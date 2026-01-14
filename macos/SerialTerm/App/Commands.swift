import SwiftUI

/// Serial port menu commands
struct SerialCommands: Commands {
    @ObservedObject var appState: AppState
    @ObservedObject var portManager: SerialPortManager

    var body: some Commands {
        CommandMenu("Serial") {
            // Connection submenu
            if appState.isConnected {
                Button("Disconnect") {
                    appState.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            } else {
                Menu("Connect") {
                    ForEach(portManager.availablePorts) { port in
                        Button(port.displayName) {
                            appState.connect(to: port, config: appState.portConfig)
                        }
                    }

                    if portManager.availablePorts.isEmpty {
                        Text("No ports available")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button("Port Settings...") {
                appState.showConnectionSheet = true
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            // Control signals
            Button("Send Break") {
                appState.sendBreak()
            }
            .keyboardShortcut("b", modifiers: [.command, .control])
            .disabled(!appState.isConnected)

            Toggle("DTR", isOn: Binding(
                get: { appState.dtrState },
                set: { _ in appState.toggleDTR() }
            ))
            .disabled(!appState.isConnected)

            Toggle("RTS", isOn: Binding(
                get: { appState.rtsState },
                set: { _ in appState.toggleRTS() }
            ))
            .disabled(!appState.isConnected)

            Divider()

            // Display options
            Toggle("Local Echo", isOn: $appState.localEcho)
                .keyboardShortcut("e", modifiers: [.command, .control])

            Button("Clear Screen") {
                appState.clearTerminal()
            }
            .keyboardShortcut("k", modifiers: [.command])
        }
    }
}

/// File transfer menu commands
struct TransferCommands: Commands {
    @ObservedObject var appState: AppState

    var body: some Commands {
        CommandMenu("Transfer") {
            Button("Send File...") {
                appState.showTransferSheet = true
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!appState.isConnected)

            Button("Receive File...") {
                appState.showTransferSheet = true
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!appState.isConnected)

            Divider()

            Menu("Send via") {
                Button("XMODEM") {
                    // Start XMODEM send
                }
                Button("YMODEM") {
                    // Start YMODEM send
                }
                Button("ZMODEM") {
                    // Start ZMODEM send
                }
            }
            .disabled(!appState.isConnected)

            Menu("Receive via") {
                Button("XMODEM") {
                    // Start XMODEM receive
                }
                Button("YMODEM") {
                    // Start YMODEM receive
                }
                Button("ZMODEM") {
                    // Start ZMODEM receive (auto-start enabled)
                }
            }
            .disabled(!appState.isConnected)

            Divider()

            if appState.activeTransfer?.isActive == true {
                Button("Cancel Transfer") {
                    appState.activeTransfer?.isActive = false
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }
    }
}
