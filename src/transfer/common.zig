const std = @import("std");

/// CRC-16-CCITT calculation (used by XMODEM-CRC and YMODEM)
pub fn crc16(data: []const u8) u16 {
    var crc: u16 = 0;
    for (data) |byte| {
        crc ^= @as(u16, byte) << 8;
        for (0..8) |_| {
            if (crc & 0x8000 != 0) {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}

/// CRC-32 calculation (used by ZMODEM)
pub fn crc32(data: []const u8) u32 {
    const table = comptime blk: {
        var t: [256]u32 = undefined;
        for (0..256) |i| {
            var c: u32 = @intCast(i);
            for (0..8) |_| {
                if (c & 1 != 0) {
                    c = (c >> 1) ^ 0xEDB88320;
                } else {
                    c >>= 1;
                }
            }
            t[i] = c;
        }
        break :blk t;
    };

    var crc: u32 = 0xFFFFFFFF;
    for (data) |byte| {
        crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return ~crc;
}

/// Simple checksum (used by XMODEM-Checksum)
pub fn checksum(data: []const u8) u8 {
    var sum: u8 = 0;
    for (data) |byte| {
        sum +%= byte;
    }
    return sum;
}

/// Transfer direction
pub const Direction = enum {
    send,
    receive,
};

/// Transfer state
pub const TransferState = enum {
    idle,
    starting,
    transferring,
    completing,
    completed,
    cancelled,
    failed,
};

/// Transfer progress information
pub const Progress = struct {
    state: TransferState = .idle,
    bytes_transferred: u64 = 0,
    total_bytes: u64 = 0,
    current_block: u32 = 0,
    total_blocks: u32 = 0,
    error_count: u32 = 0,
    file_name: ?[]const u8 = null,

    pub fn percentComplete(self: Progress) f32 {
        if (self.total_bytes == 0) return 0;
        return @as(f32, @floatFromInt(self.bytes_transferred)) / @as(f32, @floatFromInt(self.total_bytes)) * 100.0;
    }
};

/// Transfer event types
pub const Event = union(enum) {
    /// Transfer started
    started: struct {
        file_name: ?[]const u8,
        file_size: u64,
    },
    /// Progress update
    progress: Progress,
    /// Data to send over serial
    send_data: []const u8,
    /// Transfer completed successfully
    completed: void,
    /// Transfer failed
    failed: []const u8,
    /// Transfer cancelled
    cancelled: void,
};

/// Callback type for transfer events
pub const EventCallback = *const fn (event: Event, context: ?*anyopaque) void;

/// Protocol control characters
pub const Control = struct {
    pub const NUL: u8 = 0x00;
    pub const SOH: u8 = 0x01; // Start of Header (128-byte block)
    pub const STX: u8 = 0x02; // Start of Header (1024-byte block)
    pub const EOT: u8 = 0x04; // End of Transmission
    pub const ACK: u8 = 0x06; // Acknowledge
    pub const NAK: u8 = 0x15; // Negative Acknowledge
    pub const CAN: u8 = 0x18; // Cancel
    pub const SUB: u8 = 0x1A; // Substitute (padding)
    pub const CRC: u8 = 'C'; // CRC mode request
};

test "crc16 calculation" {
    // Test with known values
    const data = "123456789";
    const result = crc16(data);
    try std.testing.expectEqual(@as(u16, 0x29B1), result);
}

test "crc32 calculation" {
    // Test with known values
    const data = "123456789";
    const result = crc32(data);
    try std.testing.expectEqual(@as(u32, 0xCBF43926), result);
}

test "checksum calculation" {
    const data = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const result = checksum(&data);
    try std.testing.expectEqual(@as(u8, 0x0A), result);
}
