import Foundation
import CryptoKit

/// Shared storage accessible from both the main app and the keyboard extension.
/// Uses App Group UserDefaults for metadata and the shared file container for larger data.
///
/// ALL file data is encrypted at-rest using AES-256-GCM with a master key stored in the iOS Keychain
/// (hardware-backed via Secure Enclave on supported devices). This is the iOS equivalent of Android's
/// EncryptedSharedPreferences + EncryptedFile.
///
/// Encryption flow:
///   1. On first launch, a 256-bit AES master key is generated via CryptoKit
///   2. The master key is stored in the iOS Keychain (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
///   3. Every file write: JSON data -> AES-256-GCM encrypt with master key -> write ciphertext to disk
///   4. Every file read: read ciphertext -> AES-256-GCM decrypt with master key -> return JSON data
///   5. If decryption fails (e.g. corrupted data), attempts to read as plaintext for migration
final class AppGroupStorage {

    static let shared = AppGroupStorage()

    private let defaults: UserDefaults?
    private let containerURL: URL?

    /// The AES-256 master key used for encrypting all file data at rest.
    /// Generated once and persisted in the iOS Keychain.
    private var masterKey: SymmetricKey?

    /// Keychain key for the storage master encryption key
    private static let masterKeyKeychainKey = "storage.masterEncryptionKey"

    private init() {
        let groupID = KeychainHelper.appGroupID
        self.defaults = UserDefaults(suiteName: groupID)
        self.containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        )
        self.masterKey = loadOrCreateMasterKey()
    }

    // MARK: - Master Key Management

    /// Loads the master encryption key from Keychain, or generates a new one if none exists.
    /// The key is a 256-bit AES key stored with hardware-backed protection.
    private func loadOrCreateMasterKey() -> SymmetricKey? {
        let keychain = KeychainHelper.shared

        // Try to load existing master key
        if let keyData = keychain.load(forKey: Self.masterKeyKeychainKey),
           keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }

        // Generate new 256-bit master key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        do {
            try keychain.save(keyData, forKey: Self.masterKeyKeychainKey)
            return newKey
        } catch {
            // If we can't save the key, encryption won't work
            return nil
        }
    }

    // MARK: - AES-256-GCM Encryption / Decryption

    /// Encrypts data using AES-256-GCM with the master key.
    /// Returns: nonce (12 bytes) + ciphertext + tag (16 bytes)
    private func encrypt(_ plaintext: Data) throws -> Data {
        guard let key = masterKey else {
            throw StorageError.encryptionKeyUnavailable
        }
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealedBox.combined else {
            throw StorageError.encryptionFailed
        }
        return combined
    }

    /// Decrypts AES-256-GCM encrypted data using the master key.
    /// Input format: nonce (12 bytes) + ciphertext + tag (16 bytes)
    private func decrypt(_ ciphertext: Data) throws -> Data {
        guard let key = masterKey else {
            throw StorageError.encryptionKeyUnavailable
        }
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(sealedBox, using: key)
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

    // MARK: - Encrypted File Container (all data encrypted at-rest with AES-256-GCM)

    /// Saves data to the App Group container, encrypted with AES-256-GCM.
    /// Falls back to plaintext ONLY if the encryption key is unavailable (should never happen).
    func saveFile(_ data: Data, named filename: String) throws {
        guard let url = containerURL?.appendingPathComponent(filename) else {
            throw StorageError.containerUnavailable
        }
        let encrypted = try encrypt(data)
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Loads and decrypts data from the App Group container.
    /// If decryption fails, attempts to read as plaintext for backwards compatibility
    /// (migration from unencrypted storage), then re-saves encrypted.
    func loadFile(named filename: String) -> Data? {
        guard let url = containerURL?.appendingPathComponent(filename) else {
            return nil
        }
        guard let rawData = try? Data(contentsOf: url) else {
            return nil
        }

        // Try to decrypt (normal path for encrypted data)
        if let decrypted = try? decrypt(rawData) {
            return decrypted
        }

        // Decryption failed — this is likely unencrypted legacy data.
        // Validate it's actually valid JSON before accepting as plaintext migration.
        if JSONSerialization.isValidJSONObject(
            (try? JSONSerialization.jsonObject(with: rawData)) as Any
        ) {
            // Migration: re-save as encrypted
            if let encrypted = try? encrypt(rawData) {
                try? encrypted.write(to: url, options: [.atomic, .completeFileProtection])
            }
            return rawData
        }

        // Neither valid encrypted nor valid JSON — corrupted data
        return nil
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
    case encryptionKeyUnavailable
    case encryptionFailed

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "App Group container is not available"
        case .encryptionKeyUnavailable:
            return "Storage encryption master key is not available"
        case .encryptionFailed:
            return "Failed to encrypt data for storage"
        }
    }
}
