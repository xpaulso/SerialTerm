import Foundation

/// Represents a past session
struct SessionHistoryEntry: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let portPath: String
    let portName: String
    let config: SerialPortConfig
    let startTime: Date
    var endTime: Date?
    var bytesReceived: Int
    var bytesSent: Int
    var logFilePath: String?

    init(
        id: UUID = UUID(),
        portPath: String,
        portName: String,
        config: SerialPortConfig,
        startTime: Date = Date(),
        endTime: Date? = nil,
        bytesReceived: Int = 0,
        bytesSent: Int = 0,
        logFilePath: String? = nil
    ) {
        self.id = id
        self.portPath = portPath
        self.portName = portName
        self.config = config
        self.startTime = startTime
        self.endTime = endTime
        self.bytesReceived = bytesReceived
        self.bytesSent = bytesSent
        self.logFilePath = logFilePath
    }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }

    var durationString: String {
        guard let duration = duration else { return "Active" }
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var displayName: String {
        if portName.isEmpty {
            return portPath.replacingOccurrences(of: "/dev/cu.", with: "")
        }
        return portName
    }
}

/// Manages session history persistence
@MainActor
class SessionHistoryManager: ObservableObject {
    static let shared = SessionHistoryManager()

    @Published private(set) var history: [SessionHistoryEntry] = []
    @Published var currentSession: SessionHistoryEntry?

    private let defaultsKey = "SessionHistory"
    private let maxHistoryEntries = 100

    private init() {
        loadHistory()
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let entries = try? JSONDecoder().decode([SessionHistoryEntry].self, from: data) {
            self.history = entries
        }
    }

    private func saveHistory() {
        // Keep only the most recent entries
        let trimmedHistory = Array(history.prefix(maxHistoryEntries))
        if let data = try? JSONEncoder().encode(trimmedHistory) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Start a new session
    func startSession(portPath: String, portName: String, config: SerialPortConfig) {
        let entry = SessionHistoryEntry(
            portPath: portPath,
            portName: portName,
            config: config
        )
        currentSession = entry
    }

    /// End the current session
    func endSession() {
        guard var session = currentSession else { return }
        session.endTime = Date()
        history.insert(session, at: 0)
        currentSession = nil
        saveHistory()
    }

    /// Update current session stats
    func updateStats(bytesReceived: Int? = nil, bytesSent: Int? = nil) {
        if let received = bytesReceived {
            currentSession?.bytesReceived += received
        }
        if let sent = bytesSent {
            currentSession?.bytesSent += sent
        }
    }

    /// Set log file for current session
    func setLogFile(_ path: String) {
        currentSession?.logFilePath = path
    }

    /// Clear all history
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    /// Remove a specific entry
    func removeEntry(_ entry: SessionHistoryEntry) {
        history.removeAll { $0.id == entry.id }
        saveHistory()
    }

    /// Get recent unique ports (for quick connect)
    func recentPorts(limit: Int = 5) -> [SessionHistoryEntry] {
        var seen = Set<String>()
        var result: [SessionHistoryEntry] = []

        for entry in history {
            if !seen.contains(entry.portPath) {
                seen.insert(entry.portPath)
                result.append(entry)
                if result.count >= limit {
                    break
                }
            }
        }

        return result
    }
}
