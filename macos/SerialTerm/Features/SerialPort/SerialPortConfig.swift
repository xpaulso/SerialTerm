import Foundation

/// Serial port configuration
struct SerialPortConfig: Codable, Equatable, Hashable {
    var baudRate: BaudRate = .b115200
    var dataBits: DataBits = .eight
    var parity: Parity = .none
    var stopBits: StopBits = .one
    var flowControl: FlowControl = .none
    var localEcho: Bool = false
    var lineEnding: LineEnding = .cr
    var terminalType: TerminalType = .autodetect

    /// Standard baud rates
    enum BaudRate: Int, CaseIterable, Identifiable, Codable {
        case b300 = 300
        case b1200 = 1200
        case b2400 = 2400
        case b4800 = 4800
        case b9600 = 9600
        case b19200 = 19200
        case b38400 = 38400
        case b57600 = 57600
        case b115200 = 115200
        case b230400 = 230400
        case b460800 = 460800
        case b921600 = 921600

        var id: Int { rawValue }

        var description: String {
            "\(rawValue)"
        }
    }

    /// Data bits per character
    enum DataBits: Int, CaseIterable, Identifiable, Codable {
        case five = 5
        case six = 6
        case seven = 7
        case eight = 8

        var id: Int { rawValue }

        var description: String {
            "\(rawValue)"
        }
    }

    /// Parity checking mode
    enum Parity: String, CaseIterable, Identifiable, Codable {
        case none
        case odd
        case even

        var id: String { rawValue }

        var description: String {
            rawValue.capitalized
        }

        var shortDescription: String {
            switch self {
            case .none: return "N"
            case .odd: return "O"
            case .even: return "E"
            }
        }
    }

    /// Number of stop bits
    enum StopBits: Int, CaseIterable, Identifiable, Codable {
        case one = 1
        case two = 2

        var id: Int { rawValue }

        var description: String {
            "\(rawValue)"
        }
    }

    /// Flow control method
    enum FlowControl: String, CaseIterable, Identifiable, Codable {
        case none
        case hardware // RTS/CTS
        case software // XON/XOFF

        var id: String { rawValue }

        var description: String {
            switch self {
            case .none: return "None"
            case .hardware: return "RTS/CTS"
            case .software: return "XON/XOFF"
            }
        }
    }

    /// Line ending for transmitted data
    enum LineEnding: String, CaseIterable, Identifiable, Codable {
        case cr
        case lf
        case crlf

        var id: String { rawValue }

        var description: String {
            switch self {
            case .cr: return "CR"
            case .lf: return "LF"
            case .crlf: return "CR+LF"
            }
        }

        var bytes: Data {
            switch self {
            case .cr: return Data([0x0D])
            case .lf: return Data([0x0A])
            case .crlf: return Data([0x0D, 0x0A])
            }
        }
    }

    /// Terminal type for escape sequence identification and DA responses
    enum TerminalType: String, CaseIterable, Identifiable, Codable {
        case autodetect
        case vt100
        case vt220
        case linux

        var id: String { rawValue }

        var description: String {
            switch self {
            case .autodetect: return "Auto Detect"
            case .vt100: return "VT100"
            case .vt220: return "VT220"
            case .linux: return "Linux Console"
            }
        }

        /// Primary DA response for CSI c / CSI 0 c
        var primaryDAResponse: String {
            switch self {
            case .vt100:
                return "\u{1B}[?1;2c"
            case .vt220:
                return "\u{1B}[?62;1;2;6;7;8;9c"
            case .linux:
                return "\u{1B}[?6c"
            case .autodetect:
                return "\u{1B}[?64;1;2;6;9;15;16;17;18;21;22c"
            }
        }

        /// Secondary DA response for CSI > c
        var secondaryDAResponse: String {
            switch self {
            case .vt100:
                return "\u{1B}[>0;10;0c"
            case .vt220:
                return "\u{1B}[>1;10;0c"
            case .linux:
                return "\u{1B}[>0;0;0c"
            case .autodetect:
                return "\u{1B}[>1;10;0c"
            }
        }
    }

    /// Returns a short summary string (e.g., "115200 8N1")
    var summary: String {
        "\(baudRate.rawValue) \(dataBits.rawValue)\(parity.shortDescription)\(stopBits.rawValue)"
    }

    /// Alias for toolbar display
    var shortSummary: String { summary }

    /// Common preset configurations
    static let `default` = SerialPortConfig()

    static let arduino = SerialPortConfig(
        baudRate: .b9600,
        dataBits: .eight,
        parity: .none,
        stopBits: .one,
        flowControl: .none
    )

    static let ciscoConsole = SerialPortConfig(
        baudRate: .b9600,
        dataBits: .eight,
        parity: .none,
        stopBits: .one,
        flowControl: .none
    )

    static let highSpeed = SerialPortConfig(
        baudRate: .b921600,
        dataBits: .eight,
        parity: .none,
        stopBits: .one,
        flowControl: .hardware
    )
}
