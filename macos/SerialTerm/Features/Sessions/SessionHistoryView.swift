import SwiftUI

/// View for displaying session history
struct SessionHistoryView: View {
    @ObservedObject var historyManager = SessionHistoryManager.shared
    @State private var selectedEntry: SessionHistoryEntry?

    var body: some View {
        NavigationSplitView {
            List(historyManager.history, selection: $selectedEntry) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.displayName)
                        .font(.headline)
                    HStack {
                        Text(entry.config.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(entry.durationString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(formatDate(entry.startTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .tag(entry)
            }
            .navigationTitle("Session History")
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") {
                        historyManager.clearHistory()
                    }
                    .disabled(historyManager.history.isEmpty)
                }
            }
        } detail: {
            if let entry = selectedEntry {
                SessionDetailView(entry: entry)
            } else {
                Text("Select a session")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct SessionDetailView: View {
    let entry: SessionHistoryEntry

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Port", value: entry.displayName)
                LabeledContent("Path", value: entry.portPath)
                LabeledContent("Settings", value: entry.config.summary)
            }

            Section("Statistics") {
                LabeledContent("Duration", value: entry.durationString)
                LabeledContent("Bytes Received", value: formatBytes(entry.bytesReceived))
                LabeledContent("Bytes Sent", value: formatBytes(entry.bytesSent))
            }

            Section("Time") {
                LabeledContent("Started", value: formatDateTime(entry.startTime))
                if let endTime = entry.endTime {
                    LabeledContent("Ended", value: formatDateTime(endTime))
                }
            }

            if let logPath = entry.logFilePath {
                Section("Log File") {
                    Text(logPath)
                        .font(.system(.body, design: .monospaced))
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(logPath, inFileViewerRootedAtPath: "")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    SessionHistoryView()
}
