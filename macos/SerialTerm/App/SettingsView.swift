import SwiftUI

struct SettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var profileManager = ProfileManager.shared
    @ObservedObject var portManager = SerialPortManager.shared

    @AppStorage("defaultBaudRate") private var defaultBaudRate = 115200
    @AppStorage("defaultDataBits") private var defaultDataBits = 8
    @AppStorage("escapeCharacter") private var escapeCharacter = 1 // Ctrl+A
    @AppStorage("autoZModem") private var autoZModem = true
    @AppStorage("scrollbackLines") private var scrollbackLines = 10000

    // Serial port selection state
    @State private var selectedPortPath: String = ""
    @State private var portConfig = SerialPortConfig()
    @State private var showAdvancedSerial = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            appearanceTab
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }

            serialDefaultsTab
                .tabItem {
                    Label("Serial", systemImage: "cable.connector")
                }

            transferTab
                .tabItem {
                    Label("Transfer", systemImage: "arrow.left.arrow.right")
                }

            loggingTab
                .tabItem {
                    Label("Logging", systemImage: "doc.text")
                }
        }
        .frame(width: 540, height: 420)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Startup") {
                Toggle("Remember last connection", isOn: .constant(true))
                Toggle("Auto-reconnect on disconnect", isOn: .constant(false))
            }

            Section("Keyboard") {
                Picker("Escape Character", selection: $escapeCharacter) {
                    Text("Ctrl+A").tag(1)
                    Text("Ctrl+B").tag(2)
                    Text("Ctrl+\\").tag(28)
                }
                Text("Press twice to send the literal character")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Scrollback") {
                Picker("Buffer Size", selection: $scrollbackLines) {
                    Text("1,000 lines").tag(1000)
                    Text("5,000 lines").tag(5000)
                    Text("10,000 lines").tag(10000)
                    Text("50,000 lines").tag(50000)
                    Text("100,000 lines").tag(100000)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        Form {
            Section("Theme") {
                Picker("Theme", selection: Binding(
                    get: { currentThemeName() },
                    set: { appearanceManager.applyTheme($0) }
                )) {
                    ForEach(Array(AppearanceSettings.themes.keys.sorted()), id: \.self) { name in
                        Text(name).tag(name)
                    }
                    Text("Custom").tag("Custom")
                }
            }

            Section("Font") {
                Picker("Font Family", selection: $appearanceManager.settings.fontName) {
                    ForEach(AppearanceSettings.availableFonts, id: \.self) { fontName in
                        Text(fontName)
                            .font(.custom(fontName, size: 12))
                            .tag(fontName)
                    }
                }

                HStack {
                    Text("Font Size")
                    Spacer()
                    Stepper("\(Int(appearanceManager.settings.fontSize)) pt",
                            value: $appearanceManager.settings.fontSize, in: 9...24)
                }

                // Preview
                Text("ABCDEFGHIJKLM 0123456789")
                    .font(.custom(appearanceManager.settings.fontName, size: appearanceManager.settings.fontSize))
                    .foregroundColor(appearanceManager.settings.foregroundColor.color)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(appearanceManager.settings.backgroundColor.color)
                    .cornerRadius(4)
            }

            Section("Colors") {
                ColorPicker("Foreground",
                           selection: Binding(
                               get: { appearanceManager.settings.foregroundColor.color },
                               set: { appearanceManager.settings.foregroundColor = CodableColor(NSColor($0)) }
                           ))

                ColorPicker("Background",
                           selection: Binding(
                               get: { appearanceManager.settings.backgroundColor.color },
                               set: { appearanceManager.settings.backgroundColor = CodableColor(NSColor($0)) }
                           ))

                ColorPicker("Cursor",
                           selection: Binding(
                               get: { appearanceManager.settings.cursorColor.color },
                               set: { appearanceManager.settings.cursorColor = CodableColor(NSColor($0)) }
                           ))

                ColorPicker("Selection",
                           selection: Binding(
                               get: { appearanceManager.settings.selectionColor.color },
                               set: { appearanceManager.settings.selectionColor = CodableColor(NSColor($0)) }
                           ))
            }

            Section("ANSI Colors") {
                HStack(spacing: 4) {
                    ansiColorButton(color: $appearanceManager.settings.ansiBlack, name: "Black")
                    ansiColorButton(color: $appearanceManager.settings.ansiRed, name: "Red")
                    ansiColorButton(color: $appearanceManager.settings.ansiGreen, name: "Green")
                    ansiColorButton(color: $appearanceManager.settings.ansiYellow, name: "Yellow")
                    ansiColorButton(color: $appearanceManager.settings.ansiBlue, name: "Blue")
                    ansiColorButton(color: $appearanceManager.settings.ansiMagenta, name: "Magenta")
                    ansiColorButton(color: $appearanceManager.settings.ansiCyan, name: "Cyan")
                    ansiColorButton(color: $appearanceManager.settings.ansiWhite, name: "White")
                }
            }

            HStack {
                Spacer()
                Button("Reset to Default") {
                    appearanceManager.reset()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func ansiColorButton(color: Binding<CodableColor>, name: String) -> some View {
        ColorPicker("", selection: Binding(
            get: { color.wrappedValue.color },
            set: { color.wrappedValue = CodableColor(NSColor($0)) }
        ))
        .labelsHidden()
        .frame(width: 40, height: 24)
        .help(name)
    }

    private func currentThemeName() -> String {
        for (name, theme) in AppearanceSettings.themes {
            if theme == appearanceManager.settings {
                return name
            }
        }
        return "Custom"
    }

    // MARK: - Serial Defaults Tab

    private var serialDefaultsTab: some View {
        Form {
            Section("Default Configuration") {
                Picker("Baud Rate", selection: $portConfig.baudRate) {
                    ForEach(SerialPortConfig.BaudRate.allCases) { rate in
                        Text(rate.description).tag(rate)
                    }
                }

                Picker("Data Bits", selection: $portConfig.dataBits) {
                    ForEach(SerialPortConfig.DataBits.allCases) { bits in
                        Text(bits.description).tag(bits)
                    }
                }

                Picker("Parity", selection: $portConfig.parity) {
                    ForEach(SerialPortConfig.Parity.allCases) { parity in
                        Text(parity.description).tag(parity)
                    }
                }

                Picker("Stop Bits", selection: $portConfig.stopBits) {
                    ForEach(SerialPortConfig.StopBits.allCases) { stop in
                        Text(stop.description).tag(stop)
                    }
                }

                Picker("Flow Control", selection: $portConfig.flowControl) {
                    ForEach(SerialPortConfig.FlowControl.allCases) { flow in
                        Text(flow.description).tag(flow)
                    }
                }

                Picker("Line Ending", selection: $portConfig.lineEnding) {
                    ForEach(SerialPortConfig.LineEnding.allCases) { ending in
                        Text(ending.description).tag(ending)
                    }
                }

                Picker("Terminal Type", selection: $portConfig.terminalType) {
                    ForEach(SerialPortConfig.TerminalType.allCases) { type in
                        Text(type.description).tag(type)
                    }
                }
            }

            Section("Presets") {
                HStack {
                    Button("Default") { portConfig = .default }
                    Button("Arduino") { portConfig = .arduino }
                    Button("Cisco") { portConfig = .ciscoConsole }
                    Button("High Speed") { portConfig = .highSpeed }
                }
                .buttonStyle(.bordered)
            }

            Section("Line Signals") {
                Toggle("Assert DTR on connect", isOn: .constant(true))
                Toggle("Assert RTS on connect", isOn: .constant(true))
            }

            Section {
                Text("Current: \(portConfig.summary)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Transfer Tab

    private var transferTab: some View {
        Form {
            Section("ZMODEM") {
                Toggle("Auto-start ZMODEM receive", isOn: $autoZModem)
                Text("Automatically detect and start ZMODEM transfers")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Defaults") {
                Picker("Default Protocol", selection: .constant("ZMODEM")) {
                    Text("XMODEM").tag("XMODEM")
                    Text("YMODEM").tag("YMODEM")
                    Text("ZMODEM").tag("ZMODEM")
                }
            }

            Section("File Handling") {
                Toggle("Overwrite existing files", isOn: .constant(false))
                Toggle("Preserve file timestamps", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Logging Tab

    private var loggingTab: some View {
        Form {
            Section("Default Logging") {
                Toggle("Auto-start logging on connect", isOn: .constant(false))
                Toggle("Include timestamps", isOn: .constant(false))
            }

            Section("Log Directory") {
                HStack {
                    Text(defaultLogDirectory())
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Change...") {
                        selectLogDirectory()
                    }

                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: defaultLogDirectory())
                    }
                }
            }

            Section("Naming") {
                Text("Default log name format: {session_name}_{timestamp}.log")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func defaultLogDirectory() -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("SerialTerm Logs").path
    }

    private func selectLogDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"

        if panel.runModal() == .OK {
            // Save the selected directory
        }
    }
}

#Preview {
    SettingsView()
}
