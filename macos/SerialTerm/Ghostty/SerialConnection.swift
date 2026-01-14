import Foundation

/// Protocol for serial connection events
protocol SerialConnectionDelegate: AnyObject, Sendable {
    func serialConnection(_ connection: SerialConnection, didReceive data: Data)
    func serialConnection(_ connection: SerialConnection, didEncounterError error: Error)
    func serialConnectionDidDisconnect(_ connection: SerialConnection)
}

/// Errors that can occur with serial connections
enum SerialConnectionError: LocalizedError {
    case openFailed(String)
    case configurationFailed
    case notATerminal
    case readError
    case writeError
    case portClosed

    var errorDescription: String? {
        switch self {
        case .openFailed(let path):
            return "Failed to open serial port: \(path)"
        case .configurationFailed:
            return "Failed to configure serial port"
        case .notATerminal:
            return "Device is not a terminal"
        case .readError:
            return "Error reading from serial port"
        case .writeError:
            return "Error writing to serial port"
        case .portClosed:
            return "Serial port is closed"
        }
    }
}

/// Manages a serial port connection
final class SerialConnection: @unchecked Sendable {
    private var fileDescriptor: Int32 = -1
    private var originalTermios: termios?
    private let path: String
    private let config: SerialPortConfig

    private var readQueue: DispatchQueue
    private var readSource: DispatchSourceRead?

    weak var delegate: SerialConnectionDelegate?

    var isOpen: Bool { fileDescriptor >= 0 }

    init(path: String, config: SerialPortConfig, delegate: SerialConnectionDelegate? = nil) throws {
        self.path = path
        self.config = config
        self.delegate = delegate
        self.readQueue = DispatchQueue(label: "com.serialterm.read.\(path)", qos: .userInteractive)

        try open()
        try configure()
        startReading()
    }

    deinit {
        close()
    }

    private func open() throws {
        // Open the port
        fileDescriptor = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)

        if fileDescriptor < 0 {
            throw SerialConnectionError.openFailed(path)
        }

        // Verify it's a terminal
        guard isatty(fileDescriptor) != 0 else {
            Darwin.close(fileDescriptor)
            fileDescriptor = -1
            throw SerialConnectionError.notATerminal
        }

        // Save original termios
        var termios = termios()
        if tcgetattr(fileDescriptor, &termios) == 0 {
            originalTermios = termios
        }
    }

    private func configure() throws {
        var termios = termios()

        guard tcgetattr(fileDescriptor, &termios) == 0 else {
            throw SerialConnectionError.configurationFailed
        }

        // Set raw mode
        cfmakeraw(&termios)

        // Enable receiver and local mode
        termios.c_cflag |= UInt(CREAD | CLOCAL)

        // Set baud rate
        let speed = speed_t(config.baudRate.rawValue)
        cfsetispeed(&termios, speed)
        cfsetospeed(&termios, speed)

        // Set data bits
        termios.c_cflag &= ~UInt(CSIZE)
        switch config.dataBits {
        case .five: termios.c_cflag |= UInt(CS5)
        case .six: termios.c_cflag |= UInt(CS6)
        case .seven: termios.c_cflag |= UInt(CS7)
        case .eight: termios.c_cflag |= UInt(CS8)
        }

        // Set parity
        switch config.parity {
        case .none:
            termios.c_cflag &= ~UInt(PARENB)
        case .odd:
            termios.c_cflag |= UInt(PARENB | PARODD)
        case .even:
            termios.c_cflag |= UInt(PARENB)
            termios.c_cflag &= ~UInt(PARODD)
        }

        // Set stop bits
        switch config.stopBits {
        case .one:
            termios.c_cflag &= ~UInt(CSTOPB)
        case .two:
            termios.c_cflag |= UInt(CSTOPB)
        }

        // Set flow control
        switch config.flowControl {
        case .none:
            termios.c_cflag &= ~UInt(CRTSCTS)
            termios.c_iflag &= ~UInt(IXON | IXOFF | IXANY)
        case .hardware:
            termios.c_cflag |= UInt(CRTSCTS)
            termios.c_iflag &= ~UInt(IXON | IXOFF | IXANY)
        case .software:
            termios.c_cflag &= ~UInt(CRTSCTS)
            termios.c_iflag |= UInt(IXON | IXOFF | IXANY)
        }

        // Set read timeout
        termios.c_cc.16 = 0  // VMIN
        termios.c_cc.17 = 1  // VTIME (0.1 second timeout)

        // Apply settings
        guard tcsetattr(fileDescriptor, TCSANOW, &termios) == 0 else {
            throw SerialConnectionError.configurationFailed
        }

        // Use ioctl to set non-standard baud rates on macOS
        var speed_value = UInt(config.baudRate.rawValue)
        _ = ioctl(fileDescriptor, UInt(0x80045402), &speed_value)

        // Clear non-blocking flag
        var flags = fcntl(fileDescriptor, F_GETFL, 0)
        flags &= ~O_NONBLOCK
        _ = fcntl(fileDescriptor, F_SETFL, flags)
    }

    private func startReading() {
        guard fileDescriptor >= 0 else { return }

        readSource = DispatchSource.makeReadSource(fileDescriptor: fileDescriptor, queue: readQueue)

        readSource?.setEventHandler { [weak self] in
            self?.handleRead()
        }

        readSource?.setCancelHandler { [weak self] in
            self?.readSource = nil
        }

        readSource?.resume()
    }

    private func handleRead() {
        var buffer = [UInt8](repeating: 0, count: 4096)

        let bytesRead = read(fileDescriptor, &buffer, buffer.count)

        if bytesRead > 0 {
            let data = Data(buffer[0..<bytesRead])
            delegate?.serialConnection(self, didReceive: data)
        } else if bytesRead < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
            delegate?.serialConnection(self, didEncounterError: SerialConnectionError.readError)
        }
    }

    func write(_ data: Data) {
        guard fileDescriptor >= 0 else { return }

        data.withUnsafeBytes { buffer in
            var written = 0
            while written < data.count {
                let result = Darwin.write(fileDescriptor, buffer.baseAddress! + written, data.count - written)
                if result < 0 {
                    delegate?.serialConnection(self, didEncounterError: SerialConnectionError.writeError)
                    return
                }
                written += result
            }
        }
    }

    func sendBreak() {
        guard fileDescriptor >= 0 else { return }
        _ = tcsendbreak(fileDescriptor, 0)
    }

    func setDTR(_ state: Bool) {
        guard fileDescriptor >= 0 else { return }

        var status: Int32 = 0
        _ = ioctl(fileDescriptor, UInt(TIOCMGET), &status)

        if state {
            status |= TIOCM_DTR
        } else {
            status &= ~TIOCM_DTR
        }

        _ = ioctl(fileDescriptor, UInt(TIOCMSET), &status)
    }

    func setRTS(_ state: Bool) {
        guard fileDescriptor >= 0 else { return }

        var status: Int32 = 0
        _ = ioctl(fileDescriptor, UInt(TIOCMGET), &status)

        if state {
            status |= TIOCM_RTS
        } else {
            status &= ~TIOCM_RTS
        }

        _ = ioctl(fileDescriptor, UInt(TIOCMSET), &status)
    }

    func getModemStatus() -> (dtr: Bool, rts: Bool, cts: Bool, dsr: Bool, dcd: Bool, ri: Bool) {
        guard fileDescriptor >= 0 else {
            return (false, false, false, false, false, false)
        }

        var status: Int32 = 0
        _ = ioctl(fileDescriptor, UInt(TIOCMGET), &status)

        return (
            dtr: (status & TIOCM_DTR) != 0,
            rts: (status & TIOCM_RTS) != 0,
            cts: (status & TIOCM_CTS) != 0,
            dsr: (status & TIOCM_DSR) != 0,
            dcd: (status & TIOCM_CD) != 0,
            ri: (status & TIOCM_RI) != 0
        )
    }

    func flushInput() {
        guard fileDescriptor >= 0 else { return }
        _ = tcflush(fileDescriptor, TCIFLUSH)
    }

    func flushOutput() {
        guard fileDescriptor >= 0 else { return }
        _ = tcflush(fileDescriptor, TCOFLUSH)
    }

    func close() {
        readSource?.cancel()
        readSource = nil

        if fileDescriptor >= 0 {
            // Restore original termios
            if var original = originalTermios {
                _ = tcsetattr(fileDescriptor, TCSANOW, &original)
            }

            Darwin.close(fileDescriptor)
            fileDescriptor = -1

            delegate?.serialConnectionDidDisconnect(self)
        }
    }
}
