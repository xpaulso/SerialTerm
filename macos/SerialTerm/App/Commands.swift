import SwiftUI

/// Serial port menu commands
struct SerialCommands: Commands {
    @FocusedValue(\.appState) var appState
    @ObservedObject var portManager: SerialPortManager

    var body: some Commands {
        CommandMenu("Serial") {
            // Connection submenu
            if let appState = appState, appState.isConnected {
                Button("Disconnect") {
                    appState.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            } else {
                Menu("Connect") {
                    ForEach(portManager.availablePorts) { port in
                        Button(port.displayName) {
                            appState?.connect(to: port, config: appState?.portConfig ?? SerialPortConfig())
                        }
                    }

                    if portManager.availablePorts.isEmpty {
                        Text("No ports available")
                            .foregroundColor(.secondary)
                    }
                }
            }

            Button("Port Settings...") {
                appState?.showConnectionSheet = true
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            // Control signals
            Button("Send Break") {
                appState?.sendBreak()
            }
            .keyboardShortcut("b", modifiers: [.command, .control])
            .disabled(appState?.isConnected != true)

            Toggle("DTR", isOn: Binding(
                get: { appState?.dtrState ?? false },
                set: { _ in appState?.toggleDTR() }
            ))
            .disabled(appState?.isConnected != true)

            Toggle("RTS", isOn: Binding(
                get: { appState?.rtsState ?? false },
                set: { _ in appState?.toggleRTS() }
            ))
            .disabled(appState?.isConnected != true)

            Divider()

            // Display options
            Toggle("Local Echo", isOn: Binding(
                get: { appState?.localEcho ?? false },
                set: { appState?.localEcho = $0 }
            ))
            .keyboardShortcut("e", modifiers: [.command, .control])
        }
    }
}

/// File transfer menu commands
struct TransferCommands: Commands {
    @FocusedValue(\.appState) var appState

    var body: some Commands {
        CommandMenu("Transfer") {
            Button("Send File...") {
                appState?.showTransferSheet = true
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(appState?.isConnected != true)

            Button("Receive File...") {
                appState?.showTransferSheet = true
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(appState?.isConnected != true)

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
            .disabled(appState?.isConnected != true)

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
            .disabled(appState?.isConnected != true)

            Divider()

            if appState?.activeTransfer?.isActive == true {
                Button("Cancel Transfer") {
                    appState?.activeTransfer?.isActive = false
                }
                .keyboardShortcut(".", modifiers: [.command])
            }
        }
    }
}

/// Session management commands
struct SessionCommands: Commands {
    @FocusedValue(\.appState) var appState
    @Environment(\.openWindow) var openWindow

    var body: some Commands {
        CommandMenu("Session") {
            Button("Start Logging") {
                appState?.startLogging()
            }
            .disabled(appState?.isLogging == true || appState?.isConnected != true)

            Button("Stop Logging") {
                appState?.stopLogging()
            }
            .disabled(appState?.isLogging != true)

            Divider()

            Button("View Logs...") {
                openWindow(id: "logs")
            }

            Button("Session History...") {
                openWindow(id: "session-history")
            }

            Divider()

            Button("Connection Profiles...") {
                openWindow(id: "profiles")
            }
        }
    }
}
