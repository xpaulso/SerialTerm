import Foundation

/// A saved connection profile for quick access
struct ConnectionProfile: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var portPath: String
    var config: SerialPortConfig
    var autoLog: Bool
    var logDirectory: String?
    var notes: String
    var lastUsed: Date?
    var useCount: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        portPath: String,
        config: SerialPortConfig = SerialPortConfig(),
        autoLog: Bool = false,
        logDirectory: String? = nil,
        notes: String = "",
        lastUsed: Date? = nil,
        useCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.portPath = portPath
        self.config = config
        self.autoLog = autoLog
        self.logDirectory = logDirectory
        self.notes = notes
        self.lastUsed = lastUsed
        self.useCount = useCount
        self.createdAt = createdAt
    }

    var displayName: String {
        name.isEmpty ? portPath.replacingOccurrences(of: "/dev/cu.", with: "") : name
    }

    var configSummary: String {
        config.summary
    }
}

/// Manages saved connection profiles
@MainActor
class ProfileManager: ObservableObject {
    static let shared = ProfileManager()

    @Published private(set) var profiles: [ConnectionProfile] = []

    private let defaultsKey = "ConnectionProfiles"

    private init() {
        loadProfiles()
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let profiles = try? JSONDecoder().decode([ConnectionProfile].self, from: data) {
            self.profiles = profiles
        }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Add a new profile
    func addProfile(_ profile: ConnectionProfile) {
        profiles.append(profile)
        saveProfiles()
    }

    /// Update an existing profile
    func updateProfile(_ profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()
        }
    }

    /// Delete a profile
    func deleteProfile(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles()
    }

    /// Delete profile by ID
    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        saveProfiles()
    }

    /// Mark profile as used (updates lastUsed and useCount)
    func markAsUsed(_ profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index].lastUsed = Date()
            profiles[index].useCount += 1
            saveProfiles()
        }
    }

    /// Get profile by ID
    func getProfile(id: UUID) -> ConnectionProfile? {
        profiles.first { $0.id == id }
    }

    /// Get profiles sorted by most recently used
    var recentProfiles: [ConnectionProfile] {
        profiles.sorted { (p1, p2) in
            let d1 = p1.lastUsed ?? Date.distantPast
            let d2 = p2.lastUsed ?? Date.distantPast
            return d1 > d2
        }
    }

    /// Get profiles sorted by most frequently used
    var frequentProfiles: [ConnectionProfile] {
        profiles.sorted { $0.useCount > $1.useCount }
    }

    /// Create profile from current connection
    func createProfile(
        name: String,
        portPath: String,
        config: SerialPortConfig,
        autoLog: Bool = false,
        notes: String = ""
    ) -> ConnectionProfile {
        let profile = ConnectionProfile(
            name: name,
            portPath: portPath,
            config: config,
            autoLog: autoLog,
            notes: notes
        )
        addProfile(profile)
        return profile
    }

    /// Find profile matching port path
    func findProfile(forPort portPath: String) -> ConnectionProfile? {
        profiles.first { $0.portPath == portPath }
    }

    /// Import profiles from JSON data
    func importProfiles(from data: Data) throws {
        let imported = try JSONDecoder().decode([ConnectionProfile].self, from: data)
        for profile in imported {
            if !profiles.contains(where: { $0.name == profile.name && $0.portPath == profile.portPath }) {
                profiles.append(profile)
            }
        }
        saveProfiles()
    }

    /// Export profiles to JSON data
    func exportProfiles() throws -> Data {
        try JSONEncoder().encode(profiles)
    }
}
