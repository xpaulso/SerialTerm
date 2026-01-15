import SwiftUI

// MARK: - Focused Values for Multi-Window Support

struct FocusedAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var appState: AppState? {
        get { self[FocusedAppStateKey.self] }
        set { self[FocusedAppStateKey.self] = newValue }
    }
}

@main
struct SerialTermApp: App {
    @StateObject private var portManager = SerialPortManager()

    var body: some Scene {
        WindowGroup {
            TerminalWindowView()
                .environmentObject(portManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SerialCommands(portManager: portManager)
            TransferCommands()
            SessionCommands()
        }

        Settings {
            SettingsView()
        }

        Window("Session History", id: "session-history") {
            SessionHistoryView()
        }

        Window("Connection Profiles", id: "profiles") {
            ProfilesView()
                .environmentObject(portManager)
        }

        Window("Session Logs", id: "logs") {
            LogsView()
        }
    }
}

// MARK: - Terminal Window View (Per-Window State)

struct TerminalWindowView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .focusedValue(\.appState, appState)
    }
}

// MARK: - Main Application State

@MainActor
final class AppState: ObservableObject {
    @Published var currentPort: SerialPortInfo?
    @Published var portConfig = SerialPortConfig()
    @Published var isConnected = false
    @Published var showConnectionSheet = false
    @Published var showTransferSheet = false
    @Published var localEcho = false
    @Published var dtrState = true
    @Published var rtsState = true

    // Terminal state
    @Published var terminalOutput: [UInt8] = []
    @Published var statusMessage: String = "Disconnected"

    // Transfer state
    @Published var activeTransfer: TransferState?

    // Session management
    let historyManager = SessionHistoryManager.shared
    let profileManager = ProfileManager.shared
    let sessionLogger = SessionLogger()

    @Published var isLogging = false

    /// Serial connection handle
    var serialConnection: SerialConnection?

    func connect(to port: SerialPortInfo, config: SerialPortConfig) {
        disconnect()

        do {
            serialConnection = try SerialConnection(
                path: port.path,
                config: config,
                delegate: self
            )
            currentPort = port
            portConfig = config
            isConnected = true
            statusMessage = "Connected to \(port.name)"
            localEcho = config.localEcho

            // Record in history
            historyManager.startSession(portPath: port.path, portName: port.name, config: config)

        } catch {
            statusMessage = "Failed to connect: \(error.localizedDescription)"
        }
    }

    func connect(to profile: ConnectionProfile) {
        let portInfo = SerialPortInfo(
            id: profile.portPath,
            path: profile.portPath,
            name: profile.portPath.components(separatedBy: "/").last ?? profile.portPath,
            vendorID: nil,
            productID: nil
        )
        connect(to: portInfo, config: profile.config)
    }

    func disconnect() {
        serialConnection?.close()
        serialConnection = nil
        isConnected = false
        currentPort = nil
        statusMessage = "Disconnected"
    }

    func send(_ data: Data) {
        serialConnection?.write(data)

        if localEcho {
            terminalOutput.append(contentsOf: data)
        }

        // Log sent data
        if isLogging {
            sessionLogger.logSent(data)
        }

        // Update stats
        historyManager.updateStats(bytesSent: data.count)
    }

    func send(_ string: String) {
        if let data = string.data(using: .utf8) {
            send(data)
        }
    }

    func sendBreak() {
        serialConnection?.sendBreak()
        sessionLogger.logMessage("Break signal sent")
    }

    func toggleDTR() {
        dtrState.toggle()
        serialConnection?.setDTR(dtrState)
        sessionLogger.logMessage("DTR: \(dtrState ? "ON" : "OFF")")
    }

    func toggleRTS() {
        rtsState.toggle()
        serialConnection?.setRTS(rtsState)
        sessionLogger.logMessage("RTS: \(rtsState ? "ON" : "OFF")")
    }

    func clearTerminal() {
        terminalOutput.removeAll()
    }

    func startLogging() {
        try? sessionLogger.startLogging(sessionName: currentPort?.name ?? "unknown")
        isLogging = true
    }

    func stopLogging() {
        sessionLogger.stopLogging()
        isLogging = false
    }
}

// MARK: - Serial Connection Delegate

extension AppState: SerialConnectionDelegate {
    nonisolated func serialConnection(_ connection: SerialConnection, didReceive data: Data) {
        Task { @MainActor in
            terminalOutput.append(contentsOf: data)

            // Log received data
            if isLogging {
                sessionLogger.logReceived(data)
            }

            // Update stats
            historyManager.updateStats(bytesReceived: data.count)
        }
    }

    nonisolated func serialConnection(_ connection: SerialConnection, didEncounterError error: Error) {
        Task { @MainActor in
            statusMessage = "Error: \(error.localizedDescription)"
            sessionLogger.logMessage("Error: \(error.localizedDescription)")
        }
    }

    nonisolated func serialConnectionDidDisconnect(_ connection: SerialConnection) {
        Task { @MainActor in
            isConnected = false
            currentPort = nil
            statusMessage = "Connection closed"
            sessionLogger.logMessage("Connection closed")
        }
    }
}

// MARK: - Supporting Types

struct TransferState {
    enum TransferDirection {
        case send
        case receive
    }

    enum TransferProtocol: String {
        case xmodem = "XMODEM"
        case ymodem = "YMODEM"
        case zmodem = "ZMODEM"
    }

    var direction: TransferDirection
    var protocolType: TransferProtocol
    var fileName: String
    var progress: Double
    var bytesTransferred: Int
    var totalBytes: Int
    var isActive: Bool
}
