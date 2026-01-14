const std = @import("std");
const Port = @import("Port.zig").Port;
const Config = @import("Config.zig").Config;

// Re-export modules for internal use
pub const port = @import("Port.zig");
pub const config = @import("Config.zig");

/// Opaque handle to a serial port
pub const SerialPortHandle = *Port;

/// Error codes for C API
pub const SerialError = enum(c_int) {
    success = 0,
    open_failed = -1,
    config_failed = -2,
    not_a_terminal = -3,
    invalid_baud = -4,
    read_error = -5,
    write_error = -6,
    timeout = -7,
    port_closed = -8,
    invalid_handle = -9,
    out_of_memory = -10,
};

/// Serial port configuration for C API
pub const SerialConfig = extern struct {
    baud_rate: u32 = 115200,
    data_bits: u8 = 8,
    parity: u8 = 0, // 0=none, 1=odd, 2=even
    stop_bits: u8 = 1,
    flow_control: u8 = 0, // 0=none, 1=hardware, 2=software
    local_echo: bool = false,
    line_ending: u8 = 0, // 0=CR, 1=LF, 2=CRLF

    fn toConfig(self: SerialConfig) Config {
        return .{
            .baud_rate = baudFromU32(self.baud_rate),
            .data_bits = switch (self.data_bits) {
                5 => .five,
                6 => .six,
                7 => .seven,
                else => .eight,
            },
            .parity = switch (self.parity) {
                1 => .odd,
                2 => .even,
                else => .none,
            },
            .stop_bits = if (self.stop_bits == 2) .two else .one,
            .flow_control = switch (self.flow_control) {
                1 => .hardware,
                2 => .software,
                else => .none,
            },
            .local_echo = self.local_echo,
            .line_ending = switch (self.line_ending) {
                1 => .lf,
                2 => .crlf,
                else => .cr,
            },
        };
    }

    fn baudFromU32(baud: u32) Config.BaudRate {
        return switch (baud) {
            300 => .B300,
            1200 => .B1200,
            2400 => .B2400,
            4800 => .B4800,
            9600 => .B9600,
            19200 => .B19200,
            38400 => .B38400,
            57600 => .B57600,
            230400 => .B230400,
            460800 => .B460800,
            921600 => .B921600,
            else => .B115200,
        };
    }
};

/// Modem status for C API
pub const ModemStatus = extern struct {
    dtr: bool = false,
    rts: bool = false,
    cts: bool = false,
    dsr: bool = false,
    dcd: bool = false,
    ri: bool = false,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// ============================================================================
// C API Functions
// ============================================================================

/// Opens a serial port
export fn serial_open(path: [*:0]const u8, cfg: *const SerialConfig, handle_out: *?SerialPortHandle) SerialError {
    const port_ptr = allocator.create(Port) catch return .out_of_memory;
    errdefer allocator.destroy(port_ptr);

    const path_slice = std.mem.span(path);
    port_ptr.* = Port.open(path_slice, cfg.toConfig()) catch |err| {
        return switch (err) {
            Port.Error.OpenFailed => .open_failed,
            Port.Error.ConfigurationFailed => .config_failed,
            Port.Error.NotATerminal => .not_a_terminal,
            Port.Error.InvalidBaudRate => .invalid_baud,
            else => .open_failed,
        };
    };

    handle_out.* = port_ptr;
    return .success;
}

/// Closes a serial port
export fn serial_close(handle: ?SerialPortHandle) void {
    if (handle) |h| {
        h.close();
        allocator.destroy(h);
    }
}

/// Reads data from the serial port
export fn serial_read(handle: ?SerialPortHandle, buffer: [*]u8, buffer_len: usize, bytes_read: *usize) SerialError {
    const h = handle orelse return .invalid_handle;
    const n = h.read(buffer[0..buffer_len]) catch |err| {
        return switch (err) {
            Port.Error.ReadError => .read_error,
            Port.Error.PortClosed => .port_closed,
            else => .read_error,
        };
    };
    bytes_read.* = n;
    return .success;
}

/// Writes data to the serial port
export fn serial_write(handle: ?SerialPortHandle, data: [*]const u8, data_len: usize, bytes_written: *usize) SerialError {
    const h = handle orelse return .invalid_handle;
    const n = h.write(data[0..data_len]) catch |err| {
        return switch (err) {
            Port.Error.WriteError => .write_error,
            Port.Error.PortClosed => .port_closed,
            else => .write_error,
        };
    };
    bytes_written.* = n;
    return .success;
}

/// Writes all data to the serial port
export fn serial_write_all(handle: ?SerialPortHandle, data: [*]const u8, data_len: usize) SerialError {
    const h = handle orelse return .invalid_handle;
    h.writeAll(data[0..data_len]) catch |err| {
        return switch (err) {
            Port.Error.WriteError => .write_error,
            Port.Error.PortClosed => .port_closed,
            else => .write_error,
        };
    };
    return .success;
}

/// Sends a break signal
export fn serial_send_break(handle: ?SerialPortHandle) SerialError {
    const h = handle orelse return .invalid_handle;
    h.sendBreak();
    return .success;
}

/// Sets the DTR line
export fn serial_set_dtr(handle: ?SerialPortHandle, state: bool) SerialError {
    const h = handle orelse return .invalid_handle;
    h.setDTR(state);
    return .success;
}

/// Sets the RTS line
export fn serial_set_rts(handle: ?SerialPortHandle, state: bool) SerialError {
    const h = handle orelse return .invalid_handle;
    h.setRTS(state);
    return .success;
}

/// Gets modem status
export fn serial_get_modem_status(handle: ?SerialPortHandle, status: *ModemStatus) SerialError {
    const h = handle orelse return .invalid_handle;
    const s = h.getModemStatus();
    status.* = .{
        .dtr = s.dtr,
        .rts = s.rts,
        .cts = s.cts,
        .dsr = s.dsr,
        .dcd = s.dcd,
        .ri = s.ri,
    };
    return .success;
}

/// Flushes input buffer
export fn serial_flush_input(handle: ?SerialPortHandle) SerialError {
    const h = handle orelse return .invalid_handle;
    h.flushInput();
    return .success;
}

/// Flushes output buffer
export fn serial_flush_output(handle: ?SerialPortHandle) SerialError {
    const h = handle orelse return .invalid_handle;
    h.flushOutput();
    return .success;
}

/// Flushes both buffers
export fn serial_flush(handle: ?SerialPortHandle) SerialError {
    const h = handle orelse return .invalid_handle;
    h.flush();
    return .success;
}

/// Returns number of bytes available to read
export fn serial_bytes_available(handle: ?SerialPortHandle) c_int {
    const h = handle orelse return 0;
    return @intCast(h.bytesAvailable());
}

/// Waits for data with timeout
export fn serial_wait_for_data(handle: ?SerialPortHandle, timeout_ms: u32) bool {
    const h = handle orelse return false;
    return h.waitForData(timeout_ms);
}

/// Gets the file descriptor (for use with select/poll)
export fn serial_get_fd(handle: ?SerialPortHandle) c_int {
    const h = handle orelse return -1;
    return h.fd;
}

// ============================================================================
// Port Enumeration
// ============================================================================

/// Callback type for port enumeration
pub const EnumCallback = *const fn (path: [*:0]const u8, context: ?*anyopaque) callconv(.C) void;

/// Enumerate available serial ports
export fn serial_enumerate_ports(callback: EnumCallback, context: ?*anyopaque) SerialError {
    const ports = port.enumeratePorts(allocator) catch return .out_of_memory;
    defer {
        for (ports) |p| allocator.free(p);
        allocator.free(ports);
    }

    for (ports) |p| {
        // Create null-terminated string
        const path_z = allocator.dupeZ(u8, p) catch continue;
        defer allocator.free(path_z);
        callback(path_z.ptr, context);
    }

    return .success;
}
