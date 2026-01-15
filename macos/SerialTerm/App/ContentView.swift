import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var portManager: SerialPortManager
    @StateObject private var commandHandler = CommandModeHandler()
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        ZStack {
            // Terminal view with appearance settings
            TerminalView(
                output: $appState.terminalOutput,
                onInput: handleInput
            )
            .opacity(appState.isConnected ? 1.0 : 0.3)

            // Status indicators overlay
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        // Command mode indicator
                        if commandHandler.isInCommandMode {
                            CommandModeIndicator()
                        }

                        // Logging indicator
                        if appState.isLogging {
                            LoggingIndicator()
                        }
                    }
                }
                Spacer()
            }

            // Connection overlay when disconnected
            if !appState.isConnected {
                ConnectionOverlay()
            }

            // Transfer progress overlay
            if let transfer = appState.activeTransfer, transfer.isActive {
                TransferProgressOverlay(transfer: transfer)
            }
        }
        .sheet(isPresented: $appState.showConnectionSheet) {
            SerialPortPicker()
        }
        .sheet(isPresented: $appState.showTransferSheet) {
            TransferSheet()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                ConnectionToolbar()
            }
        }
        .onKeyPress { key in
            handleKeyPress(key)
        }
    }

    private func handleInput(_ data: Data) {
        guard appState.isConnected else { return }

        for byte in data {
            let (consumed, command) = commandHandler.processKey(byte)

            if let command = command {
                executeCommand(command)
            } else if !consumed {
                appState.send(Data([byte]))
            }
        }
    }

    private func handleKeyPress(_ key: KeyPress) -> KeyPress.Result {
        guard appState.isConnected else { return .ignored }

        if let asciiValue = key.characters.first?.asciiValue {
            let (consumed, command) = commandHandler.processKey(asciiValue)

            if let command = command {
                executeCommand(command)
                return .handled
            } else if consumed {
                return .handled
            }
        }

        return .ignored
    }

    private func executeCommand(_ command: CommandModeHandler.Command) {
        switch command {
        case .quit:
            appState.disconnect()
        case .sendBreak:
            appState.sendBreak()
        case .toggleDTR:
            appState.toggleDTR()
        case .toggleRTS:
            appState.toggleRTS()
        case .uploadXMODEM:
            startTransfer(protocol: .xmodem, direction: .send)
        case .uploadYMODEM:
            startTransfer(protocol: .ymodem, direction: .send)
        case .uploadZMODEM:
            startTransfer(protocol: .zmodem, direction: .send)
        case .downloadReceive:
            startTransfer(protocol: .zmodem, direction: .receive)
        case .showHelp:
            showHelp()
        case .sendEscape:
            appState.send(Data([commandHandler.escapeCharacter]))
        case .toggleLocalEcho:
            appState.localEcho.toggle()
        case .clearScreen:
            appState.clearTerminal()
        case .showPortSettings:
            appState.showConnectionSheet = true
        }
    }

    private func startTransfer(protocol: TransferState.TransferProtocol, direction: TransferState.TransferDirection) {
        appState.activeTransfer = TransferState(
            direction: direction,
            protocolType: `protocol`,
            fileName: "",
            progress: 0,
            bytesTransferred: 0,
            totalBytes: 0,
            isActive: true
        )
        appState.showTransferSheet = true
    }

    private func showHelp() {
        // Display help in terminal
        let helpText = """
        \r\n--- SerialTerm Command Mode (Ctrl+A) ---\r\n
        Ctrl+A, Q   - Quit/Disconnect\r\n
        Ctrl+A, B   - Send Break\r\n
        Ctrl+A, D   - Toggle DTR\r\n
        Ctrl+A, R   - Toggle RTS\r\n
        Ctrl+A, X   - Upload XMODEM\r\n
        Ctrl+A, Y   - Upload YMODEM\r\n
        Ctrl+A, Z   - Upload ZMODEM\r\n
        Ctrl+A, E   - Toggle Local Echo\r\n
        Ctrl+A, C   - Clear Screen\r\n
        Ctrl+A, S   - Port Settings\r\n
        Ctrl+A, H/? - Show Help\r\n
        Ctrl+A, Ctrl+A - Send Ctrl+A\r\n
        ----------------------------------------\r\n
        """
        appState.terminalOutput.append(contentsOf: helpText.utf8)
    }
}

// MARK: - Connection Overlay

struct ConnectionOverlay: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var portManager: SerialPortManager
    @ObservedObject var profileManager = ProfileManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "cable.connector")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Connection")
                .font(.headline)

            Text("Select a serial port to connect")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Recent profiles
            if !profileManager.recentProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent Profiles")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(profileManager.recentProfiles.prefix(3)) { profile in
                        Button(action: { appState.connect(to: profile) }) {
                            HStack {
                                Text(profile.displayName)
                                Spacer()
                                Text(profile.configSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }

            if portManager.availablePorts.isEmpty {
                Text("No serial ports detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Menu {
                    ForEach(portManager.availablePorts) { port in
                        Button(port.displayName) {
                            appState.connect(to: port, config: appState.portConfig)
                        }
                    }
                } label: {
                    Label("Connect", systemImage: "cable.connector")
                }
                .menuStyle(.borderedButton)
            }

            Button("Settings...") {
                appState.showConnectionSheet = true
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Command Mode Indicator

struct CommandModeIndicator: View {
    var body: some View {
        Text("CMD")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.orange.opacity(0.8))
            .cornerRadius(4)
            .padding(8)
    }
}

// MARK: - Logging Indicator

struct LoggingIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
            Text("REC")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.red.opacity(0.2))
        .cornerRadius(4)
        .padding(8)
        .onTapGesture {
            appState.stopLogging()
        }
        .help("Click to stop logging - \(appState.sessionLogger.bytesLogged) bytes logged")
    }
}

// MARK: - Transfer Progress Overlay

struct TransferProgressOverlay: View {
    let transfer: TransferState

    var body: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Image(systemName: transfer.direction == .send ? "arrow.up.doc" : "arrow.down.doc")
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(transfer.fileName.isEmpty ? "Transfer in progress..." : transfer.fileName)
                        .font(.system(.body, design: .monospaced))

                    ProgressView(value: transfer.progress)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(transfer.protocolType.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(formatBytes(transfer.bytesTransferred)) / \(formatBytes(transfer.totalBytes))")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                Button(action: {}) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(8)
            .padding()
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Connection Toolbar

struct ConnectionToolbar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            // Connection status
            Circle()
                .fill(appState.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            if appState.isConnected {
                // Port name
                Text(appState.currentPort?.name ?? "Connected")
                    .font(.system(.caption, design: .monospaced))

                // Serial config summary (e.g., "115200 8N1")
                Text(appState.portConfig.shortSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                // Terminal type
                Text("VT220")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(3)

                // Logging button
                Button(action: toggleLogging) {
                    Image(systemName: appState.isLogging ? "record.circle.fill" : "record.circle")
                        .foregroundColor(appState.isLogging ? .red : .secondary)
                }
                .help(appState.isLogging ? "Stop logging" : "Start logging")

                Button(action: { appState.disconnect() }) {
                    Image(systemName: "xmark.circle")
                }
                .help("Disconnect")
            } else {
                Text("Disconnected")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)

                Button(action: { appState.showConnectionSheet = true }) {
                    Image(systemName: "cable.connector")
                }
                .help("Connect...")
            }
        }
    }

    private func toggleLogging() {
        if appState.isLogging {
            appState.stopLogging()
        } else {
            appState.startLogging()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(SerialPortManager())
}
