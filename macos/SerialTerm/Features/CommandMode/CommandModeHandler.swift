import Foundation
import Combine

/// Handles escape character sequences for command mode
/// Default escape is Ctrl+A (like picocom)
final class CommandModeHandler: ObservableObject {
    @Published var isInCommandMode = false

    /// Configurable escape character (default: Ctrl+A = 0x01)
    var escapeCharacter: UInt8 = 0x01

    private var lastKeyWasEscape = false
    private var escapeTimeoutTask: Task<Void, Never>?

    /// Available commands
    enum Command {
        case quit                  // Ctrl+A, Q - Disconnect
        case sendBreak            // Ctrl+A, B - Send break signal
        case toggleDTR            // Ctrl+A, D - Toggle DTR line
        case toggleRTS            // Ctrl+A, R - Toggle RTS line (lowercase)
        case uploadXMODEM         // Ctrl+A, X - Upload via XMODEM
        case uploadYMODEM         // Ctrl+A, Y - Upload via YMODEM
        case uploadZMODEM         // Ctrl+A, Z - Upload via ZMODEM
        case downloadReceive      // Ctrl+A, Shift+R - Receive download
        case showHelp             // Ctrl+A, H or ? - Show help
        case sendEscape           // Ctrl+A, Ctrl+A - Send literal escape character
        case toggleLocalEcho      // Ctrl+A, E - Toggle local echo
        case clearScreen          // Ctrl+A, C - Clear terminal
        case showPortSettings     // Ctrl+A, S - Show port settings
    }

    /// Process a key input
    /// Returns (consumed: Bool, command: Command?)
    /// - consumed: true if the key was handled by command mode
    /// - command: the command to execute, if any
    func processKey(_ key: UInt8) -> (consumed: Bool, command: Command?) {
        // Cancel any pending timeout
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil

        if lastKeyWasEscape {
            lastKeyWasEscape = false
            isInCommandMode = false

            // Process command key
            switch key {
            case escapeCharacter:
                // Double escape sends literal escape character
                return (true, .sendEscape)

            case UInt8(ascii: "q"), UInt8(ascii: "Q"):
                return (true, .quit)

            case UInt8(ascii: "b"), UInt8(ascii: "B"):
                return (true, .sendBreak)

            case UInt8(ascii: "d"), UInt8(ascii: "D"):
                return (true, .toggleDTR)

            case UInt8(ascii: "r"):
                return (true, .toggleRTS)

            case UInt8(ascii: "R"):
                return (true, .downloadReceive)

            case UInt8(ascii: "x"), UInt8(ascii: "X"):
                return (true, .uploadXMODEM)

            case UInt8(ascii: "y"), UInt8(ascii: "Y"):
                return (true, .uploadYMODEM)

            case UInt8(ascii: "z"), UInt8(ascii: "Z"):
                return (true, .uploadZMODEM)

            case UInt8(ascii: "h"), UInt8(ascii: "H"), UInt8(ascii: "?"):
                return (true, .showHelp)

            case UInt8(ascii: "e"), UInt8(ascii: "E"):
                return (true, .toggleLocalEcho)

            case UInt8(ascii: "c"), UInt8(ascii: "C"):
                return (true, .clearScreen)

            case UInt8(ascii: "s"), UInt8(ascii: "S"):
                return (true, .showPortSettings)

            default:
                // Unknown command, just consume it
                return (true, nil)
            }
        }

        // Check for escape character
        if key == escapeCharacter {
            lastKeyWasEscape = true
            isInCommandMode = true

            // Set timeout to auto-cancel command mode after 2 seconds
            escapeTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    if self.lastKeyWasEscape {
                        self.lastKeyWasEscape = false
                        self.isInCommandMode = false
                    }
                }
            }

            return (true, nil)
        }

        // Not in command mode, don't consume the key
        return (false, nil)
    }

    /// Reset command mode state
    func reset() {
        lastKeyWasEscape = false
        isInCommandMode = false
        escapeTimeoutTask?.cancel()
        escapeTimeoutTask = nil
    }
}
