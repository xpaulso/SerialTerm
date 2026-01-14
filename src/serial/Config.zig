const std = @import("std");

/// Serial port configuration parameters
pub const Config = struct {
    baud_rate: BaudRate = .B115200,
    data_bits: DataBits = .eight,
    parity: Parity = .none,
    stop_bits: StopBits = .one,
    flow_control: FlowControl = .none,
    local_echo: bool = false,
    line_ending: LineEnding = .cr,

    /// Standard baud rates
    pub const BaudRate = enum(u32) {
        B300 = 300,
        B1200 = 1200,
        B2400 = 2400,
        B4800 = 4800,
        B9600 = 9600,
        B19200 = 19200,
        B38400 = 38400,
        B57600 = 57600,
        B115200 = 115200,
        B230400 = 230400,
        B460800 = 460800,
        B921600 = 921600,

        pub fn toSpeed(self: BaudRate) u32 {
            return @intFromEnum(self);
        }
    };

    /// Data bits per character
    pub const DataBits = enum(u8) {
        five = 5,
        six = 6,
        seven = 7,
        eight = 8,

        pub fn toMask(self: DataBits) u32 {
            return switch (self) {
                .five => 0x00, // CS5
                .six => 0x10, // CS6
                .seven => 0x20, // CS7
                .eight => 0x30, // CS8
            };
        }
    };

    /// Parity checking mode
    pub const Parity = enum {
        none,
        odd,
        even,
        mark,
        space,
    };

    /// Number of stop bits
    pub const StopBits = enum {
        one,
        two,
    };

    /// Flow control method
    pub const FlowControl = enum {
        none,
        hardware, // RTS/CTS
        software, // XON/XOFF
    };

    /// Line ending for transmitted data
    pub const LineEnding = enum {
        cr, // Carriage Return only
        lf, // Line Feed only
        crlf, // Both CR and LF

        pub fn bytes(self: LineEnding) []const u8 {
            return switch (self) {
                .cr => "\r",
                .lf => "\n",
                .crlf => "\r\n",
            };
        }
    };

    /// Returns the configuration as a string for display
    pub fn formatString(self: Config, buf: []u8) ![]u8 {
        const parity_char: u8 = switch (self.parity) {
            .none => 'N',
            .odd => 'O',
            .even => 'E',
            .mark => 'M',
            .space => 'S',
        };
        const stop_bits: u8 = switch (self.stop_bits) {
            .one => '1',
            .two => '2',
        };
        const flow_str = switch (self.flow_control) {
            .none => "None",
            .hardware => "RTS/CTS",
            .software => "XON/XOFF",
        };

        return std.fmt.bufPrint(buf, "{d} {d}{c}{c} {s}", .{
            self.baud_rate.toSpeed(),
            @as(u8, @intFromEnum(self.data_bits)),
            parity_char,
            stop_bits,
            flow_str,
        });
    }

    /// Common preset configurations
    pub const presets = struct {
        pub const default_8n1 = Config{
            .baud_rate = .B115200,
            .data_bits = .eight,
            .parity = .none,
            .stop_bits = .one,
            .flow_control = .none,
        };

        pub const arduino = Config{
            .baud_rate = .B9600,
            .data_bits = .eight,
            .parity = .none,
            .stop_bits = .one,
            .flow_control = .none,
        };

        pub const cisco_console = Config{
            .baud_rate = .B9600,
            .data_bits = .eight,
            .parity = .none,
            .stop_bits = .one,
            .flow_control = .none,
        };

        pub const modem = Config{
            .baud_rate = .B57600,
            .data_bits = .eight,
            .parity = .none,
            .stop_bits = .one,
            .flow_control = .hardware,
        };
    };
};

test "Config format string" {
    var buf: [64]u8 = undefined;
    const cfg = Config{};
    const result = try cfg.formatString(&buf);
    try std.testing.expectEqualStrings("115200 8N1 None", result);
}

test "Config presets" {
    const arduino = Config.presets.arduino;
    try std.testing.expectEqual(@as(u32, 9600), arduino.baud_rate.toSpeed());
    try std.testing.expectEqual(Config.DataBits.eight, arduino.data_bits);
}
