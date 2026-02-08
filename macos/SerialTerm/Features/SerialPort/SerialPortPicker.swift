import SwiftUI

struct SerialPortPicker: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var portManager: SerialPortManager
    @Environment(\.dismiss) var dismiss

    @State private var selectedPort: SerialPortInfo?
    @State private var config = SerialPortConfig()
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Port list
            portListView

            Divider()

            // Quick settings
            settingsView

            Divider()

            // Action buttons
            actionButtons
        }
        .frame(width: 420, height: 400)
        .onAppear {
            config = appState.portConfig
            selectedPort = appState.currentPort
        }
    }

    private var headerView: some View {
        HStack {
            Text("Serial Port Connection")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var portListView: some View {
        Group {
            if portManager.availablePorts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No serial ports detected")
                        .foregroundColor(.secondary)
                    Button("Refresh") {
                        portManager.enumeratePorts()
                    }
                    .buttonStyle(.link)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(portManager.availablePorts, selection: $selectedPort) { port in
                    PortRow(port: port, isSelected: selectedPort?.id == port.id)
                        .tag(port)
                }
                .listStyle(.inset)
            }
        }
        .frame(minHeight: 150)
    }

    private var settingsView: some View {
        VStack(spacing: 12) {
            HStack {
                // Baud rate
                VStack(alignment: .leading, spacing: 4) {
                    Text("Baud Rate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $config.baudRate) {
                        ForEach(SerialPortConfig.BaudRate.allCases) { rate in
                            Text(rate.description).tag(rate)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                if showAdvanced {
                    // Data bits
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $config.dataBits) {
                            ForEach(SerialPortConfig.DataBits.allCases) { bits in
                                Text(bits.description).tag(bits)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 60)
                    }

                    // Parity
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $config.parity) {
                            ForEach(SerialPortConfig.Parity.allCases) { parity in
                                Text(parity.description).tag(parity)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 70)
                    }

                    // Stop bits
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stop")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $config.stopBits) {
                            ForEach(SerialPortConfig.StopBits.allCases) { stop in
                                Text(stop.description).tag(stop)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 50)
                    }

                    // Flow control
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flow")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $config.flowControl) {
                            ForEach(SerialPortConfig.FlowControl.allCases) { flow in
                                Text(flow.description).tag(flow)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }

                    // Terminal type
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Terminal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $config.terminalType) {
                            ForEach(SerialPortConfig.TerminalType.allCases) { type in
                                Text(type.description).tag(type)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                }

                Spacer()

                Button(showAdvanced ? "Less" : "More...") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAdvanced.toggle()
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            // Summary
            Text(config.summary)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var actionButtons: some View {
        HStack {
            // Presets menu
            Menu("Presets") {
                Button("Default (115200 8N1)") {
                    config = .default
                }
                Button("Arduino (9600 8N1)") {
                    config = .arduino
                }
                Button("Cisco Console (9600 8N1)") {
                    config = .ciscoConsole
                }
                Button("High Speed (921600 8N1)") {
                    config = .highSpeed
                }
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button("Connect") {
                if let port = selectedPort {
                    appState.connect(to: port, config: config)
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPort == nil)
        }
        .padding()
    }
}

struct PortRow: View {
    let port: SerialPortInfo
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: "cable.connector")
                .foregroundColor(isSelected ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.displayName)
                    .font(.system(.body, design: .default))
                Text(port.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let vendorID = port.vendorID, let productID = port.productID {
                Text(String(format: "%04X:%04X", vendorID, productID))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SerialPortPicker()
        .environmentObject(AppState())
        .environmentObject(SerialPortManager())
}
