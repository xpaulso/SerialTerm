const std = @import("std");
const common = @import("common.zig");

const Control = common.Control;
const Progress = common.Progress;
const Event = common.Event;
const EventCallback = common.EventCallback;
const TransferState = common.TransferState;

/// XMODEM protocol implementation
/// Supports both checksum and CRC modes, as well as XMODEM-1K
pub const XModem = struct {
    const BLOCK_SIZE = 128;
    const BLOCK_SIZE_1K = 1024;
    const MAX_RETRIES = 10;
    const TIMEOUT_MS = 10000;

    allocator: std.mem.Allocator,
    state: State,
    mode: Mode,
    block_num: u8,
    retry_count: u8,
    callback: EventCallback,
    context: ?*anyopaque,

    // Send state
    send_data: ?[]const u8 = null,
    send_offset: usize = 0,

    // Receive state
    recv_buffer: std.ArrayList(u8),
    block_buffer: [3 + BLOCK_SIZE_1K + 2]u8 = undefined,
    block_pos: usize = 0,
    expected_block_size: usize = BLOCK_SIZE,

    pub const State = enum {
        idle,
        // Sender states
        send_waiting_for_init,
        send_block,
        send_waiting_for_ack,
        send_eot,
        send_waiting_for_eot_ack,
        // Receiver states
        recv_send_init,
        recv_waiting_for_block,
        recv_block_header,
        recv_block_data,
        recv_block_check,
        // Final states
        completed,
        failed,
        cancelled,
    };

    pub const Mode = enum {
        checksum, // Original XMODEM with 1-byte checksum
        crc, // XMODEM-CRC with CRC-16
        one_k, // XMODEM-1K with 1024-byte blocks
    };

    pub fn init(allocator: std.mem.Allocator, callback: EventCallback, context: ?*anyopaque) XModem {
        return XModem{
            .allocator = allocator,
            .state = .idle,
            .mode = .crc,
            .block_num = 1,
            .retry_count = 0,
            .callback = callback,
            .context = context,
            .recv_buffer = .empty,
        };
    }

    pub fn deinit(self: *XModem) void {
        self.recv_buffer.deinit(self.allocator);
    }

    /// Start sending a file
    pub fn startSend(self: *XModem, data: []const u8) void {
        self.state = .send_waiting_for_init;
        self.send_data = data;
        self.send_offset = 0;
        self.block_num = 1;
        self.retry_count = 0;

        self.callback(.{ .started = .{
            .file_name = null,
            .file_size = data.len,
        } }, self.context);
    }

    /// Start receiving a file
    pub fn startReceive(self: *XModem) void {
        self.state = .recv_send_init;
        self.block_num = 1;
        self.retry_count = 0;
        self.recv_buffer.clearRetainingCapacity();

        // Send 'C' to request CRC mode
        self.mode = .crc;
        self.callback(.{ .send_data = &[_]u8{Control.CRC} }, self.context);

        self.callback(.{ .started = .{
            .file_name = null,
            .file_size = 0,
        } }, self.context);

        self.state = .recv_waiting_for_block;
    }

    /// Process received byte(s) from serial port
    pub fn processData(self: *XModem, data: []const u8) void {
        for (data) |byte| {
            self.processByte(byte);
        }
    }

    fn processByte(self: *XModem, byte: u8) void {
        switch (self.state) {
            .idle => {},

            // Sender states
            .send_waiting_for_init => {
                if (byte == Control.NAK) {
                    self.mode = .checksum;
                    self.sendBlock();
                } else if (byte == Control.CRC) {
                    self.mode = .crc;
                    self.sendBlock();
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .send_waiting_for_ack => {
                if (byte == Control.ACK) {
                    self.retry_count = 0;
                    if (self.send_offset >= (self.send_data orelse &[_]u8{}).len) {
                        // All data sent, send EOT
                        self.state = .send_eot;
                        self.callback(.{ .send_data = &[_]u8{Control.EOT} }, self.context);
                        self.state = .send_waiting_for_eot_ack;
                    } else {
                        self.block_num +%= 1;
                        self.sendBlock();
                    }
                } else if (byte == Control.NAK) {
                    self.retry_count += 1;
                    if (self.retry_count > MAX_RETRIES) {
                        self.handleError("Too many retries");
                    } else {
                        self.resendBlock();
                    }
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .send_waiting_for_eot_ack => {
                if (byte == Control.ACK) {
                    self.state = .completed;
                    self.callback(.completed, self.context);
                } else if (byte == Control.NAK) {
                    self.retry_count += 1;
                    if (self.retry_count > MAX_RETRIES) {
                        self.handleError("EOT not acknowledged");
                    } else {
                        self.callback(.{ .send_data = &[_]u8{Control.EOT} }, self.context);
                    }
                }
            },

            // Receiver states
            .recv_waiting_for_block => {
                if (byte == Control.SOH) {
                    self.expected_block_size = BLOCK_SIZE;
                    self.block_pos = 0;
                    self.block_buffer[self.block_pos] = byte;
                    self.block_pos += 1;
                    self.state = .recv_block_header;
                } else if (byte == Control.STX) {
                    self.expected_block_size = BLOCK_SIZE_1K;
                    self.block_pos = 0;
                    self.block_buffer[self.block_pos] = byte;
                    self.block_pos += 1;
                    self.state = .recv_block_header;
                } else if (byte == Control.EOT) {
                    // End of transmission
                    self.callback(.{ .send_data = &[_]u8{Control.ACK} }, self.context);
                    self.state = .completed;
                    self.callback(.completed, self.context);
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .recv_block_header => {
                self.block_buffer[self.block_pos] = byte;
                self.block_pos += 1;
                if (self.block_pos >= 3) {
                    // Check block number
                    const block_num = self.block_buffer[1];
                    const block_num_inv = self.block_buffer[2];
                    if (block_num != (~block_num_inv & 0xFF)) {
                        // Block number error
                        self.sendNak();
                    } else {
                        self.state = .recv_block_data;
                    }
                }
            },

            .recv_block_data => {
                self.block_buffer[self.block_pos] = byte;
                self.block_pos += 1;

                const check_size: usize = if (self.mode == .checksum) 1 else 2;
                const total_size = 3 + self.expected_block_size + check_size;

                if (self.block_pos >= total_size) {
                    self.state = .recv_block_check;
                    self.verifyAndAcceptBlock();
                }
            },

            else => {},
        }
    }

    fn sendBlock(self: *XModem) void {
        const data = self.send_data orelse return;
        const block_size = if (self.mode == .one_k) BLOCK_SIZE_1K else BLOCK_SIZE;

        var block: [3 + BLOCK_SIZE_1K + 2]u8 = undefined;
        block[0] = if (self.mode == .one_k) Control.STX else Control.SOH;
        block[1] = self.block_num;
        block[2] = ~self.block_num;

        const remaining = data.len - self.send_offset;
        const copy_len = @min(remaining, block_size);

        @memcpy(block[3..][0..copy_len], data[self.send_offset..][0..copy_len]);

        // Pad with SUB if needed
        if (copy_len < block_size) {
            @memset(block[3 + copy_len ..][0 .. block_size - copy_len], Control.SUB);
        }

        // Calculate checksum/CRC
        const data_slice = block[3..][0..block_size];
        if (self.mode == .checksum) {
            block[3 + block_size] = common.checksum(data_slice);
            self.callback(.{ .send_data = block[0 .. 3 + block_size + 1] }, self.context);
        } else {
            const crc = common.crc16(data_slice);
            block[3 + block_size] = @intCast(crc >> 8);
            block[3 + block_size + 1] = @intCast(crc & 0xFF);
            self.callback(.{ .send_data = block[0 .. 3 + block_size + 2] }, self.context);
        }

        self.send_offset += copy_len;
        self.state = .send_waiting_for_ack;

        // Report progress
        self.callback(.{
            .progress = .{
                .state = .transferring,
                .bytes_transferred = self.send_offset,
                .total_bytes = data.len,
                .current_block = self.block_num,
                .error_count = self.retry_count,
            },
        }, self.context);
    }

    fn resendBlock(self: *XModem) void {
        // Move offset back and resend
        const block_size = if (self.mode == .one_k) BLOCK_SIZE_1K else BLOCK_SIZE;
        const data = self.send_data orelse return;

        if (self.send_offset >= block_size) {
            self.send_offset -= @min(self.send_offset, block_size);
        }
        if (self.send_offset > data.len) {
            self.send_offset = if (data.len >= block_size) data.len - block_size else 0;
        }
        self.sendBlock();
    }

    fn verifyAndAcceptBlock(self: *XModem) void {
        const block_num = self.block_buffer[1];
        const data_slice = self.block_buffer[3..][0..self.expected_block_size];
        const check_size: usize = if (self.mode == .checksum) 1 else 2;

        // Verify checksum/CRC
        const valid = if (self.mode == .checksum) blk: {
            const expected = common.checksum(data_slice);
            break :blk self.block_buffer[3 + self.expected_block_size] == expected;
        } else blk: {
            const expected = common.crc16(data_slice);
            const received = (@as(u16, self.block_buffer[3 + self.expected_block_size]) << 8) |
                @as(u16, self.block_buffer[3 + self.expected_block_size + 1]);
            break :blk received == expected;
        };

        if (!valid) {
            self.sendNak();
            return;
        }

        // Check block number
        if (block_num == self.block_num) {
            // Accept block
            self.recv_buffer.appendSlice(self.allocator, data_slice) catch {
                self.handleError("Out of memory");
                return;
            };
            self.block_num +%= 1;
            self.retry_count = 0;

            // Report progress
            self.callback(.{
                .progress = .{
                    .state = .transferring,
                    .bytes_transferred = self.recv_buffer.items.len,
                    .total_bytes = 0,
                    .current_block = block_num,
                    .error_count = self.retry_count,
                },
            }, self.context);
        } else if (block_num == self.block_num -% 1) {
            // Duplicate block, ACK but don't store
        } else {
            self.sendNak();
            return;
        }

        // Send ACK
        self.callback(.{ .send_data = &[_]u8{Control.ACK} }, self.context);
        self.state = .recv_waiting_for_block;

        _ = check_size;
    }

    fn sendNak(self: *XModem) void {
        self.retry_count += 1;
        if (self.retry_count > MAX_RETRIES) {
            self.handleError("Too many errors");
        } else {
            self.callback(.{ .send_data = &[_]u8{Control.NAK} }, self.context);
            self.state = .recv_waiting_for_block;
        }
    }

    fn handleError(self: *XModem, message: []const u8) void {
        self.state = .failed;
        // Send cancel sequence
        self.callback(.{ .send_data = &[_]u8{ Control.CAN, Control.CAN, Control.CAN } }, self.context);
        self.callback(.{ .failed = message }, self.context);
    }

    fn handleCancel(self: *XModem) void {
        self.state = .cancelled;
        self.callback(.cancelled, self.context);
    }

    /// Cancel the current transfer
    pub fn cancel(self: *XModem) void {
        if (self.state != .idle and self.state != .completed and
            self.state != .failed and self.state != .cancelled)
        {
            self.callback(.{ .send_data = &[_]u8{ Control.CAN, Control.CAN, Control.CAN } }, self.context);
            self.state = .cancelled;
            self.callback(.cancelled, self.context);
        }
    }

    /// Get received data (for receive operations)
    pub fn getReceivedData(self: *XModem) []const u8 {
        return self.recv_buffer.items;
    }

    /// Check if transfer is active
    pub fn isActive(self: *XModem) bool {
        return self.state != .idle and self.state != .completed and
            self.state != .failed and self.state != .cancelled;
    }
};

test "XMODEM CRC calculation" {
    const data = [_]u8{0x00} ** 128;
    const crc = common.crc16(&data);
    try std.testing.expect(crc != 0);
}
