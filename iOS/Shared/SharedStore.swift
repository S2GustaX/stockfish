import Foundation

enum SharedStore {
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroup)
    }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: AppIdentity.appGroup) }

    static func saveSettings(_ value: AppSettings) {
        if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: "settings") }
    }
    static func loadSettings() -> AppSettings {
        guard let data = defaults?.data(forKey: "settings"),
              let value = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return value
    }

    private static func file(_ name: String) -> URL? { directory?.appendingPathComponent(name) }

    static func save<T: Encodable>(_ value: T, as name: String) {
        guard let url = file(name), let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func clearSession() {
        for fileName in ["tracking.json", "scan.json", "analysis.json", "broadcast.json"] {
            if let url = file(fileName) { try? FileManager.default.removeItem(at: url) }
        }
    }
}

struct BroadcastStatus: Codable {
    var active: Bool
    var message: String
    var timestamp: Date = Date()
}
