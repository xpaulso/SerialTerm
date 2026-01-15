import SwiftUI
import AppKit

/// View for browsing and managing session logs
struct LogsView: View {
    @StateObject private var sessionLogger = SessionLogger()
    @State private var logFiles: [LogFileInfo] = []
    @State private var selectedLog: LogFileInfo?
    @State private var logContent: String = ""
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(filteredLogFiles, selection: $selectedLog) { logFile in
                VStack(alignment: .leading, spacing: 4) {
                    Text(logFile.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack {
                        Text(logFile.sizeString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(logFile.dateString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .tag(logFile)
                .contextMenu {
                    Button("Open") {
                        sessionLogger.openLogFile(logFile)
                    }
                    Button("Reveal in Finder") {
                        sessionLogger.revealLogFile(logFile)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        deleteLog(logFile)
                    }
                }
            }
            .navigationTitle("Session Logs")
            .searchable(text: $searchText, prompt: "Search logs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openLogDirectory) {
                        Image(systemName: "folder")
                    }
                    .help("Open logs folder")
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(action: { deleteAllLogs() }) {
                        Image(systemName: "trash")
                    }
                    .help("Delete all logs")
                    .disabled(logFiles.isEmpty)
                }
            }
        } detail: {
            if let log = selectedLog {
                LogContentView(logFile: log, content: logContent)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a log file")
                        .foregroundColor(.secondary)
                    Text("\(logFiles.count) log files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            refreshLogs()
        }
        .onChange(of: selectedLog) { _, newValue in
            if let log = newValue {
                loadLogContent(log)
            }
        }
    }

    private var filteredLogFiles: [LogFileInfo] {
        if searchText.isEmpty {
            return logFiles
        }
        return logFiles.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func refreshLogs() {
        logFiles = sessionLogger.getLogFiles()
    }

    private func loadLogContent(_ logFile: LogFileInfo) {
        do {
            logContent = try String(contentsOf: logFile.url, encoding: .utf8)
        } catch {
            logContent = "Error loading file: \(error.localizedDescription)"
        }
    }

    private func deleteLog(_ logFile: LogFileInfo) {
        try? sessionLogger.deleteLogFile(logFile)
        refreshLogs()
        if selectedLog?.id == logFile.id {
            selectedLog = nil
            logContent = ""
        }
    }

    private func deleteAllLogs() {
        for log in logFiles {
            try? sessionLogger.deleteLogFile(log)
        }
        refreshLogs()
        selectedLog = nil
        logContent = ""
    }

    private func openLogDirectory() {
        NSWorkspace.shared.open(sessionLogger.logDirectory)
    }
}

struct LogContentView: View {
    let logFile: LogFileInfo
    let content: String
    @State private var fontSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(logFile.name)
                    .font(.headline)
                Spacer()
                Text(logFile.sizeString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(logFile.dateString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Content
            ScrollView([.horizontal, .vertical]) {
                Text(content)
                    .font(.system(size: fontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { fontSize = max(8, fontSize - 1) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                Button(action: { fontSize = min(24, fontSize + 1) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
            }
        }
    }
}

#Preview {
    LogsView()
}
