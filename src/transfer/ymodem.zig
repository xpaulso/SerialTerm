const std = @import("std");
const common = @import("common.zig");

const Control = common.Control;
const Progress = common.Progress;
const Event = common.Event;
const EventCallback = common.EventCallback;
const TransferState = common.TransferState;

/// YMODEM protocol implementation
/// Extension of XMODEM with file name/size in block 0 and batch transfers
pub const YModem = struct {
    const BLOCK_SIZE = 128;
    const BLOCK_SIZE_1K = 1024;
    const MAX_RETRIES = 10;

    state: State,
    block_num: u8,
    retry_count: u8,
    callback: EventCallback,
    context: ?*anyopaque,

    // File info
    file_name: [256]u8 = undefined,
    file_name_len: usize = 0,
    file_size: u64 = 0,

    // Send state
    send_data: ?[]const u8 = null,
    send_offset: usize = 0,

    // Receive state
    recv_buffer: std.ArrayList(u8),
    block_buffer: [3 + BLOCK_SIZE_1K + 2]u8 = undefined,
    block_pos: usize = 0,
    expected_block_size: usize = BLOCK_SIZE_1K,
    bytes_remaining: u64 = 0,

    pub const State = enum {
        idle,
        // Sender states
        send_waiting_for_init,
        send_block0,
        send_waiting_for_block0_ack,
        send_waiting_for_data_init,
        send_block,
        send_waiting_for_ack,
        send_eot,
        send_waiting_for_eot_ack,
        send_final_block0,
        send_waiting_for_final_ack,
        // Receiver states
        recv_send_init,
        recv_waiting_for_block0,
        recv_block0_header,
        recv_block0_data,
        recv_waiting_for_data_init,
        recv_waiting_for_block,
        recv_block_header,
        recv_block_data,
        // Final states
        completed,
        failed,
        cancelled,
    };

    pub fn init(allocator: std.mem.Allocator, callback: EventCallback, context: ?*anyopaque) YModem {
        return YModem{
            .state = .idle,
            .block_num = 0,
            .retry_count = 0,
            .callback = callback,
            .context = context,
            .recv_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *YModem) void {
        self.recv_buffer.deinit();
    }

    /// Start sending a file
    pub fn startSend(self: *YModem, file_name: []const u8, data: []const u8) void {
        self.state = .send_waiting_for_init;
        self.send_data = data;
        self.send_offset = 0;
        self.block_num = 0;
        self.retry_count = 0;
        self.file_size = data.len;

        // Store file name
        const copy_len = @min(file_name.len, self.file_name.len - 1);
        @memcpy(self.file_name[0..copy_len], file_name[0..copy_len]);
        self.file_name_len = copy_len;

        self.callback(.{ .started = .{
            .file_name = self.file_name[0..self.file_name_len],
            .file_size = data.len,
        } }, self.context);
    }

    /// Start receiving files
    pub fn startReceive(self: *YModem) void {
        self.state = .recv_send_init;
        self.block_num = 0;
        self.retry_count = 0;
        self.recv_buffer.clearRetainingCapacity();
        self.file_name_len = 0;
        self.file_size = 0;
        self.bytes_remaining = 0;

        // Send 'C' to request CRC mode
        self.callback(.{ .send_data = &[_]u8{Control.CRC} }, self.context);
        self.state = .recv_waiting_for_block0;

        self.callback(.{ .started = .{
            .file_name = null,
            .file_size = 0,
        } }, self.context);
    }

    /// Process received data
    pub fn processData(self: *YModem, data: []const u8) void {
        for (data) |byte| {
            self.processByte(byte);
        }
    }

    fn processByte(self: *YModem, byte: u8) void {
        switch (self.state) {
            .idle => {},

            // Sender states
            .send_waiting_for_init => {
                if (byte == Control.CRC) {
                    self.sendBlock0();
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .send_waiting_for_block0_ack => {
                if (byte == Control.ACK) {
                    self.state = .send_waiting_for_data_init;
                } else if (byte == Control.NAK) {
                    self.handleRetry(&YModem.sendBlock0);
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .send_waiting_for_data_init => {
                if (byte == Control.CRC) {
                    self.block_num = 1;
                    self.sendBlock();
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .send_waiting_for_ack => {
                if (byte == Control.ACK) {
                    self.retry_count = 0;
                    if (self.send_offset >= (self.send_data orelse &[_]u8{}).len) {
                        self.sendEOT();
                    } else {
                        self.block_num +%= 1;
                        self.sendBlock();
                    }
                } else if (byte == Control.NAK) {
                    self.handleRetry(&YModem.resendBlock);
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .send_waiting_for_eot_ack => {
                if (byte == Control.NAK) {
                    // First NAK after EOT, send EOT again
                    self.callback(.{ .send_data = &[_]u8{Control.EOT} }, self.context);
                } else if (byte == Control.ACK) {
                    // Send empty block 0 to signal end of batch
                    self.state = .send_final_block0;
                    self.sendFinalBlock0();
                } else if (byte == Control.CRC) {
                    // Receiver ready for next file, send empty block 0
                    self.sendFinalBlock0();
                }
            },

            .send_waiting_for_final_ack => {
                if (byte == Control.ACK) {
                    self.state = .completed;
                    self.callback(.completed, self.context);
                }
            },

            // Receiver states
            .recv_waiting_for_block0 => {
                if (byte == Control.SOH) {
                    self.expected_block_size = BLOCK_SIZE;
                    self.block_pos = 0;
                    self.block_buffer[self.block_pos] = byte;
                    self.block_pos += 1;
                    self.state = .recv_block0_header;
                } else if (byte == Control.STX) {
                    self.expected_block_size = BLOCK_SIZE_1K;
                    self.block_pos = 0;
                    self.block_buffer[self.block_pos] = byte;
                    self.block_pos += 1;
                    self.state = .recv_block0_header;
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .recv_block0_header => {
                self.block_buffer[self.block_pos] = byte;
                self.block_pos += 1;
                if (self.block_pos >= 3) {
                    self.state = .recv_block0_data;
                }
            },

            .recv_block0_data => {
                self.block_buffer[self.block_pos] = byte;
                self.block_pos += 1;

                const total_size = 3 + self.expected_block_size + 2;
                if (self.block_pos >= total_size) {
                    self.processBlock0();
                }
            },

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
                    // Send NAK first (YMODEM quirk)
                    self.callback(.{ .send_data = &[_]u8{Control.NAK} }, self.context);
                    // Then wait for second EOT
                    // Actually, simplified: just ACK and complete
                    self.callback(.{ .send_data = &[_]u8{Control.ACK} }, self.context);
                    // Send C to indicate ready for next file
                    self.callback(.{ .send_data = &[_]u8{Control.CRC} }, self.context);
                    self.state = .recv_waiting_for_block0;
                    self.block_num = 0;
                } else if (byte == Control.CAN) {
                    self.handleCancel();
                }
            },

            .recv_block_header => {
                self.block_buffer[self.block_pos] = byte;
                self.block_pos += 1;
                if (self.block_pos >= 3) {
                    self.state = .recv_block_data;
                }
            },

            .recv_block_data => {
                self.block_buffer[self.block_pos] = byte;
                self.block_pos += 1;

                const total_size = 3 + self.expected_block_size + 2;
                if (self.block_pos >= total_size) {
                    self.verifyAndAcceptBlock();
                }
            },

            else => {},
        }
    }

    fn sendBlock0(self: *YModem) void {
        var block: [3 + BLOCK_SIZE_1K + 2]u8 = undefined;
        block[0] = Control.STX; // Use 1K blocks for header
        block[1] = 0;
        block[2] = 0xFF;

        // Fill with zeros first
        @memset(block[3..][0..BLOCK_SIZE_1K], 0);

        // Copy filename
        @memcpy(block[3..][0..self.file_name_len], self.file_name[0..self.file_name_len]);

        // Add null terminator and file size
        var pos: usize = 3 + self.file_name_len;
        block[pos] = 0;
        pos += 1;

        // Write file size as decimal string
        var size_buf: [32]u8 = undefined;
        const size_str = std.fmt.bufPrint(&size_buf, "{d}", .{self.file_size}) catch "0";
        @memcpy(block[pos..][0..size_str.len], size_str);

        // Calculate CRC
        const data_slice = block[3..][0..BLOCK_SIZE_1K];
        const crc = common.crc16(data_slice);
        block[3 + BLOCK_SIZE_1K] = @intCast(crc >> 8);
        block[3 + BLOCK_SIZE_1K + 1] = @intCast(crc & 0xFF);

        self.callback(.{ .send_data = block[0 .. 3 + BLOCK_SIZE_1K + 2] }, self.context);
        self.state = .send_waiting_for_block0_ack;
    }

    fn sendBlock(self: *YModem) void {
        const data = self.send_data orelse return;

        var block: [3 + BLOCK_SIZE_1K + 2]u8 = undefined;
        block[0] = Control.STX;
        block[1] = self.block_num;
        block[2] = ~self.block_num;

        const remaining = data.len - self.send_offset;
        const copy_len = @min(remaining, BLOCK_SIZE_1K);

        @memcpy(block[3..][0..copy_len], data[self.send_offset..][0..copy_len]);

        // Pad with SUB if needed
        if (copy_len < BLOCK_SIZE_1K) {
            @memset(block[3 + copy_len ..][0 .. BLOCK_SIZE_1K - copy_len], Control.SUB);
        }

        // Calculate CRC
        const data_slice = block[3..][0..BLOCK_SIZE_1K];
        const crc = common.crc16(data_slice);
        block[3 + BLOCK_SIZE_1K] = @intCast(crc >> 8);
        block[3 + BLOCK_SIZE_1K + 1] = @intCast(crc & 0xFF);

        self.callback(.{ .send_data = block[0 .. 3 + BLOCK_SIZE_1K + 2] }, self.context);
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
                .file_name = self.file_name[0..self.file_name_len],
            },
        }, self.context);
    }

    fn resendBlock(self: *YModem) void {
        const data = self.send_data orelse return;
        if (self.send_offset >= BLOCK_SIZE_1K) {
            self.send_offset -= BLOCK_SIZE_1K;
        }
        if (self.send_offset > data.len) {
            self.send_offset = if (data.len >= BLOCK_SIZE_1K) data.len - BLOCK_SIZE_1K else 0;
        }
        self.sendBlock();
    }

    fn sendEOT(self: *YModem) void {
        self.callback(.{ .send_data = &[_]u8{Control.EOT} }, self.context);
        self.state = .send_waiting_for_eot_ack;
    }

    fn sendFinalBlock0(self: *YModem) void {
        // Empty block 0 signals end of batch
        var block: [3 + BLOCK_SIZE + 2]u8 = undefined;
        block[0] = Control.SOH;
        block[1] = 0;
        block[2] = 0xFF;
        @memset(block[3..][0..BLOCK_SIZE], 0);

        const crc = common.crc16(block[3..][0..BLOCK_SIZE]);
        block[3 + BLOCK_SIZE] = @intCast(crc >> 8);
        block[3 + BLOCK_SIZE + 1] = @intCast(crc & 0xFF);

        self.callback(.{ .send_data = block[0 .. 3 + BLOCK_SIZE + 2] }, self.context);
        self.state = .send_waiting_for_final_ack;
    }

    fn processBlock0(self: *YModem) void {
        const data_slice = self.block_buffer[3..][0..self.expected_block_size];

        // Verify CRC
        const expected = common.crc16(data_slice);
        const received = (@as(u16, self.block_buffer[3 + self.expected_block_size]) << 8) |
            @as(u16, self.block_buffer[3 + self.expected_block_size + 1]);

        if (received != expected) {
            self.sendNak();
            return;
        }

        // Check for empty block (end of batch)
        if (data_slice[0] == 0) {
            self.callback(.{ .send_data = &[_]u8{Control.ACK} }, self.context);
            self.state = .completed;
            self.callback(.completed, self.context);
            return;
        }

        // Parse filename
        var i: usize = 0;
        while (i < data_slice.len and data_slice[i] != 0) : (i += 1) {
            self.file_name[i] = data_slice[i];
        }
        self.file_name_len = i;

        // Parse file size
        i += 1; // Skip null
        var size: u64 = 0;
        while (i < data_slice.len and data_slice[i] >= '0' and data_slice[i] <= '9') : (i += 1) {
            size = size * 10 + (data_slice[i] - '0');
        }
        self.file_size = size;
        self.bytes_remaining = size;

        // ACK block 0 and send C to start data transfer
        self.callback(.{ .send_data = &[_]u8{Control.ACK} }, self.context);
        self.callback(.{ .send_data = &[_]u8{Control.CRC} }, self.context);

        self.block_num = 1;
        self.state = .recv_waiting_for_block;

        // Report file info
        self.callback(.{ .started = .{
            .file_name = self.file_name[0..self.file_name_len],
            .file_size = self.file_size,
        } }, self.context);
    }

    fn verifyAndAcceptBlock(self: *YModem) void {
        const block_num = self.block_buffer[1];
        const data_slice = self.block_buffer[3..][0..self.expected_block_size];

        // Verify CRC
        const expected = common.crc16(data_slice);
        const received = (@as(u16, self.block_buffer[3 + self.expected_block_size]) << 8) |
            @as(u16, self.block_buffer[3 + self.expected_block_size + 1]);

        if (received != expected) {
            self.sendNak();
            return;
        }

        // Check block number
        if (block_num == self.block_num) {
            // Calculate how much actual data to store
            const store_len = @min(self.expected_block_size, self.bytes_remaining);
            self.recv_buffer.appendSlice(data_slice[0..store_len]) catch {
                self.handleError("Out of memory");
                return;
            };
            self.bytes_remaining -= store_len;
            self.block_num +%= 1;
            self.retry_count = 0;

            // Report progress
            self.callback(.{
                .progress = .{
                    .state = .transferring,
                    .bytes_transferred = self.recv_buffer.items.len,
                    .total_bytes = self.file_size,
                    .current_block = block_num,
                    .error_count = self.retry_count,
                    .file_name = self.file_name[0..self.file_name_len],
                },
            }, self.context);
        }

        self.callback(.{ .send_data = &[_]u8{Control.ACK} }, self.context);
        self.state = .recv_waiting_for_block;
    }

    fn sendNak(self: *YModem) void {
        self.retry_count += 1;
        if (self.retry_count > MAX_RETRIES) {
            self.handleError("Too many errors");
        } else {
            self.callback(.{ .send_data = &[_]u8{Control.NAK} }, self.context);
        }
    }

    fn handleRetry(self: *YModem, retry_fn: *const fn (*YModem) void) void {
        self.retry_count += 1;
        if (self.retry_count > MAX_RETRIES) {
            self.handleError("Too many retries");
        } else {
            retry_fn(self);
        }
    }

    fn handleError(self: *YModem, message: []const u8) void {
        self.state = .failed;
        self.callback(.{ .send_data = &[_]u8{ Control.CAN, Control.CAN, Control.CAN } }, self.context);
        self.callback(.{ .failed = message }, self.context);
    }

    fn handleCancel(self: *YModem) void {
        self.state = .cancelled;
        self.callback(.cancelled, self.context);
    }

    pub fn cancel(self: *YModem) void {
        if (self.state != .idle and self.state != .completed and
            self.state != .failed and self.state != .cancelled)
        {
            self.callback(.{ .send_data = &[_]u8{ Control.CAN, Control.CAN, Control.CAN } }, self.context);
            self.state = .cancelled;
            self.callback(.cancelled, self.context);
        }
    }

    pub fn getReceivedData(self: *YModem) []const u8 {
        return self.recv_buffer.items;
    }

    pub fn getFileName(self: *YModem) ?[]const u8 {
        if (self.file_name_len > 0) {
            return self.file_name[0..self.file_name_len];
        }
        return null;
    }

    pub fn isActive(self: *YModem) bool {
        return self.state != .idle and self.state != .completed and
            self.state != .failed and self.state != .cancelled;
    }
};
