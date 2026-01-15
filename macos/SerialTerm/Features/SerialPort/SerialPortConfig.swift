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
