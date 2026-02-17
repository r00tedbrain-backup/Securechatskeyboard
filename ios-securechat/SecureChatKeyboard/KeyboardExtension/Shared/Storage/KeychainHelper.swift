import Foundation
import Security

/// Secure Keychain wrapper for storing cryptographic keys and sensitive data.
/// Replaces Android's EncryptedSharedPreferences with hardware-backed iOS Keychain.
/// Data is encrypted by iOS using the device passcode-derived key (Secure Enclave on supported devices).
final class KeychainHelper {

    static let shared = KeychainHelper()

    /// The App Group identifier shared between the main app and the keyboard extension.
    /// IMPORTANT: Replace with your actual App Group ID from Apple Developer Portal.
    static let appGroupID = "group.com.bwt.securechats"
    static let serviceID = "com.bwt.securechats.keychain"

    private init() {}

    // MARK: - Save

    func save(_ data: Data, forKey key: String) throws {
        // Delete existing item first to avoid duplicates
        try? delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceID,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrAccessGroup as String: Self.appGroupID
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status: status)
        }
    }

    func save<T: Encodable>(_ object: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(object)
        try save(data, forKey: key)
    }

    func saveString(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, forKey: key)
    }

    // MARK: - Load

    func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceID,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccessGroup as String: Self.appGroupID
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    func load<T: Decodable>(forKey key: String, as type: T.Type) -> T? {
        guard let data = load(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func loadString(forKey key: String) -> String? {
        guard let data = load(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Delete

    func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceID,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: Self.appGroupID
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    /// Delete all items for this service. Use with caution.
    func deleteAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceID,
            kSecAttrAccessGroup as String: Self.appGroupID
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    // MARK: - Existence Check

    func exists(forKey key: String) -> Bool {
        return load(forKey: key) != nil
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case saveFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        case .deleteFailed(let status):
            return "Keychain delete failed with status: \(status)"
        case .encodingFailed:
            return "Failed to encode data for Keychain storage"
        }
    }
}
