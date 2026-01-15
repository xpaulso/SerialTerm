import Foundation
import AppKit

/// Handles session logging to files
@MainActor
class SessionLogger: ObservableObject {
    @Published private(set) var isLogging = false
    @Published private(set) var currentLogPath: String?
    @Published private(set) var bytesLogged: Int = 0

    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "[HH:mm:ss.SSS] "
        return formatter
    }()

    var includeTimestamps: Bool = false
    var logDirectory: URL

    init() {
        // Default to Documents/SerialTerm Logs
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logDirectory = documentsPath.appendingPathComponent("SerialTerm Logs")
    }

    /// Start logging with optional custom name
    func startLogging(sessionName: String? = nil, customName: String? = nil) throws {
        guard !isLogging else { return }

        // Ensure log directory exists
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        // Generate filename
        let timestamp = dateFormatter.string(from: Date())
        let baseName: String
        if let custom = customName, !custom.isEmpty {
            baseName = custom
        } else if let session = sessionName, !session.isEmpty {
            baseName = "\(session)_\(timestamp)"
        } else {
            baseName = "session_\(timestamp)"
        }

        // Sanitize filename
        let sanitizedName = baseName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")

        let logURL = logDirectory.appendingPathComponent("\(sanitizedName).log")

        // Create file
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: logURL)

        // Write header
        let header = "=== SerialTerm Log ===\n"
            + "Started: \(Date())\n"
            + "Session: \(sessionName ?? "Unknown")\n"
            + "========================\n\n"
        if let headerData = header.data(using: .utf8) {
            try fileHandle?.write(contentsOf: headerData)
        }

        currentLogPath = logURL.path
        bytesLogged = 0
        isLogging = true
    }

    /// Stop logging
    func stopLogging() {
        guard isLogging else { return }

        // Write footer
        let footer = "\n========================\n"
            + "Ended: \(Date())\n"
            + "Total bytes logged: \(bytesLogged)\n"
            + "=== End of Log ===\n"
        if let footerData = footer.data(using: .utf8) {
            try? fileHandle?.write(contentsOf: footerData)
        }

        try? fileHandle?.close()
        fileHandle = nil
        isLogging = false
    }

    /// Log received data
    func logReceived(_ data: Data) {
        guard isLogging, let fileHandle = fileHandle else { return }

        var logData = Data()

        if includeTimestamps {
            let timestamp = timestampFormatter.string(from: Date())
            if let timestampData = "[RX] \(timestamp)".data(using: .utf8) {
                logData.append(timestampData)
            }
        }

        logData.append(data)
        bytesLogged += data.count

        try? fileHandle.write(contentsOf: logData)
    }

    /// Log sent data
    func logSent(_ data: Data) {
        guard isLogging, let fileHandle = fileHandle else { return }

        var logData = Data()

        if includeTimestamps {
            let timestamp = timestampFormatter.string(from: Date())
            if let timestampData = "[TX] \(timestamp)".data(using: .utf8) {
                logData.append(timestampData)
            }
        }

        logData.append(data)
        bytesLogged += data.count

        try? fileHandle.write(contentsOf: logData)
    }

    /// Log a text message (for events, not data)
    func logMessage(_ message: String) {
        guard isLogging, let fileHandle = fileHandle else { return }

        let timestamp = timestampFormatter.string(from: Date())
        let logLine = "\n--- \(timestamp)\(message) ---\n"
        if let data = logLine.data(using: .utf8) {
            try? fileHandle.write(contentsOf: data)
        }
    }

    /// Get list of existing log files
    func getLogFiles() -> [LogFileInfo] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logDirectory,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "log" }
            .compactMap { url -> LogFileInfo? in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let creationDate = attrs[.creationDate] as? Date,
                      let size = attrs[.size] as? Int else {
                    return nil
                }
                return LogFileInfo(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    creationDate: creationDate,
                    size: size
                )
            }
            .sorted { $0.creationDate > $1.creationDate }
    }

    /// Delete a log file
    func deleteLogFile(_ info: LogFileInfo) throws {
        try FileManager.default.removeItem(at: info.url)
    }

    /// Open log file in default application
    func openLogFile(_ info: LogFileInfo) {
        NSWorkspace.shared.open(info.url)
    }

    /// Reveal log file in Finder
    func revealLogFile(_ info: LogFileInfo) {
        NSWorkspace.shared.selectFile(info.url.path, inFileViewerRootedAtPath: "")
    }

    deinit {
        // Note: stopLogging() cannot be called here due to MainActor isolation
        // The caller should ensure stopLogging() is called before deinit
    }
}

/// Information about a log file
struct LogFileInfo: Identifiable, Hashable, Equatable {
    let url: URL
    let name: String
    let creationDate: Date
    let size: Int

    var id: URL { url }

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: LogFileInfo, rhs: LogFileInfo) -> Bool {
        lhs.url == rhs.url
    }
}
