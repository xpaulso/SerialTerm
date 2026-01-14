import SwiftUI

@main
struct SerialTermApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var portManager = SerialPortManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(portManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SerialCommands(appState: appState, portManager: portManager)
            TransferCommands(appState: appState)
            SessionCommands(appState: appState)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("Session History", id: "session-history") {
            SessionHistoryView()
                .environmentObject(appState)
        }

        Window("Connection Profiles", id: "profiles") {
            ProfilesView()
                .environmentObject(appState)
                .environmentObject(portManager)
        }

        Window("Session Logs", id: "logs") {
            LogsView()
        }
    }
}

/// Main application state
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
            statusMessage = "Connected to \(port.displayName)"

            // Set initial modem line states
            serialConnection?.setDTR(dtrState)
            serialConnection?.setRTS(rtsState)

            // Start session tracking
            historyManager.startSession(
                portPath: port.path,
                portName: port.name,
                config: config
            )

            // Update profile usage if applicable
            if let profile = profileManager.findProfile(forPort: port.path) {
                profileManager.markAsUsed(profile)
            }
        } catch {
            statusMessage = "Failed to connect: \(error.localizedDescription)"
        }
    }

    func connect(to profile: ConnectionProfile) {
        guard let portInfo = SerialPortManager().availablePorts.first(where: { $0.path == profile.portPath }) else {
            statusMessage = "Port \(profile.portPath) not available"
            return
        }
        connect(to: portInfo, config: profile.config)
        profileManager.markAsUsed(profile)

        // Auto-start logging if profile has autoLog enabled
        if profile.autoLog {
            startLogging(sessionName: profile.name)
        }
    }

    func disconnect() {
        // Stop logging if active
        if isLogging {
            stopLogging()
        }

        // End session tracking
        historyManager.endSession()

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
        sessionLogger.logMessage("DTR \(dtrState ? "asserted" : "deasserted")")
    }

    func toggleRTS() {
        rtsState.toggle()
        serialConnection?.setRTS(rtsState)
        sessionLogger.logMessage("RTS \(rtsState ? "asserted" : "deasserted")")
    }

    func clearTerminal() {
        terminalOutput.removeAll()
    }

    // MARK: - Logging

    func startLogging(sessionName: String? = nil, customName: String? = nil) {
        let name = sessionName ?? currentPort?.displayName
        do {
            try sessionLogger.startLogging(sessionName: name, customName: customName)
            isLogging = true
            statusMessage = "Logging to \(sessionLogger.currentLogPath ?? "file")"

            // Update session history with log path
            if let path = sessionLogger.currentLogPath {
                historyManager.setLogFile(path)
            }
        } catch {
            statusMessage = "Failed to start logging: \(error.localizedDescription)"
        }
    }

    func stopLogging() {
        sessionLogger.stopLogging()
        isLogging = false
    }

    // MARK: - Profile Management

    func saveCurrentAsProfile(name: String, notes: String = "") {
        guard let port = currentPort else { return }
        _ = profileManager.createProfile(
            name: name,
            portPath: port.path,
            config: portConfig,
            autoLog: false,
            notes: notes
        )
    }
}

extension AppState: SerialConnectionDelegate {
    nonisolated func serialConnection(_ connection: SerialConnection, didReceive data: Data) {
        Task { @MainActor in
            self.terminalOutput.append(contentsOf: data)

            // Log received data
            if self.isLogging {
                self.sessionLogger.logReceived(data)
            }

            // Update stats
            self.historyManager.updateStats(bytesReceived: data.count)

            // Check for ZMODEM auto-start
            if data.count > 4 {
                let bytes = [UInt8](data)
                if TransferManager.detectZModemAutoStart(bytes) {
                    // Auto-start ZMODEM receive
                    self.statusMessage = "ZMODEM transfer detected"
                }
            }
        }
    }

    nonisolated func serialConnection(_ connection: SerialConnection, didEncounterError error: Error) {
        Task { @MainActor in
            self.statusMessage = "Error: \(error.localizedDescription)"
            self.sessionLogger.logMessage("Error: \(error.localizedDescription)")
        }
    }

    nonisolated func serialConnectionDidDisconnect(_ connection: SerialConnection) {
        Task { @MainActor in
            self.isConnected = false
            self.statusMessage = "Disconnected"
            self.historyManager.endSession()
            if self.isLogging {
                self.stopLogging()
            }
        }
    }
}

/// Transfer state for UI
struct TransferState: Identifiable {
    let id = UUID()
    var direction: TransferDirection
    var protocolType: TransferProtocol
    var fileName: String
    var progress: Double
    var bytesTransferred: Int
    var totalBytes: Int
    var isActive: Bool

    enum TransferDirection {
        case send, receive
    }

    enum TransferProtocol: String, CaseIterable {
        case xmodem = "XMODEM"
        case ymodem = "YMODEM"
        case zmodem = "ZMODEM"
    }
}

// MARK: - Session Commands

struct SessionCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Session") {
            Button("Start Logging...") {
                appState.startLogging()
            }
            .keyboardShortcut("L", modifiers: [.command, .shift])
            .disabled(!appState.isConnected || appState.isLogging)

            Button("Stop Logging") {
                appState.stopLogging()
            }
            .disabled(!appState.isLogging)

            Divider()

            Button("Save as Profile...") {
                // Show save profile dialog
            }
            .keyboardShortcut("S", modifiers: [.command, .shift])
            .disabled(!appState.isConnected)

            Divider()

            Button("Session History") {
                // Open session history window
            }
            .keyboardShortcut("H", modifiers: [.command, .option])

            Button("Connection Profiles") {
                // Open profiles window
            }
            .keyboardShortcut("P", modifiers: [.command, .option])

            Button("View Logs") {
                // Open logs window
            }
        }
    }
}

// MARK: - Session History View

struct SessionHistoryView: View {
    @ObservedObject var historyManager = SessionHistoryManager.shared
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Session History")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    historyManager.clearHistory()
                }
                .disabled(historyManager.history.isEmpty)
            }
            .padding()

            Divider()

            // List
            if historyManager.history.isEmpty {
                VStack {
                    Spacer()
                    Text("No session history")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(historyManager.history) { entry in
                    SessionHistoryRow(entry: entry)
                        .contextMenu {
                            Button("Connect") {
                                reconnect(entry)
                            }
                            if let logPath = entry.logFilePath {
                                Button("Open Log") {
                                    NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
                                }
                            }
                            Divider()
                            Button("Remove") {
                                historyManager.removeEntry(entry)
                            }
                        }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func reconnect(_ entry: SessionHistoryEntry) {
        let portInfo = SerialPortInfo(
            id: entry.portPath,
            path: entry.portPath,
            name: entry.portName,
            vendorID: nil,
            productID: nil
        )
        appState.connect(to: portInfo, config: entry.config)
    }
}

struct SessionHistoryRow: View {
    let entry: SessionHistoryEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.headline)
                Text(entry.config.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.startTime, style: .date)
                    .font(.caption)
                Text(entry.durationString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if entry.logFilePath != nil {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Profiles View

struct ProfilesView: View {
    @ObservedObject var profileManager = ProfileManager.shared
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var portManager: SerialPortManager
    @State private var showingAddSheet = false
    @State private var editingProfile: ConnectionProfile?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connection Profiles")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding()

            Divider()

            // List
            if profileManager.profiles.isEmpty {
                VStack {
                    Spacer()
                    Text("No saved profiles")
                        .foregroundColor(.secondary)
                    Text("Save a profile from an active connection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(profileManager.profiles) { profile in
                    ProfileRow(profile: profile)
                        .contextMenu {
                            Button("Connect") {
                                appState.connect(to: profile)
                            }
                            Button("Edit...") {
                                editingProfile = profile
                            }
                            Divider()
                            Button("Delete") {
                                profileManager.deleteProfile(profile)
                            }
                        }
                        .onTapGesture(count: 2) {
                            appState.connect(to: profile)
                        }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .sheet(isPresented: $showingAddSheet) {
            ProfileEditSheet(profile: nil)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditSheet(profile: profile)
        }
    }
}

struct ProfileRow: View {
    let profile: ConnectionProfile

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName)
                    .font(.headline)
                Text(profile.configSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !profile.notes.isEmpty {
                    Text(profile.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let lastUsed = profile.lastUsed {
                    Text(lastUsed, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if profile.useCount > 0 {
                    Text("\(profile.useCount) uses")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if profile.autoLog {
                Image(systemName: "doc.text")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ProfileEditSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var profileManager = ProfileManager.shared

    let profile: ConnectionProfile?
    @State private var name: String = ""
    @State private var portPath: String = ""
    @State private var config = SerialPortConfig()
    @State private var autoLog = false
    @State private var notes: String = ""

    var body: some View {
        VStack(spacing: 0) {
            Text(profile == nil ? "New Profile" : "Edit Profile")
                .font(.headline)
                .padding()

            Form {
                TextField("Name", text: $name)
                TextField("Port Path", text: $portPath)
                    .font(.system(.body, design: .monospaced))

                Picker("Baud Rate", selection: $config.baudRate) {
                    ForEach([9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600], id: \.self) { rate in
                        Text("\(rate)").tag(rate)
                    }
                }

                Toggle("Auto-start logging", isOn: $autoLog)

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3)
            }
            .formStyle(.grouped)
            .padding()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveProfile()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || portPath.isEmpty)
            }
            .padding()
        }
        .frame(width: 400)
        .onAppear {
            if let profile = profile {
                name = profile.name
                portPath = profile.portPath
                config = profile.config
                autoLog = profile.autoLog
                notes = profile.notes
            }
        }
    }

    private func saveProfile() {
        if let existing = profile {
            var updated = existing
            updated.name = name
            updated.portPath = portPath
            updated.config = config
            updated.autoLog = autoLog
            updated.notes = notes
            profileManager.updateProfile(updated)
        } else {
            _ = profileManager.createProfile(
                name: name,
                portPath: portPath,
                config: config,
                autoLog: autoLog,
                notes: notes
            )
        }
    }
}

// MARK: - Logs View

struct LogsView: View {
    @StateObject private var logger = SessionLogger()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Session Logs")
                    .font(.headline)
                Spacer()
                Button("Open Folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logger.logDirectory.path)
                }
            }
            .padding()

            Divider()

            // List
            let logs = logger.getLogFiles()
            if logs.isEmpty {
                VStack {
                    Spacer()
                    Text("No log files")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(logs) { log in
                    LogFileRow(log: log)
                        .contextMenu {
                            Button("Open") {
                                logger.openLogFile(log)
                            }
                            Button("Reveal in Finder") {
                                logger.revealLogFile(log)
                            }
                            Divider()
                            Button("Delete") {
                                try? logger.deleteLogFile(log)
                            }
                        }
                        .onTapGesture(count: 2) {
                            logger.openLogFile(log)
                        }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct LogFileRow: View {
    let log: LogFileInfo

    var body: some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(log.name)
                    .font(.headline)
                Text(log.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(log.sizeString)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}
