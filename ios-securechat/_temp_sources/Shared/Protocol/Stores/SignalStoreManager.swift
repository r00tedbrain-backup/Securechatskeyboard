import Foundation

/// Manages all Signal Protocol store data persistence.
/// This is the central persistence layer that replaces Android's SignalProtocolStoreImpl + StorageHelper.
///
/// On iOS, we split storage:
///   - Keychain: identity key pair (hardware-backed encryption)
///   - App Group files: session records, pre-keys, signed pre-keys, kyber pre-keys, sender keys
///   - App Group UserDefaults: metadata (rotation timestamps, active IDs)
///
/// All store data is serialized via Codable and stored as JSON.
/// libsignal-swift store protocols will be implemented once the SPM dependency is integrated.
final class SignalStoreManager {

    static let shared = SignalStoreManager()

    private let keychain = KeychainHelper.shared
    private let storage = AppGroupStorage.shared

    // MARK: - Keychain Keys

    private enum Keys {
        static let identityKeyPair = "signal.identityKeyPair"
        static let localRegistrationId = "signal.localRegistrationId"
        static let accountName = "signal.accountName"
        static let accountDeviceId = "signal.accountDeviceId"
    }

    // MARK: - File Names

    private enum Files {
        static let preKeys = "signal_prekeys.json"
        static let signedPreKeys = "signal_signed_prekeys.json"
        static let sessions = "signal_sessions.json"
        static let senderKeys = "signal_sender_keys.json"
        static let kyberPreKeys = "signal_kyber_prekeys.json"
        static let identityStore = "signal_identities.json"
        static let contacts = "signal_contacts.json"
        static let messages = "signal_messages.json"
        static let metadata = "signal_metadata.json"
    }

    private init() {}

    // MARK: - Identity Key Pair (Keychain — hardware-backed)

    func saveIdentityKeyPair(_ data: Data) throws {
        try keychain.save(data, forKey: Keys.identityKeyPair)
    }

    func loadIdentityKeyPair() -> Data? {
        return keychain.load(forKey: Keys.identityKeyPair)
    }

    // MARK: - Registration ID

    func saveLocalRegistrationId(_ id: Int32) throws {
        let data = withUnsafeBytes(of: id) { Data($0) }
        try keychain.save(data, forKey: Keys.localRegistrationId)
    }

    func loadLocalRegistrationId() -> Int32? {
        guard let data = keychain.load(forKey: Keys.localRegistrationId),
              data.count == MemoryLayout<Int32>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Int32.self) }
    }

    // MARK: - Account Info

    func saveAccountName(_ name: String) throws {
        try keychain.saveString(name, forKey: Keys.accountName)
    }

    func loadAccountName() -> String? {
        return keychain.loadString(forKey: Keys.accountName)
    }

    func saveAccountDeviceId(_ id: Int32) throws {
        let data = withUnsafeBytes(of: id) { Data($0) }
        try keychain.save(data, forKey: Keys.accountDeviceId)
    }

    func loadAccountDeviceId() -> Int32? {
        guard let data = keychain.load(forKey: Keys.accountDeviceId),
              data.count == MemoryLayout<Int32>.size else { return nil }
        return data.withUnsafeBytes { $0.load(as: Int32.self) }
    }

    // MARK: - Pre-Keys (App Group files)

    func savePreKeys(_ preKeys: [SerializablePreKey]) throws {
        try storage.saveEncodable(preKeys, filename: Files.preKeys)
    }

    func loadPreKeys() -> [SerializablePreKey] {
        return storage.loadDecodable(filename: Files.preKeys, as: [SerializablePreKey].self) ?? []
    }

    // MARK: - Signed Pre-Keys

    func saveSignedPreKeys(_ signedPreKeys: [SerializableSignedPreKey]) throws {
        try storage.saveEncodable(signedPreKeys, filename: Files.signedPreKeys)
    }

    func loadSignedPreKeys() -> [SerializableSignedPreKey] {
        return storage.loadDecodable(
            filename: Files.signedPreKeys, as: [SerializableSignedPreKey].self
        ) ?? []
    }

    // MARK: - Kyber Pre-Keys

    func saveKyberPreKeys(_ kyberPreKeys: [SerializableKyberPreKey]) throws {
        try storage.saveEncodable(kyberPreKeys, filename: Files.kyberPreKeys)
    }

    func loadKyberPreKeys() -> [SerializableKyberPreKey] {
        return storage.loadDecodable(
            filename: Files.kyberPreKeys, as: [SerializableKyberPreKey].self
        ) ?? []
    }

    // MARK: - Sessions

    func saveSessions(_ sessions: [String: Data]) throws {
        try storage.saveEncodable(sessions, filename: Files.sessions)
    }

    func loadSessions() -> [String: Data] {
        return storage.loadDecodable(filename: Files.sessions, as: [String: Data].self) ?? [:]
    }

    // MARK: - Sender Keys

    func saveSenderKeys(_ senderKeys: [String: Data]) throws {
        try storage.saveEncodable(senderKeys, filename: Files.senderKeys)
    }

    func loadSenderKeys() -> [String: Data] {
        return storage.loadDecodable(filename: Files.senderKeys, as: [String: Data].self) ?? [:]
    }

    // MARK: - Identity Store (trusted identities)

    func saveIdentities(_ identities: [String: Data]) throws {
        try storage.saveEncodable(identities, filename: Files.identityStore)
    }

    func loadIdentities() -> [String: Data] {
        return storage.loadDecodable(filename: Files.identityStore, as: [String: Data].self) ?? [:]
    }

    // MARK: - Contacts

    func saveContacts(_ contacts: [Contact]) throws {
        try storage.saveEncodable(contacts, filename: Files.contacts)
    }

    func loadContacts() -> [Contact] {
        return storage.loadDecodable(filename: Files.contacts, as: [Contact].self) ?? []
    }

    // MARK: - Messages

    func saveMessages(_ messages: [StorageMessage]) throws {
        try storage.saveEncodable(messages, filename: Files.messages)
    }

    func loadMessages() -> [StorageMessage] {
        return storage.loadDecodable(filename: Files.messages, as: [StorageMessage].self) ?? []
    }

    // MARK: - Pre-Key Metadata

    func saveMetadata(_ metadata: PreKeyMetadata) throws {
        try storage.saveEncodable(metadata, filename: Files.metadata)
    }

    func loadMetadata() -> PreKeyMetadata {
        return storage.loadDecodable(filename: Files.metadata, as: PreKeyMetadata.self)
            ?? PreKeyMetadata()
    }

    // MARK: - Wipe All Data

    func wipeAll() throws {
        try keychain.deleteAll()
        try storage.deleteFile(named: Files.preKeys)
        try storage.deleteFile(named: Files.signedPreKeys)
        try storage.deleteFile(named: Files.sessions)
        try storage.deleteFile(named: Files.senderKeys)
        try storage.deleteFile(named: Files.kyberPreKeys)
        try storage.deleteFile(named: Files.identityStore)
        try storage.deleteFile(named: Files.contacts)
        try storage.deleteFile(named: Files.messages)
        try storage.deleteFile(named: Files.metadata)
    }
}

// MARK: - Serializable Store Records

/// Serializable pre-key record for JSON storage
struct SerializablePreKey: Codable {
    let id: Int32
    let record: Data  // serialized PreKeyRecord bytes
}

/// Serializable signed pre-key record for JSON storage
struct SerializableSignedPreKey: Codable {
    let id: Int32
    let record: Data  // serialized SignedPreKeyRecord bytes
    let timestamp: Int64
}

/// Serializable Kyber pre-key record for JSON storage
struct SerializableKyberPreKey: Codable {
    let id: Int32
    let record: Data  // serialized KyberPreKeyRecord bytes
    let timestamp: Int64
    var used: Bool = false
}
