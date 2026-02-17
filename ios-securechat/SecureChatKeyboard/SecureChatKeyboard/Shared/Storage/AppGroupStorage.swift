import Foundation

/// Shared storage accessible from both the main app and the keyboard extension.
/// Uses App Group UserDefaults for metadata and the shared file container for larger data.
/// Equivalent to Android's StorageHelper.java (non-sensitive data portion).
final class AppGroupStorage {

    static let shared = AppGroupStorage()

    private let defaults: UserDefaults?
    private let containerURL: URL?

    private init() {
        let groupID = KeychainHelper.appGroupID
        self.defaults = UserDefaults(suiteName: groupID)
        self.containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        )
    }

    // MARK: - UserDefaults (metadata, rotation timestamps, settings)

    func set<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults?.set(data, forKey: key)
    }

    func get<T: Decodable>(forKey key: String, as type: T.Type) -> T? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func setInt(_ value: Int, forKey key: String) {
        defaults?.set(value, forKey: key)
    }

    func getInt(forKey key: String) -> Int {
        return defaults?.integer(forKey: key) ?? 0
    }

    func setInt64(_ value: Int64, forKey key: String) {
        defaults?.set(value, forKey: key)
    }

    func getInt64(forKey key: String) -> Int64 {
        return Int64(defaults?.integer(forKey: key) ?? 0)
    }

    func setBool(_ value: Bool, forKey key: String) {
        defaults?.set(value, forKey: key)
    }

    func getBool(forKey key: String) -> Bool {
        return defaults?.bool(forKey: key) ?? false
    }

    func setString(_ value: String, forKey key: String) {
        defaults?.set(value, forKey: key)
    }

    func getString(forKey key: String) -> String? {
        return defaults?.string(forKey: key)
    }

    func remove(forKey key: String) {
        defaults?.removeObject(forKey: key)
    }

    // MARK: - File Container (larger data: contacts, messages, session records)

    func saveFile(_ data: Data, named filename: String) throws {
        guard let url = containerURL?.appendingPathComponent(filename) else {
            throw StorageError.containerUnavailable
        }
        try data.write(to: url, options: .atomic)
    }

    func loadFile(named filename: String) -> Data? {
        guard let url = containerURL?.appendingPathComponent(filename) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    func deleteFile(named filename: String) throws {
        guard let url = containerURL?.appendingPathComponent(filename) else {
            throw StorageError.containerUnavailable
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func saveEncodable<T: Encodable>(_ object: T, filename: String) throws {
        let data = try JSONEncoder().encode(object)
        try saveFile(data, named: filename)
    }

    func loadDecodable<T: Decodable>(filename: String, as type: T.Type) -> T? {
        guard let data = loadFile(named: filename) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

enum StorageError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "App Group container is not available"
        }
    }
}
