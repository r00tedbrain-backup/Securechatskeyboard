import Foundation

/// Main Signal Protocol manager — singleton that handles all E2EE operations.
/// This is the iOS equivalent of Android's SignalProtocolMain.java.
///
/// NOTE: The actual libsignal-swift calls (SessionCipher, SessionBuilder, etc.)
/// are stubbed with TODO markers. Once LibSignalClient is added via SPM and the
/// Xcode project is set up, these will be filled in with real crypto calls.
/// The architecture, data flow, and storage are fully implemented.
final class SignalProtocolManager {

    static let shared = SignalProtocolManager()

    private let store = SignalStoreManager.shared

    // In-memory state
    private(set) var accountName: String?
    private(set) var deviceId: Int32 = 1
    private(set) var contacts: [Contact] = []
    private(set) var messages: [StorageMessage] = []
    private(set) var metadata: PreKeyMetadata = PreKeyMetadata()
    private(set) var isInitialized: Bool = false

    private init() {}

    // MARK: - Initialization

    /// Initialize the protocol for the first time (generate all keys).
    func initialize() {
        Logger.log("Initializing Signal Protocol...")

        // Generate UUID-based account name
        let name = UUID().uuidString
        let devId: Int32 = 1

        // TODO: Generate IdentityKeyPair using LibSignalClient
        // let identityKeyPair = IdentityKeyPair.generate()
        // let registrationId = Int32.random(in: 1...16380)

        // TODO: Generate signed pre-key
        // let signedPreKey = SignedPreKeyRecord(...)

        // TODO: Generate one-time pre-keys
        // let preKeys = (0..<PreKeyMetadata.oneTimePreKeyCount).map { ... }

        // TODO: Generate Kyber pre-key
        // let kyberKeyPair = KEMKeyPair.generate(.kyber1024)
        // let kyberPreKey = KyberPreKeyRecord(...)

        // Initialize metadata with rotation schedule
        var meta = PreKeyMetadata()
        meta.nextSignedPreKeyId = 1
        meta.activeSignedPreKeyId = 0
        meta.nextOneTimePreKeyId = Int32(PreKeyMetadata.oneTimePreKeyCount)
        meta.isSignedPreKeyRegistered = true
        meta.scheduleNextSignedPreKeyRefresh()
        meta.scheduleNextKyberPreKeyRefresh()

        // Save to persistent storage
        do {
            try store.saveAccountName(name)
            try store.saveAccountDeviceId(devId)
            // TODO: try store.saveIdentityKeyPair(identityKeyPair.serialize())
            // TODO: try store.saveLocalRegistrationId(registrationId)
            try store.saveMetadata(meta)
            try store.saveContacts([])
            try store.saveMessages([])
        } catch {
            Logger.log("ERROR: Failed to save initial protocol state: \(error)")
            return
        }

        self.accountName = name
        self.deviceId = devId
        self.metadata = meta
        self.contacts = []
        self.messages = []
        self.isInitialized = true

        Logger.log("Signal Protocol initialized. Account: \(name)")
    }

    /// Reload account from persistent storage (app restart, keyboard activation).
    func reloadAccount() {
        Logger.log("Reloading account from storage...")

        guard let name = store.loadAccountName() else {
            Logger.log("No account found in storage. Need to initialize.")
            initialize()
            return
        }

        self.accountName = name
        self.deviceId = store.loadAccountDeviceId() ?? 1
        self.contacts = store.loadContacts()
        self.messages = store.loadMessages()
        self.metadata = store.loadMetadata()
        self.isInitialized = true

        Logger.log("Account reloaded: \(name), \(contacts.count) contacts, \(messages.count) messages")
    }

    // MARK: - Encrypt

    /// Encrypt a plaintext message for the given contact.
    /// Returns a MessageEnvelope ready for serialization, or nil on failure.
    func encrypt(message: String, for contact: Contact) -> MessageEnvelope? {
        guard isInitialized, let name = accountName else {
            Logger.log("ERROR: Protocol not initialized")
            return nil
        }

        // Check if signed pre-key rotation is needed
        var envelope: MessageEnvelope? = nil
        if metadata.needsSignedPreKeyRefresh {
            Logger.log("Signed pre-key rotation needed")
            rotateSignedPreKey()
            envelope = createPreKeyResponseEnvelope()
        }

        // Check if Kyber pre-key rotation is needed
        if metadata.needsKyberPreKeyRefresh {
            Logger.log("Kyber pre-key rotation needed")
            rotateKyberPreKey()
        }

        // TODO: Actual encryption with libsignal-swift
        // let address = ProtocolAddress(name: contact.signalProtocolAddressName, deviceId: UInt32(contact.deviceId))
        // let sessionCipher = try SessionCipher(for: address, store: signalStore)
        // let ciphertext = try sessionCipher.encrypt(message.data(using: .utf8)!)

        // Placeholder: create envelope structure
        let ciphertextData = Data() // TODO: Replace with actual ciphertext
        let ciphertextType: Int32 = 2 // WHISPER_TYPE; TODO: use actual type

        if envelope != nil {
            // Key rotation happened — include ciphertext in existing envelope
            envelope?.ciphertextMessage = ciphertextData
            envelope?.ciphertextType = ciphertextType
        } else {
            envelope = MessageEnvelope(
                ciphertextMessage: ciphertextData,
                ciphertextType: ciphertextType,
                signalProtocolAddressName: name,
                deviceId: deviceId
            )
        }

        // Store the plaintext message locally
        let storageMsg = StorageMessage(
            contactUUID: contact.signalProtocolAddressName,
            senderUUID: name,
            recipientUUID: contact.signalProtocolAddressName,
            unencryptedMessage: message
        )
        messages.append(storageMsg)
        persistState()

        return envelope
    }

    // MARK: - Decrypt

    /// Decrypt a MessageEnvelope received from a contact.
    /// Returns the plaintext string, or throws on failure.
    func decrypt(envelope: MessageEnvelope, from contact: Contact) throws -> String {
        guard isInitialized else {
            throw ProtocolError.notInitialized
        }

        // If envelope contains updated pre-keys, process them first
        if envelope.preKeyResponse != nil && envelope.ciphertextMessage != nil {
            Logger.log("Message with updated preKeyResponse received")
            _ = processPreKeyResponse(envelope: envelope, contact: contact)
        }

        // TODO: Actual decryption with libsignal-swift
        // let address = ProtocolAddress(name: contact.signalProtocolAddressName, deviceId: UInt32(contact.deviceId))
        // let sessionCipher = try SessionCipher(for: address, store: signalStore)
        //
        // let plaintext: Data
        // if envelope.ciphertextType == CiphertextMessage.MessageType.preKey.rawValue {
        //     let preKeyMessage = try PreKeySignalMessage(bytes: envelope.ciphertextMessage!)
        //     plaintext = try sessionCipher.decrypt(message: preKeyMessage)
        // } else {
        //     let signalMessage = try SignalMessage(bytes: envelope.ciphertextMessage!)
        //     plaintext = try sessionCipher.decrypt(message: signalMessage)
        // }

        let decryptedMessage = "" // TODO: Replace with String(data: plaintext, encoding: .utf8)

        // Store decrypted message locally
        let storageMsg = StorageMessage(
            contactUUID: contact.signalProtocolAddressName,
            senderUUID: contact.signalProtocolAddressName,
            recipientUUID: accountName ?? "",
            timestamp: envelope.timestampAsDate,
            unencryptedMessage: decryptedMessage
        )
        messages.append(storageMsg)
        persistState()

        return decryptedMessage
    }

    // MARK: - PreKeyResponse (Invite Message)

    /// Create a PreKeyResponse envelope to send as an invite.
    func createPreKeyResponseEnvelope() -> MessageEnvelope? {
        guard let name = accountName else { return nil }

        // TODO: Build PreKeyResponseData from actual protocol store
        // let identityKey = store.loadIdentityKeyPair()
        // let signedPreKey = store.loadSignedPreKeys().last
        // let preKey = store.loadPreKeys().first
        // let kyberPreKey = store.loadKyberPreKeys().last

        let response = PreKeyResponseData(
            identityKey: Data(), // TODO: actual identity key
            devices: []          // TODO: actual device pre-key items
        )
        // TODO: Set Kyber fields on response

        return MessageEnvelope(
            preKeyResponse: response,
            signalProtocolAddressName: name,
            deviceId: deviceId
        )
    }

    /// Process a received PreKeyResponse (establish session with sender).
    func processPreKeyResponse(envelope: MessageEnvelope, contact: Contact) -> Bool {
        guard let preKeyResponse = envelope.preKeyResponse else { return false }

        Logger.log("Processing PreKeyResponse from \(contact.displayName)")

        // TODO: Reconstruct PreKeyBundle from preKeyResponse
        // TODO: Build session using SessionBuilder
        // let address = ProtocolAddress(name: contact.signalProtocolAddressName, deviceId: UInt32(contact.deviceId))
        // let builder = SessionBuilder(for: address, store: signalStore)
        // try builder.process(preKeyBundle)

        persistState()
        return true
    }

    // MARK: - Contact Management

    func addContact(firstName: String, lastName: String,
                    addressName: String, deviceId: Int32) throws -> Contact {
        guard !firstName.isEmpty, !addressName.isEmpty else {
            throw ProtocolError.invalidContact
        }

        let contact = Contact(
            firstName: firstName,
            lastName: lastName,
            signalProtocolAddressName: addressName,
            deviceId: deviceId
        )

        if contacts.contains(contact) {
            throw ProtocolError.duplicateContact
        }

        contacts.append(contact)
        persistState()
        return contact
    }

    func removeContact(_ contact: Contact) {
        contacts.removeAll { $0 == contact }

        // TODO: Delete session for this contact
        // let address = ProtocolAddress(name: contact.signalProtocolAddressName, deviceId: UInt32(contact.deviceId))
        // signalStore.sessionStore.deleteSession(for: address)

        // Remove messages for this contact
        messages.removeAll { $0.contactUUID == contact.signalProtocolAddressName }
        persistState()
    }

    func verifyContact(_ contact: Contact) {
        guard let index = contacts.firstIndex(of: contact) else { return }
        contacts[index].verified = true
        persistState()
    }

    // MARK: - Messages

    func getMessages(for contact: Contact) -> [StorageMessage] {
        return messages
            .filter { $0.contactUUID == contact.signalProtocolAddressName }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func deleteMessages(for contact: Contact) {
        messages.removeAll { $0.contactUUID == contact.signalProtocolAddressName }
        persistState()
    }

    // MARK: - Fingerprint Verification

    /// Generate a numeric fingerprint for contact verification.
    /// Returns 12 groups of 5-digit numbers.
    func generateFingerprint(for contact: Contact) -> [String]? {
        // TODO: Use NumericFingerprintGenerator from libsignal-swift
        // let generator = NumericFingerprintGenerator(iterations: 5200)
        // let localIdentity = store.loadIdentityKeyPair().publicKey
        // let remoteIdentity = ... (from session store)
        // let fingerprint = generator.createFor(
        //     version: 2,
        //     localIdentifier: accountName.data(using: .utf8)!,
        //     localIdentityKey: localIdentity,
        //     remoteIdentifier: contact.signalProtocolAddressName.data(using: .utf8)!,
        //     remoteIdentityKey: remoteIdentity
        // )
        // return fingerprint.displayable.formatted // 12 groups of 5 digits

        return nil // TODO: implement with libsignal
    }

    // MARK: - Key Rotation (Private)

    private func rotateSignedPreKey() {
        Logger.log("Rotating signed pre-key...")
        // TODO: Generate new signed pre-key using libsignal
        // let newSignedPreKey = SignedPreKeyRecord(...)
        // Save to store, update metadata
        metadata.scheduleNextSignedPreKeyRefresh()
        metadata.isSignedPreKeyRegistered = true
    }

    private func rotateKyberPreKey() {
        Logger.log("Rotating Kyber pre-key...")
        // TODO: Generate new Kyber pre-key using libsignal KEMKeyPair
        // let kyberKeyPair = KEMKeyPair.generate(.kyber1024)
        // let kyberPreKey = KyberPreKeyRecord(...)
        // Save to store, update metadata
        metadata.scheduleNextKyberPreKeyRefresh()
    }

    // MARK: - Persistence

    private func persistState() {
        do {
            try store.saveContacts(contacts)
            try store.saveMessages(messages)
            try store.saveMetadata(metadata)
        } catch {
            Logger.log("ERROR: Failed to persist state: \(error)")
        }
    }
}

// MARK: - Errors

enum ProtocolError: LocalizedError {
    case notInitialized
    case invalidContact
    case duplicateContact
    case unknownContact
    case noSession
    case decryptionFailed(String)
    case encryptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized: return "Signal Protocol is not initialized"
        case .invalidContact: return "Contact information is invalid or incomplete"
        case .duplicateContact: return "Contact already exists in the contact list"
        case .unknownContact: return "Contact not found in the contact list"
        case .noSession: return "No session exists with this contact"
        case .decryptionFailed(let msg): return "Decryption failed: \(msg)"
        case .encryptionFailed(let msg): return "Encryption failed: \(msg)"
        }
    }
}
