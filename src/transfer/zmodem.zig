const std = @import("std");
const common = @import("common.zig");

const Progress = common.Progress;
const Event = common.Event;
const EventCallback = common.EventCallback;
const TransferState = common.TransferState;

/// ZMODEM protocol implementation
/// Full-featured protocol with auto-start, streaming, and crash recovery
pub const ZModem = struct {
    // Frame types
    const ZRQINIT: u8 = 0; // Request receive init
    const ZRINIT: u8 = 1; // Receive init
    const ZSINIT: u8 = 2; // Send init sequence
    const ZACK: u8 = 3; // ACK
    const ZFILE: u8 = 4; // File name from sender
    const ZSKIP: u8 = 5; // Skip this file
    const ZNAK: u8 = 6; // NAK
    const ZABORT: u8 = 7; // Abort
    const ZFIN: u8 = 8; // Finish session
    const ZRPOS: u8 = 9; // Resume data at position
    const ZDATA: u8 = 10; // Data packet follows
    const ZEOF: u8 = 11; // End of file
    const ZFERR: u8 = 12; // File error
    const ZCRC: u8 = 13; // Request for file CRC
    const ZCHALLENGE: u8 = 14;
    const ZCOMPL: u8 = 15; // Request complete
    const ZCAN: u8 = 16; // Cancel
    const ZFREECNT: u8 = 17;
    const ZCOMMAND: u8 = 18;
    const ZSTDERR: u8 = 19;

    // Special bytes
    const ZPAD: u8 = '*';
    const ZDLE: u8 = 0x18;
    const ZDLEE: u8 = 0x58;
    const ZBIN: u8 = 'A'; // Binary frame
    const ZHEX: u8 = 'B'; // Hex frame
    const ZBIN32: u8 = 'C'; // 32-bit CRC binary

    // Subpacket types
    const ZCRCW: u8 = 'h'; // CRC follows, sender waits
    const ZCRCE: u8 = 'i'; // CRC follows, no more data
    const ZCRCG: u8 = 'j'; // CRC follows, more data coming
    const ZCRCQ: u8 = 'k'; // CRC follows, sender should respond

    // ZRINIT capability flags
    const CANFDX: u8 = 0x01; // Full duplex
    const CANOVIO: u8 = 0x02; // Can overlap I/O
    const CANBRK: u8 = 0x04; // Can send break
    const CANCRY: u8 = 0x08; // Can encrypt
    const CANLZW: u8 = 0x10; // Can LZW compress
    const CANFC32: u8 = 0x20; // Can use 32-bit CRC
    const ESCCTL: u8 = 0x40; // Control chars escaped
    const ESC8: u8 = 0x80; // 8th bit escaped

    const MAX_BLOCK_SIZE = 8192;
    const MAX_RETRIES = 10;

    // Auto-start detection string
    pub const AUTOSTART_SEQ = "rz\r**\x18B";

    state: State,
    callback: EventCallback,
    context: ?*anyopaque,

    // File info
    file_name: [256]u8 = undefined,
    file_name_len: usize = 0,
    file_size: u64 = 0,
    file_pos: u64 = 0,

    // Send state
    send_data: ?[]const u8 = null,
    send_offset: usize = 0,

    // Receive state
    recv_buffer: std.ArrayList(u8),

    // Frame parsing state
    frame_buffer: [MAX_BLOCK_SIZE + 64]u8 = undefined,
    frame_pos: usize = 0,
    escaped: bool = false,
    use_crc32: bool = true,

    // Protocol state
    retry_count: u8 = 0,
    rx_capabilities: u8 = CANFDX | CANOVIO | CANFC32,

    pub const State = enum {
        idle,
        // Auto-start detection
        detecting_autostart,
        // Sender states
        send_zrqinit,
        send_waiting_zrinit,
        send_zfile,
        send_waiting_zrpos,
        send_data,
        send_waiting_zack,
        send_zeof,
        send_zfin,
        send_waiting_zfin,
        // Receiver states
        recv_zrinit_sent,
        recv_waiting_zfile,
        recv_zrpos_sent,
        recv_waiting_zdata,
        recv_data,
        recv_zfin_sent,
        // Final states
        completed,
        failed,
        cancelled,
    };

    pub fn init(allocator: std.mem.Allocator, callback: EventCallback, context: ?*anyopaque) ZModem {
        return ZModem{
            .state = .idle,
            .callback = callback,
            .context = context,
            .recv_buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *ZModem) void {
        self.recv_buffer.deinit();
    }

    /// Check if data contains ZMODEM auto-start sequence
    pub fn detectAutoStart(data: []const u8) bool {
        // Look for "rz\r" or ZRQINIT header
        if (std.mem.indexOf(u8, data, "rz\r") != null) return true;
        if (std.mem.indexOf(u8, data, "**\x18B") != null) return true;
        return false;
    }

    /// Start sending a file
    pub fn startSend(self: *ZModem, file_name: []const u8, data: []const u8) void {
        self.state = .send_zrqinit;
        self.send_data = data;
        self.send_offset = 0;
        self.file_size = data.len;
        self.file_pos = 0;
        self.retry_count = 0;

        // Store filename
        const copy_len = @min(file_name.len, self.file_name.len - 1);
        @memcpy(self.file_name[0..copy_len], file_name[0..copy_len]);
        self.file_name_len = copy_len;

        // Send ZRQINIT
        self.sendZRQINIT();

        self.callback(.{ .started = .{
            .file_name = self.file_name[0..self.file_name_len],
            .file_size = data.len,
        } }, self.context);
    }

    /// Start receiving files
    pub fn startReceive(self: *ZModem) void {
        self.state = .recv_zrinit_sent;
        self.file_name_len = 0;
        self.file_size = 0;
        self.file_pos = 0;
        self.retry_count = 0;
        self.recv_buffer.clearRetainingCapacity();

        // Send ZRINIT
        self.sendZRINIT();

        self.callback(.{ .started = .{
            .file_name = null,
            .file_size = 0,
        } }, self.context);
    }

    /// Process received data
    pub fn processData(self: *ZModem, data: []const u8) void {
        for (data) |byte| {
            self.processByte(byte);
        }
    }

    fn processByte(self: *ZModem, byte: u8) void {
        // Handle escaping
        if (self.escaped) {
            self.escaped = false;
            const actual = switch (byte) {
                ZDLEE => ZDLE,
                'h' => 0x80 | 'h', // ZCRCW escaped
                'i' => 0x80 | 'i', // ZCRCE escaped
                'j' => 0x80 | 'j', // ZCRCG escaped
                'k' => 0x80 | 'k', // ZCRCQ escaped
                'l', 'm', '@' => byte ^ 0x40, // Other control chars
                else => byte ^ 0x40,
            };
            self.addToFrame(actual);
            return;
        }

        if (byte == ZDLE) {
            self.escaped = true;
            return;
        }

        self.addToFrame(byte);
    }

    fn addToFrame(self: *ZModem, byte: u8) void {
        switch (self.state) {
            .idle => {
                // Look for frame start
                if (byte == ZPAD) {
                    self.frame_pos = 0;
                    self.frame_buffer[self.frame_pos] = byte;
                    self.frame_pos += 1;
                }
            },

            .send_waiting_zrinit => {
                self.frame_buffer[self.frame_pos] = byte;
                self.frame_pos += 1;
                if (self.tryParseFrame()) |frame| {
                    if (frame.frame_type == ZRINIT) {
                        // Got ZRINIT, extract capabilities
                        self.rx_capabilities = frame.data[0];
                        self.use_crc32 = (self.rx_capabilities & CANFC32) != 0;
                        // Send ZFILE
                        self.sendZFILE();
                        self.state = .send_waiting_zrpos;
                    }
                }
            },

            .send_waiting_zrpos => {
                self.frame_buffer[self.frame_pos] = byte;
                self.frame_pos += 1;
                if (self.tryParseFrame()) |frame| {
                    if (frame.frame_type == ZRPOS) {
                        // Resume from position
                        self.file_pos = frame.getPosition();
                        self.send_offset = @intCast(self.file_pos);
                        // Start sending data
                        self.sendDataPackets();
                    } else if (frame.frame_type == ZSKIP) {
                        // File skipped
                        self.state = .completed;
                        self.callback(.completed, self.context);
                    }
                }
            },

            .send_waiting_zack => {
                self.frame_buffer[self.frame_pos] = byte;
                self.frame_pos += 1;
                if (self.tryParseFrame()) |frame| {
                    if (frame.frame_type == ZACK) {
                        // Continue sending or finish
                        if (self.send_offset >= (self.send_data orelse &[_]u8{}).len) {
                            self.sendZEOF();
                        } else {
                            self.sendDataPackets();
                        }
                    } else if (frame.frame_type == ZRPOS) {
                        // Resend from position
                        self.file_pos = frame.getPosition();
                        self.send_offset = @intCast(self.file_pos);
                        self.sendDataPackets();
                    }
                }
            },

            .recv_zrinit_sent, .recv_waiting_zfile => {
                self.frame_buffer[self.frame_pos] = byte;
                self.frame_pos += 1;
                if (self.tryParseFrame()) |frame| {
                    if (frame.frame_type == ZRQINIT) {
                        // Sender requesting init, resend ZRINIT
                        self.sendZRINIT();
                    } else if (frame.frame_type == ZFILE) {
                        // Parse file info from data subpacket
                        self.parseFileInfo(frame.data);
                        // Send ZRPOS to start from position 0
                        self.sendZRPOS(0);
                        self.state = .recv_waiting_zdata;
                    } else if (frame.frame_type == ZFIN) {
                        // Session complete
                        self.sendZFIN();
                        self.state = .completed;
                        self.callback(.completed, self.context);
                    }
                }
            },

            .recv_waiting_zdata => {
                self.frame_buffer[self.frame_pos] = byte;
                self.frame_pos += 1;
                if (self.tryParseFrame()) |frame| {
                    if (frame.frame_type == ZDATA) {
                        self.file_pos = frame.getPosition();
                        self.state = .recv_data;
                    }
                }
            },

            .recv_data => {
                // Accumulate data until subpacket end
                self.frame_buffer[self.frame_pos] = byte;
                self.frame_pos += 1;

                // Check for subpacket end (simplified)
                if (self.frame_pos > 4 and self.checkSubpacketEnd()) {
                    self.processDataSubpacket();
                }
            },

            else => {
                // Accumulate in frame buffer
                if (self.frame_pos < self.frame_buffer.len) {
                    self.frame_buffer[self.frame_pos] = byte;
                    self.frame_pos += 1;
                }
            },
        }
    }

    const Frame = struct {
        frame_type: u8,
        data: []const u8,

        fn getPosition(self: Frame) u64 {
            if (self.data.len < 4) return 0;
            return @as(u64, self.data[0]) |
                (@as(u64, self.data[1]) << 8) |
                (@as(u64, self.data[2]) << 16) |
                (@as(u64, self.data[3]) << 24);
        }
    };

    fn tryParseFrame(self: *ZModem) ?Frame {
        if (self.frame_pos < 5) return null;

        // Look for hex frame header: ZPAD ZPAD ZDLE ZHEX
        var start: usize = 0;
        while (start + 4 < self.frame_pos) : (start += 1) {
            if (self.frame_buffer[start] == ZPAD and
                self.frame_buffer[start + 1] == ZPAD and
                self.frame_buffer[start + 2] == ZDLE and
                self.frame_buffer[start + 3] == ZHEX)
            {
                // Found hex frame, parse it
                return self.parseHexFrame(start + 4);
            } else if (self.frame_buffer[start] == ZPAD and
                self.frame_buffer[start + 1] == ZDLE and
                self.frame_buffer[start + 2] == ZBIN)
            {
                // Found binary frame
                return self.parseBinFrame(start + 3);
            } else if (self.frame_buffer[start] == ZPAD and
                self.frame_buffer[start + 1] == ZDLE and
                self.frame_buffer[start + 2] == ZBIN32)
            {
                // Found 32-bit CRC binary frame
                return self.parseBin32Frame(start + 3);
            }
        }
        return null;
    }

    fn parseHexFrame(self: *ZModem, start: usize) ?Frame {
        // Hex frame format: type (2 hex chars) + data (8 hex chars) + CRC (4 hex chars)
        if (start + 14 > self.frame_pos) return null;

        const frame_type = self.hexToByte(self.frame_buffer[start], self.frame_buffer[start + 1]) orelse return null;

        // Reset frame for next parse
        self.frame_pos = 0;

        return Frame{
            .frame_type = frame_type,
            .data = self.frame_buffer[start + 2 .. start + 10],
        };
    }

    fn parseBinFrame(self: *ZModem, start: usize) ?Frame {
        if (start + 7 > self.frame_pos) return null;

        const frame_type = self.frame_buffer[start];
        self.frame_pos = 0;

        return Frame{
            .frame_type = frame_type,
            .data = self.frame_buffer[start + 1 .. start + 5],
        };
    }

    fn parseBin32Frame(self: *ZModem, start: usize) ?Frame {
        if (start + 9 > self.frame_pos) return null;

        const frame_type = self.frame_buffer[start];
        self.frame_pos = 0;

        return Frame{
            .frame_type = frame_type,
            .data = self.frame_buffer[start + 1 .. start + 5],
        };
    }

    fn hexToByte(self: *ZModem, high: u8, low: u8) ?u8 {
        _ = self;
        const h = hexDigit(high) orelse return null;
        const l = hexDigit(low) orelse return null;
        return (h << 4) | l;
    }

    fn hexDigit(c: u8) ?u4 {
        if (c >= '0' and c <= '9') return @intCast(c - '0');
        if (c >= 'a' and c <= 'f') return @intCast(c - 'a' + 10);
        if (c >= 'A' and c <= 'F') return @intCast(c - 'A' + 10);
        return null;
    }

    fn checkSubpacketEnd(self: *ZModem) bool {
        // Check for CRC subpacket terminator
        if (self.frame_pos < 2) return false;
        const last = self.frame_buffer[self.frame_pos - 1];
        return last == ZCRCE or last == ZCRCG or last == ZCRCQ or last == ZCRCW;
    }

    fn processDataSubpacket(self: *ZModem) void {
        // Extract data (excluding CRC and type byte)
        const data_end = self.frame_pos - (if (self.use_crc32) @as(usize, 5) else @as(usize, 3));
        if (data_end > 0) {
            self.recv_buffer.appendSlice(self.frame_buffer[0..data_end]) catch {
                self.handleError("Out of memory");
                return;
            };
            self.file_pos += data_end;
        }

        const subpacket_type = self.frame_buffer[self.frame_pos - (if (self.use_crc32) @as(usize, 5) else @as(usize, 3))];

        // Report progress
        self.callback(.{
            .progress = .{
                .state = .transferring,
                .bytes_transferred = self.recv_buffer.items.len,
                .total_bytes = self.file_size,
                .current_block = @intCast(self.file_pos / 1024),
                .error_count = self.retry_count,
                .file_name = if (self.file_name_len > 0) self.file_name[0..self.file_name_len] else null,
            },
        }, self.context);

        self.frame_pos = 0;

        if (subpacket_type == ZCRCE or subpacket_type == ZCRCW) {
            // Wait for next frame
            self.state = .recv_waiting_zdata;
        }

        _ = subpacket_type;
    }

    fn parseFileInfo(self: *ZModem, data: []const u8) void {
        // File info format: filename\0size mode date\0
        var i: usize = 0;
        while (i < data.len and data[i] != 0) : (i += 1) {
            if (i < self.file_name.len) {
                self.file_name[i] = data[i];
            }
        }
        self.file_name_len = @min(i, self.file_name.len);

        // Parse size
        i += 1;
        var size: u64 = 0;
        while (i < data.len and data[i] >= '0' and data[i] <= '9') : (i += 1) {
            size = size * 10 + (data[i] - '0');
        }
        self.file_size = size;

        self.callback(.{ .started = .{
            .file_name = self.file_name[0..self.file_name_len],
            .file_size = self.file_size,
        } }, self.context);
    }

    fn sendZRQINIT(self: *ZModem) void {
        // Send hex ZRQINIT frame
        var buf: [32]u8 = undefined;
        const len = self.buildHexFrame(&buf, ZRQINIT, &[_]u8{ 0, 0, 0, 0 });
        self.callback(.{ .send_data = buf[0..len] }, self.context);
        self.state = .send_waiting_zrinit;
    }

    fn sendZRINIT(self: *ZModem) void {
        // Send ZRINIT with capabilities
        var buf: [32]u8 = undefined;
        const len = self.buildHexFrame(&buf, ZRINIT, &[_]u8{
            self.rx_capabilities, // ZF0 - capabilities
            0, // ZF1
            0, // ZF2
            0, // ZF3
        });
        self.callback(.{ .send_data = buf[0..len] }, self.context);
    }

    fn sendZFILE(self: *ZModem) void {
        // Send ZFILE header
        var buf: [32]u8 = undefined;
        const len = self.buildHexFrame(&buf, ZFILE, &[_]u8{ 0, 0, 0, 0 });
        self.callback(.{ .send_data = buf[0..len] }, self.context);

        // Send filename data subpacket
        var data_buf: [512]u8 = undefined;
        var pos: usize = 0;

        // Copy filename
        @memcpy(data_buf[pos..][0..self.file_name_len], self.file_name[0..self.file_name_len]);
        pos += self.file_name_len;
        data_buf[pos] = 0;
        pos += 1;

        // Add file size
        var size_str: [32]u8 = undefined;
        const size_len = std.fmt.bufPrint(&size_str, "{d}", .{self.file_size}) catch {
            return;
        };
        @memcpy(data_buf[pos..][0..size_len.len], size_len);
        pos += size_len.len;
        data_buf[pos] = 0;
        pos += 1;

        self.sendDataSubpacket(data_buf[0..pos], ZCRCW);
    }

    fn sendZRPOS(self: *ZModem, pos: u64) void {
        var buf: [32]u8 = undefined;
        const len = self.buildHexFrame(&buf, ZRPOS, &[_]u8{
            @intCast(pos & 0xFF),
            @intCast((pos >> 8) & 0xFF),
            @intCast((pos >> 16) & 0xFF),
            @intCast((pos >> 24) & 0xFF),
        });
        self.callback(.{ .send_data = buf[0..len] }, self.context);
    }

    fn sendZEOF(self: *ZModem) void {
        var buf: [32]u8 = undefined;
        const len = self.buildHexFrame(&buf, ZEOF, &[_]u8{
            @intCast(self.file_pos & 0xFF),
            @intCast((self.file_pos >> 8) & 0xFF),
            @intCast((self.file_pos >> 16) & 0xFF),
            @intCast((self.file_pos >> 24) & 0xFF),
        });
        self.callback(.{ .send_data = buf[0..len] }, self.context);
        self.state = .send_zfin;
    }

    fn sendZFIN(self: *ZModem) void {
        var buf: [32]u8 = undefined;
        const len = self.buildHexFrame(&buf, ZFIN, &[_]u8{ 0, 0, 0, 0 });
        self.callback(.{ .send_data = buf[0..len] }, self.context);
    }

    fn sendDataPackets(self: *ZModem) void {
        const data = self.send_data orelse return;

        // Send ZDATA header
        var buf: [32]u8 = undefined;
        const len = self.buildHexFrame(&buf, ZDATA, &[_]u8{
            @intCast(self.file_pos & 0xFF),
            @intCast((self.file_pos >> 8) & 0xFF),
            @intCast((self.file_pos >> 16) & 0xFF),
            @intCast((self.file_pos >> 24) & 0xFF),
        });
        self.callback(.{ .send_data = buf[0..len] }, self.context);

        // Send data subpackets
        while (self.send_offset < data.len) {
            const remaining = data.len - self.send_offset;
            const chunk_size = @min(remaining, 1024);
            const is_last = self.send_offset + chunk_size >= data.len;

            self.sendDataSubpacket(
                data[self.send_offset..][0..chunk_size],
                if (is_last) ZCRCE else ZCRCG,
            );

            self.send_offset += chunk_size;
            self.file_pos += chunk_size;

            // Report progress
            self.callback(.{
                .progress = .{
                    .state = .transferring,
                    .bytes_transferred = self.send_offset,
                    .total_bytes = data.len,
                    .current_block = @intCast(self.file_pos / 1024),
                    .error_count = self.retry_count,
                    .file_name = self.file_name[0..self.file_name_len],
                },
            }, self.context);
        }

        self.state = .send_waiting_zack;
    }

    fn sendDataSubpacket(self: *ZModem, data: []const u8, subpacket_type: u8) void {
        var buf: [MAX_BLOCK_SIZE + 64]u8 = undefined;
        var pos: usize = 0;

        // Escape and copy data
        for (data) |byte| {
            if (self.needsEscape(byte)) {
                buf[pos] = ZDLE;
                pos += 1;
                buf[pos] = byte ^ 0x40;
                pos += 1;
            } else {
                buf[pos] = byte;
                pos += 1;
            }
        }

        // Add subpacket type
        buf[pos] = ZDLE;
        pos += 1;
        buf[pos] = subpacket_type;
        pos += 1;

        // Add CRC (simplified - using CRC-16 for now)
        const crc = common.crc16(data);
        buf[pos] = @intCast((crc >> 8) & 0xFF);
        pos += 1;
        buf[pos] = @intCast(crc & 0xFF);
        pos += 1;

        self.callback(.{ .send_data = buf[0..pos] }, self.context);
    }

    fn buildHexFrame(self: *ZModem, buf: []u8, frame_type: u8, data: []const u8) usize {
        _ = self;
        var pos: usize = 0;

        // Header: ZPAD ZPAD ZDLE ZHEX
        buf[pos] = ZPAD;
        pos += 1;
        buf[pos] = ZPAD;
        pos += 1;
        buf[pos] = ZDLE;
        pos += 1;
        buf[pos] = ZHEX;
        pos += 1;

        // Frame type (2 hex chars)
        buf[pos] = toHex(frame_type >> 4);
        pos += 1;
        buf[pos] = toHex(frame_type & 0x0F);
        pos += 1;

        // Data (8 hex chars for 4 bytes)
        for (data[0..4]) |byte| {
            buf[pos] = toHex(byte >> 4);
            pos += 1;
            buf[pos] = toHex(byte & 0x0F);
            pos += 1;
        }

        // CRC-16 (4 hex chars)
        var crc_data: [5]u8 = undefined;
        crc_data[0] = frame_type;
        @memcpy(crc_data[1..5], data[0..4]);
        const crc = common.crc16(&crc_data);
        buf[pos] = toHex(@intCast((crc >> 12) & 0x0F));
        pos += 1;
        buf[pos] = toHex(@intCast((crc >> 8) & 0x0F));
        pos += 1;
        buf[pos] = toHex(@intCast((crc >> 4) & 0x0F));
        pos += 1;
        buf[pos] = toHex(@intCast(crc & 0x0F));
        pos += 1;

        // Line terminator
        buf[pos] = '\r';
        pos += 1;
        buf[pos] = '\n';
        pos += 1;

        // XON (for hex frames)
        buf[pos] = 0x11;
        pos += 1;

        return pos;
    }

    fn toHex(value: u4) u8 {
        if (value < 10) return '0' + value;
        return 'a' + value - 10;
    }

    fn needsEscape(self: *ZModem, byte: u8) bool {
        _ = self;
        return byte == ZDLE or byte < 0x20 or byte == 0x7F or byte == 0xFF;
    }

    fn handleError(self: *ZModem, message: []const u8) void {
        self.state = .failed;
        // Send ZCAN
        const cancel = [_]u8{ ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8 };
        self.callback(.{ .send_data = &cancel }, self.context);
        self.callback(.{ .failed = message }, self.context);
    }

    pub fn cancel(self: *ZModem) void {
        if (self.state != .idle and self.state != .completed and
            self.state != .failed and self.state != .cancelled)
        {
            const cancel_seq = [_]u8{ ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, ZDLE, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8 };
            self.callback(.{ .send_data = &cancel_seq }, self.context);
            self.state = .cancelled;
            self.callback(.cancelled, self.context);
        }
    }

    pub fn getReceivedData(self: *ZModem) []const u8 {
        return self.recv_buffer.items;
    }

    pub fn getFileName(self: *ZModem) ?[]const u8 {
        if (self.file_name_len > 0) {
            return self.file_name[0..self.file_name_len];
        }
        return null;
    }

    pub fn isActive(self: *ZModem) bool {
        return self.state != .idle and self.state != .completed and
            self.state != .failed and self.state != .cancelled;
    }
};
