const std = @import("std");
const builtin = @import("builtin");
const Config = @import("Config.zig").Config;

/// Platform-specific constants
const c = if (builtin.os.tag == .macos) @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("sys/ioctl.h");
    @cInclude("IOKit/serial/ioss.h");
}) else @cImport({
    @cInclude("termios.h");
    @cInclude("unistd.h");
    @cInclude("fcntl.h");
    @cInclude("sys/ioctl.h");
});

/// Serial port abstraction for macOS/POSIX systems
pub const Port = struct {
    fd: std.posix.fd_t,
    path: []const u8,
    original_termios: std.posix.termios,
    config: Config,

    pub const Error = error{
        OpenFailed,
        ConfigurationFailed,
        NotATerminal,
        InvalidBaudRate,
        ReadError,
        WriteError,
        Timeout,
        PortClosed,
    } || std.posix.OpenError || std.posix.TermiosGetError || std.posix.TermiosSetError;

    /// Opens a serial port with the specified configuration
    pub fn open(path: []const u8, config: Config) Error!Port {
        // Open the port
        const fd = std.posix.open(path, .{
            .ACCMODE = .RDWR,
            .NOCTTY = true,
            .NONBLOCK = true,
        }, 0) catch |err| {
            return err;
        };
        errdefer std.posix.close(fd);

        // Verify it's a terminal device
        if (!std.posix.isatty(fd)) {
            return Error.NotATerminal;
        }

        // Get current termios settings
        const original = std.posix.tcgetattr(fd) catch |err| {
            return err;
        };

        // Create new termios with raw mode
        var termios = original;

        // Set raw mode (cfmakeraw equivalent)
        // Input flags
        termios.iflag.IGNBRK = false;
        termios.iflag.BRKINT = false;
        termios.iflag.PARMRK = false;
        termios.iflag.ISTRIP = false;
        termios.iflag.INLCR = false;
        termios.iflag.IGNCR = false;
        termios.iflag.ICRNL = false;
        termios.iflag.IXON = false;
        termios.iflag.IXOFF = false;
        termios.iflag.IXANY = false;

        // Output flags
        termios.oflag.OPOST = false;

        // Local flags
        termios.lflag.ECHO = false;
        termios.lflag.ECHONL = false;
        termios.lflag.ICANON = false;
        termios.lflag.ISIG = false;
        termios.lflag.IEXTEN = false;

        // Control flags - clear size bits
        termios.cflag.CSIZE = .CS8;
        termios.cflag.PARENB = false;
        termios.cflag.CSTOPB = false;
        // Hardware flow control (macOS uses separate flags)
        termios.cflag.CCTS_OFLOW = false;
        termios.cflag.CRTS_IFLOW = false;

        // Enable receiver and set local mode
        termios.cflag.CREAD = true;
        termios.cflag.CLOCAL = true;

        // Apply data bits
        termios.cflag.CSIZE = switch (config.data_bits) {
            .five => .CS5,
            .six => .CS6,
            .seven => .CS7,
            .eight => .CS8,
        };

        // Apply parity
        switch (config.parity) {
            .none => {
                termios.cflag.PARENB = false;
            },
            .odd => {
                termios.cflag.PARENB = true;
                termios.cflag.PARODD = true;
            },
            .even => {
                termios.cflag.PARENB = true;
                termios.cflag.PARODD = false;
            },
            .mark, .space => {
                // Mark/Space parity requires special handling
                termios.cflag.PARENB = true;
            },
        }

        // Apply stop bits
        termios.cflag.CSTOPB = config.stop_bits == .two;

        // Apply flow control
        switch (config.flow_control) {
            .none => {
                termios.cflag.CCTS_OFLOW = false;
                termios.cflag.CRTS_IFLOW = false;
                termios.iflag.IXON = false;
                termios.iflag.IXOFF = false;
            },
            .hardware => {
                termios.cflag.CCTS_OFLOW = true;
                termios.cflag.CRTS_IFLOW = true;
                termios.iflag.IXON = false;
                termios.iflag.IXOFF = false;
            },
            .software => {
                termios.cflag.CCTS_OFLOW = false;
                termios.cflag.CRTS_IFLOW = false;
                termios.iflag.IXON = true;
                termios.iflag.IXOFF = true;
            },
        }

        // Set read timeout behavior
        // VMIN = 0, VTIME = 1 means return immediately with available data or after 100ms
        termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        termios.cc[@intFromEnum(std.posix.V.TIME)] = 1;

        // Apply the termios settings
        std.posix.tcsetattr(fd, .FLUSH, termios) catch |err| {
            return err;
        };

        // Set baud rate (macOS-specific for non-standard rates)
        if (builtin.os.tag == .macos) {
            const speed: c_ulong = config.baud_rate.toSpeed();
            if (c.ioctl(fd, c.IOSSIOSPEED, &speed) < 0) {
                // Fall back to standard cfsetspeed for standard rates
                const baud_const = baudToConst(config.baud_rate) orelse return Error.InvalidBaudRate;
                // Cast Zig termios to C termios pointer for cfsetspeed
                const c_termios_ptr: [*c]c.struct_termios = @ptrCast(&termios);
                _ = c.cfsetspeed(c_termios_ptr, baud_const);
                std.posix.tcsetattr(fd, .FLUSH, termios) catch |err| {
                    return err;
                };
            }
        } else {
            // Linux/POSIX standard baud rate setting
            const baud_const = baudToConst(config.baud_rate) orelse return Error.InvalidBaudRate;
            // Cast Zig termios to C termios pointer
            const c_termios_ptr: [*c]c.struct_termios = @ptrCast(&termios);
            _ = c.cfsetispeed(c_termios_ptr, baud_const);
            _ = c.cfsetospeed(c_termios_ptr, baud_const);
            std.posix.tcsetattr(fd, .FLUSH, termios) catch |err| {
                return err;
            };
        }

        // Clear the NONBLOCK flag now that configuration is done
        const flags = std.posix.fcntl(fd, c.F_GETFL, 0) catch 0;
        _ = std.posix.fcntl(fd, c.F_SETFL, flags & ~@as(usize, c.O_NONBLOCK)) catch {};

        return Port{
            .fd = fd,
            .path = path,
            .original_termios = original,
            .config = config,
        };
    }

    /// Closes the serial port and restores original settings
    pub fn close(self: *Port) void {
        // Restore original termios settings
        std.posix.tcsetattr(self.fd, .FLUSH, self.original_termios) catch {};
        std.posix.close(self.fd);
        self.fd = -1;
    }

    /// Reads data from the serial port
    pub fn read(self: *Port, buffer: []u8) Error!usize {
        if (self.fd < 0) return Error.PortClosed;
        return std.posix.read(self.fd, buffer) catch return Error.ReadError;
    }

    /// Writes data to the serial port
    pub fn write(self: *Port, data: []const u8) Error!usize {
        if (self.fd < 0) return Error.PortClosed;
        return std.posix.write(self.fd, data) catch return Error.WriteError;
    }

    /// Writes all data to the serial port, handling partial writes
    pub fn writeAll(self: *Port, data: []const u8) Error!void {
        var written: usize = 0;
        while (written < data.len) {
            written += try self.write(data[written..]);
        }
    }

    /// Sends a break signal
    pub fn sendBreak(self: *Port) void {
        if (self.fd < 0) return;
        _ = c.tcsendbreak(self.fd, 0);
    }

    /// Sets the DTR (Data Terminal Ready) signal
    pub fn setDTR(self: *Port, state: bool) void {
        if (self.fd < 0) return;
        var status: c_int = 0;
        _ = c.ioctl(self.fd, c.TIOCMGET, &status);
        if (state) {
            status |= c.TIOCM_DTR;
        } else {
            status &= ~@as(c_int, c.TIOCM_DTR);
        }
        _ = c.ioctl(self.fd, c.TIOCMSET, &status);
    }

    /// Sets the RTS (Request To Send) signal
    pub fn setRTS(self: *Port, state: bool) void {
        if (self.fd < 0) return;
        var status: c_int = 0;
        _ = c.ioctl(self.fd, c.TIOCMGET, &status);
        if (state) {
            status |= c.TIOCM_RTS;
        } else {
            status &= ~@as(c_int, c.TIOCM_RTS);
        }
        _ = c.ioctl(self.fd, c.TIOCMSET, &status);
    }

    /// Gets the current modem status lines
    pub fn getModemStatus(self: *Port) ModemStatus {
        if (self.fd < 0) return .{};
        var status: c_int = 0;
        _ = c.ioctl(self.fd, c.TIOCMGET, &status);
        return .{
            .dtr = (status & c.TIOCM_DTR) != 0,
            .rts = (status & c.TIOCM_RTS) != 0,
            .cts = (status & c.TIOCM_CTS) != 0,
            .dsr = (status & c.TIOCM_DSR) != 0,
            .dcd = (status & c.TIOCM_CD) != 0,
            .ri = (status & c.TIOCM_RI) != 0,
        };
    }

    /// Flushes the input buffer
    pub fn flushInput(self: *Port) void {
        if (self.fd < 0) return;
        _ = c.tcflush(self.fd, c.TCIFLUSH);
    }

    /// Flushes the output buffer
    pub fn flushOutput(self: *Port) void {
        if (self.fd < 0) return;
        _ = c.tcflush(self.fd, c.TCOFLUSH);
    }

    /// Flushes both input and output buffers
    pub fn flush(self: *Port) void {
        if (self.fd < 0) return;
        _ = c.tcflush(self.fd, c.TCIOFLUSH);
    }

    /// Returns the number of bytes available to read
    pub fn bytesAvailable(self: *Port) usize {
        if (self.fd < 0) return 0;
        var bytes: c_int = 0;
        if (c.ioctl(self.fd, c.FIONREAD, &bytes) < 0) {
            return 0;
        }
        return @intCast(@max(0, bytes));
    }

    /// Waits for data to be available with timeout (in milliseconds)
    pub fn waitForData(self: *Port, timeout_ms: u32) bool {
        if (self.fd < 0) return false;

        var fds = [_]std.posix.pollfd{.{
            .fd = self.fd,
            .events = std.posix.POLL.IN,
            .revents = 0,
        }};

        const result = std.posix.poll(&fds, @intCast(timeout_ms)) catch return false;
        return result > 0 and (fds[0].revents & std.posix.POLL.IN) != 0;
    }

    /// Modem status line states
    pub const ModemStatus = struct {
        dtr: bool = false, // Data Terminal Ready
        rts: bool = false, // Request To Send
        cts: bool = false, // Clear To Send
        dsr: bool = false, // Data Set Ready
        dcd: bool = false, // Data Carrier Detect
        ri: bool = false, // Ring Indicator
    };

    /// Convert BaudRate to termios constant
    fn baudToConst(baud: Config.BaudRate) ?c.speed_t {
        return switch (baud) {
            .B300 => c.B300,
            .B1200 => c.B1200,
            .B2400 => c.B2400,
            .B4800 => c.B4800,
            .B9600 => c.B9600,
            .B19200 => c.B19200,
            .B38400 => c.B38400,
            .B57600 => c.B57600,
            .B115200 => c.B115200,
            .B230400 => c.B230400,
            else => null, // Non-standard rates need IOSSIOSPEED on macOS
        };
    }
};

/// Enumerate available serial ports on the system
pub fn enumeratePorts(allocator: std.mem.Allocator) ![][]const u8 {
    var ports = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (ports.items) |p| allocator.free(p);
        ports.deinit();
    }

    // On macOS, look for /dev/cu.* devices
    var dev_dir = std.fs.openDirAbsolute("/dev", .{ .iterate = true }) catch return ports.toOwnedSlice();
    defer dev_dir.close();

    var iter = dev_dir.iterate();
    while (iter.next() catch null) |entry| {
        if (std.mem.startsWith(u8, entry.name, "cu.")) {
            const full_path = try std.fmt.allocPrint(allocator, "/dev/{s}", .{entry.name});
            try ports.append(full_path);
        }
    }

    return ports.toOwnedSlice();
}

test "enumeratePorts" {
    const allocator = std.testing.allocator;
    const ports = try enumeratePorts(allocator);
    defer {
        for (ports) |p| allocator.free(p);
        allocator.free(ports);
    }
    // Just verify it doesn't crash - actual ports depend on system
}
