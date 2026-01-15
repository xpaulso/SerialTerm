import SwiftUI

/// View for managing connection profiles
struct ProfilesView: View {
    @EnvironmentObject var portManager: SerialPortManager
    @ObservedObject var profileManager = ProfileManager.shared
    @State private var selectedProfile: ConnectionProfile?
    @State private var showingNewProfile = false
    @State private var editingProfile: ConnectionProfile?

    var body: some View {
        NavigationSplitView {
            List(profileManager.profiles, selection: $selectedProfile) { profile in
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName)
                        .font(.headline)
                    HStack {
                        Text(profile.configSummary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        if profile.useCount > 0 {
                            Text("\(profile.useCount) uses")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(profile.portPath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .tag(profile)
                .contextMenu {
                    Button("Edit") {
                        editingProfile = profile
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        profileManager.deleteProfile(profile)
                    }
                }
            }
            .navigationTitle("Connection Profiles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewProfile = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
        } detail: {
            if let profile = selectedProfile {
                ProfileDetailView(profile: profile)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a profile")
                        .foregroundColor(.secondary)
                    Text("Or create a new one")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingNewProfile) {
            ProfileEditorSheet(profile: nil, portManager: portManager)
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorSheet(profile: profile, portManager: portManager)
        }
        .frame(minWidth: 500, minHeight: 300)
    }
}

struct ProfileDetailView: View {
    let profile: ConnectionProfile

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Name", value: profile.displayName)
                LabeledContent("Port", value: profile.portPath)
                LabeledContent("Settings", value: profile.configSummary)
            }

            Section("Options") {
                LabeledContent("Auto Log", value: profile.autoLog ? "Yes" : "No")
                if let logDir = profile.logDirectory {
                    LabeledContent("Log Directory", value: logDir)
                }
            }

            if !profile.notes.isEmpty {
                Section("Notes") {
                    Text(profile.notes)
                }
            }

            Section("Usage") {
                LabeledContent("Times Used", value: "\(profile.useCount)")
                if let lastUsed = profile.lastUsed {
                    LabeledContent("Last Used", value: formatDateTime(lastUsed))
                }
                LabeledContent("Created", value: formatDateTime(profile.createdAt))
            }
        }
        .formStyle(.grouped)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ProfileEditorSheet: View {
    let profile: ConnectionProfile?
    let portManager: SerialPortManager
    @ObservedObject var profileManager = ProfileManager.shared

    @State private var name: String = ""
    @State private var portPath: String = ""
    @State private var config = SerialPortConfig()
    @State private var autoLog = false
    @State private var notes = ""

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $name)
                Picker("Port", selection: $portPath) {
                    Text("Select a port").tag("")
                    ForEach(portManager.availablePorts) { port in
                        Text(port.displayName).tag(port.path)
                    }
                }
            }

            Section("Serial Settings") {
                Picker("Baud Rate", selection: $config.baudRate) {
                    ForEach(SerialPortConfig.BaudRate.allCases, id: \.self) { rate in
                        Text(rate.description).tag(rate)
                    }
                }
                Picker("Data Bits", selection: $config.dataBits) {
                    ForEach(SerialPortConfig.DataBits.allCases, id: \.self) { bits in
                        Text(bits.description).tag(bits)
                    }
                }
                Picker("Parity", selection: $config.parity) {
                    ForEach(SerialPortConfig.Parity.allCases, id: \.self) { parity in
                        Text(parity.description).tag(parity)
                    }
                }
                Picker("Stop Bits", selection: $config.stopBits) {
                    ForEach(SerialPortConfig.StopBits.allCases, id: \.self) { bits in
                        Text(bits.description).tag(bits)
                    }
                }
                Picker("Flow Control", selection: $config.flowControl) {
                    ForEach(SerialPortConfig.FlowControl.allCases, id: \.self) { flow in
                        Text(flow.description).tag(flow)
                    }
                }
            }

            Section("Options") {
                Toggle("Auto-start logging", isOn: $autoLog)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(height: 80)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 500)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveProfile()
                    dismiss()
                }
                .disabled(name.isEmpty || portPath.isEmpty)
            }
        }
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

#Preview {
    ProfilesView()
        .environmentObject(SerialPortManager())
}
