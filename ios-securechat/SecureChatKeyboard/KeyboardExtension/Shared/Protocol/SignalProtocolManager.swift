import Foundation

/// Main Signal Protocol manager — singleton that handles all E2EE operations.
/// This is the iOS equivalent of Android's SignalProtocolMain.java.
///
/// Uses LibSignalClient free functions (signalEncrypt, signalDecrypt, processPreKeyBundle)
/// with InMemorySignalProtocolStore for session/key management and our custom
/// SignalStoreManager for persistent storage (Keychain + App Group files).
final class SignalProtocolManager {

    static let shared = SignalProtocolManager()

    private let store = SignalStoreManager.shared

    // In-memory protocol store (holds sessions, pre-keys, identity in RAM)
    private var protocolStore: InMemorySignalProtocolStore?
    private let context = NullContext()

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
        Logger.log("[INIT] ========== INITIALIZING SIGNAL PROTOCOL ==========")

        // Generate UUID-based account name
        let name = UUID().uuidString
        let devId: Int32 = 1
        Logger.log("[INIT] Generated accountName=\(name), deviceId=\(devId)")

        // 1. Generate IdentityKeyPair
        let identityKeyPair = IdentityKeyPair.generate()
        let registrationId = UInt32.random(in: 1...16380)

        // 2. Create the in-memory protocol store with generated identity
        let inMemStore = InMemorySignalProtocolStore(
            identity: identityKeyPair,
            registrationId: registrationId
        )

        // 3. Generate signed pre-key
        let signedPreKeyId: UInt32 = 0
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let signedPreKeyPrivate = PrivateKey.generate()
        let signedPreKeySignature = identityKeyPair.privateKey.generateSignature(
            message: signedPreKeyPrivate.publicKey.serialize()
        )

        let signedPreKey: SignedPreKeyRecord
        do {
            signedPreKey = try SignedPreKeyRecord(
                id: signedPreKeyId,
                timestamp: timestamp,
                privateKey: signedPreKeyPrivate,
                signature: signedPreKeySignature
            )
            try inMemStore.storeSignedPreKey(signedPreKey, id: signedPreKeyId, context: context)
        } catch {
            Logger.log("ERROR: Failed to create signed pre-key: \(error)")
            return
        }

        // 4. Generate one-time pre-keys
        let oneTimePreKeyCount = PreKeyMetadata.oneTimePreKeyCount
        var serializedPreKeys: [SerializablePreKey] = []
        do {
            for i in 0..<oneTimePreKeyCount {
                let preKeyId = UInt32(i)
                let preKeyPrivate = PrivateKey.generate()
                let preKeyRecord = try PreKeyRecord(id: preKeyId, privateKey: preKeyPrivate)
                try inMemStore.storePreKey(preKeyRecord, id: preKeyId, context: context)
                serializedPreKeys.append(SerializablePreKey(
                    id: Int32(preKeyId),
                    record: preKeyRecord.serialize()
                ))
            }
        } catch {
            Logger.log("ERROR: Failed to create one-time pre-keys: \(error)")
            return
        }

        // 5. Generate Kyber pre-key (post-quantum)
        let kyberPreKeyId: UInt32 = 0
        let kyberKeyPair = KEMKeyPair.generate()
        let kyberSignature = identityKeyPair.privateKey.generateSignature(
            message: kyberKeyPair.publicKey.serialize()
        )

        let kyberPreKey: KyberPreKeyRecord
        do {
            kyberPreKey = try KyberPreKeyRecord(
                id: kyberPreKeyId,
                timestamp: timestamp,
                keyPair: kyberKeyPair,
                signature: kyberSignature
            )
            try inMemStore.storeKyberPreKey(kyberPreKey, id: kyberPreKeyId, context: context)
        } catch {
            Logger.log("ERROR: Failed to create Kyber pre-key: \(error)")
            return
        }

        // 6. Initialize metadata with rotation schedule
        var meta = PreKeyMetadata()
        meta.nextSignedPreKeyId = 1
        meta.activeSignedPreKeyId = Int32(signedPreKeyId)
        meta.nextOneTimePreKeyId = oneTimePreKeyCount
        meta.isSignedPreKeyRegistered = true
        meta.scheduleNextSignedPreKeyRefresh()
        meta.scheduleNextKyberPreKeyRefresh()

        // 7. Persist everything
        do {
            try store.saveAccountName(name)
            try store.saveAccountDeviceId(devId)
            try store.saveIdentityKeyPair(identityKeyPair.serialize())
            try store.saveLocalRegistrationId(Int32(registrationId))
            try store.savePreKeys(serializedPreKeys)
            try store.saveSignedPreKeys([SerializableSignedPreKey(
                id: Int32(signedPreKeyId),
                record: signedPreKey.serialize(),
                timestamp: Int64(timestamp)
            )])
            try store.saveKyberPreKeys([SerializableKyberPreKey(
                id: Int32(kyberPreKeyId),
                record: kyberPreKey.serialize(),
                timestamp: Int64(timestamp)
            )])
            try store.saveMetadata(meta)
            try store.saveContacts([])
            try store.saveMessages([])
        } catch {
            Logger.log("ERROR: Failed to save initial protocol state: \(error)")
            return
        }

        self.protocolStore = inMemStore
        self.accountName = name
        self.deviceId = devId
        self.metadata = meta
        self.contacts = []
        self.messages = []
        self.isInitialized = true

        Logger.log("[INIT] Signal Protocol initialized OK. Account=\(name), regId=\(registrationId), signedPreKeyId=\(signedPreKeyId), oneTimePreKeys=\(oneTimePreKeyCount), kyberPreKeyId=\(kyberPreKeyId)")
    }

    /// Reload account from persistent storage (app restart, keyboard activation).
    func reloadAccount() {
        Logger.log("[RELOAD] ========== RELOADING ACCOUNT FROM STORAGE ==========")

        guard let name = store.loadAccountName() else {
            Logger.log("[RELOAD] No account found in storage. Will initialize fresh.")
            initialize()
            return
        }
        Logger.log("[RELOAD] Found accountName=\(name)")

        // Reconstruct identity key pair from persisted bytes
        guard let identityData = store.loadIdentityKeyPair(),
              let regIdInt32 = store.loadLocalRegistrationId() else {
            Logger.log("[RELOAD] ERROR: Missing identity key pair or registration ID. Re-initializing.")
            initialize()
            return
        }
        Logger.log("[RELOAD] identityData=\(identityData.count) bytes, regId=\(regIdInt32)")

        // Check for corrupted state: account exists in Keychain but prekeys were deleted
        // (happens when app is uninstalled and reinstalled - Keychain persists but App Group files are deleted)
        if store.loadPreKeys().isEmpty && store.loadSignedPreKeys().isEmpty && store.loadKyberPreKeys().isEmpty {
            Logger.log("[RELOAD] CORRUPTED STATE DETECTED: Account exists in Keychain but no prekeys found in App Group files. Wiping Keychain and re-initializing.")
            try? store.wipeAll()
            initialize()
            return
        }

        let identityKeyPair: IdentityKeyPair
        do {
            identityKeyPair = try IdentityKeyPair(bytes: identityData)
        } catch {
            Logger.log("[RELOAD] ERROR: Failed to deserialize identity key pair: \(error). Re-initializing.")
            initialize()
            return
        }

        let registrationId = UInt32(regIdInt32)
        let inMemStore = InMemorySignalProtocolStore(
            identity: identityKeyPair,
            registrationId: registrationId
        )

        // Reload pre-keys into in-memory store
        let preKeys = store.loadPreKeys()
        let signedPreKeys = store.loadSignedPreKeys()
        let kyberPreKeys = store.loadKyberPreKeys()
        Logger.log("[RELOAD] Loading preKeys=\(preKeys.count), signedPreKeys=\(signedPreKeys.count), kyberPreKeys=\(kyberPreKeys.count)")

        do {
            for spk in preKeys {
                let record = try PreKeyRecord(bytes: spk.record)
                try inMemStore.storePreKey(record, id: UInt32(spk.id), context: context)
                Logger.log("[RELOAD] Loaded preKey id=\(spk.id)")
            }
            for signedPk in signedPreKeys {
                let record = try SignedPreKeyRecord(bytes: signedPk.record)
                try inMemStore.storeSignedPreKey(record, id: UInt32(signedPk.id), context: context)
                Logger.log("[RELOAD] Loaded signedPreKey id=\(signedPk.id)")
            }
            for kyberPk in kyberPreKeys {
                let record = try KyberPreKeyRecord(bytes: kyberPk.record)
                try inMemStore.storeKyberPreKey(record, id: UInt32(kyberPk.id), context: context)
                Logger.log("[RELOAD] Loaded kyberPreKey id=\(kyberPk.id)")
            }
        } catch {
            Logger.log("[RELOAD] ERROR: Failed to reload pre-keys: \(error)")
        }

        // Reload sessions into in-memory store
        let sessions = store.loadSessions()
        Logger.log("[RELOAD] Loading \(sessions.count) sessions")
        for (addressKey, sessionData) in sessions {
            do {
                let parts = addressKey.split(separator: ".")
                guard parts.count == 2,
                      let devIdUInt = UInt32(parts[1]) else {
                    Logger.log("[RELOAD] WARN: Skipping malformed session key: \(addressKey)")
                    continue
                }
                let address = try ProtocolAddress(name: String(parts[0]), deviceId: devIdUInt)
                let sessionRecord = try SessionRecord(bytes: sessionData)
                try inMemStore.storeSession(sessionRecord, for: address, context: context)
                Logger.log("[RELOAD] Loaded session for \(addressKey) (\(sessionData.count) bytes)")
            } catch {
                Logger.log("[RELOAD] ERROR: Failed to reload session for \(addressKey): \(error)")
            }
        }

        // Reload trusted identities
        let identities = store.loadIdentities()
        Logger.log("[RELOAD] Loading \(identities.count) trusted identities")
        for (addressKey, identityData) in identities {
            do {
                let parts = addressKey.split(separator: ".")
                guard parts.count == 2,
                      let devIdUInt = UInt32(parts[1]) else {
                    Logger.log("[RELOAD] WARN: Skipping malformed identity key: \(addressKey)")
                    continue
                }
                let address = try ProtocolAddress(name: String(parts[0]), deviceId: devIdUInt)
                let identityKey = try IdentityKey(bytes: identityData)
                _ = try inMemStore.saveIdentity(identityKey, for: address, context: context)
                Logger.log("[RELOAD] Loaded identity for \(addressKey) (\(identityData.count) bytes)")
            } catch {
                Logger.log("[RELOAD] ERROR: Failed to reload identity for \(addressKey): \(error)")
            }
        }

        self.protocolStore = inMemStore
        self.accountName = name
        self.deviceId = store.loadAccountDeviceId() ?? 1
        self.contacts = store.loadContacts()
        self.messages = store.loadMessages()
        self.metadata = store.loadMetadata()
        self.isInitialized = true

        Logger.log("[RELOAD] ========== RELOAD COMPLETE ==========")
        Logger.log("[RELOAD] account=\(name), deviceId=\(self.deviceId), contacts=\(contacts.count), messages=\(messages.count), sessions=\(sessions.count), identities=\(identities.count)")
        Logger.log("[RELOAD] metadata: activeSignedPreKeyId=\(metadata.activeSignedPreKeyId), nextOneTimePreKeyId=\(metadata.nextOneTimePreKeyId), needsSignedRefresh=\(metadata.needsSignedPreKeyRefresh), needsKyberRefresh=\(metadata.needsKyberPreKeyRefresh)")
    }

    // MARK: - Encrypt

    /// Encrypt a plaintext message for the given contact.
    /// Returns a MessageEnvelope ready for serialization, or nil on failure.
    func encrypt(message: String, for contact: Contact) -> MessageEnvelope? {
        Logger.log("[ENCRYPT] ========== ENCRYPTING MESSAGE ==========")
        Logger.log("[ENCRYPT] message=\"\(message)\" for contact=\(contact.displayName) addr=\(contact.signalProtocolAddressName) devId=\(contact.deviceId)")

        guard isInitialized, let name = accountName, let inMemStore = protocolStore else {
            Logger.log("[ENCRYPT] ERROR: Protocol not initialized! isInit=\(isInitialized), name=\(accountName ?? "nil"), store=\(protocolStore != nil)")
            return nil
        }
        Logger.log("[ENCRYPT] Protocol OK: myAccount=\(name), myDeviceId=\(deviceId)")

        // Check if signed pre-key rotation is needed
        var envelope: MessageEnvelope? = nil
        if metadata.needsSignedPreKeyRefresh {
            Logger.log("[ENCRYPT] Signed pre-key rotation needed, rotating...")
            rotateSignedPreKey()
            envelope = createPreKeyResponseEnvelope()
            Logger.log("[ENCRYPT] Key rotation envelope created: \(envelope != nil)")
        }

        // Check if Kyber pre-key rotation is needed
        if metadata.needsKyberPreKeyRefresh {
            Logger.log("[ENCRYPT] Kyber pre-key rotation needed, rotating...")
            rotateKyberPreKey()
        }

        // Encrypt with LibSignalClient
        guard let plaintextData = message.data(using: .utf8) else {
            Logger.log("[ENCRYPT] ERROR: Failed to encode message as UTF-8")
            return nil
        }
        Logger.log("[ENCRYPT] plaintext size=\(plaintextData.count) bytes")

        do {
            let address = try ProtocolAddress(
                name: contact.signalProtocolAddressName,
                deviceId: UInt32(contact.deviceId)
            )
            Logger.log("[ENCRYPT] Target address: \(address.name).\(address.deviceId)")

            // Check if session exists
            let existingSession = try inMemStore.loadSession(for: address, context: context)
            Logger.log("[ENCRYPT] Session exists: \(existingSession != nil)")

            let ciphertext = try signalEncrypt(
                message: plaintextData,
                for: address,
                sessionStore: inMemStore,
                identityStore: inMemStore,
                context: context
            )

            let ciphertextData = ciphertext.serialize()
            let ciphertextType = Int32(ciphertext.messageType.rawValue)
            Logger.log("[ENCRYPT] SUCCESS! ciphertextType=\(ciphertextType) (3=prekey, 2=whisper), ciphertext=\(ciphertextData.count) bytes")

            // Persist session state after encrypt
            persistSessionState(for: address)

            if envelope != nil {
                // Key rotation happened — include ciphertext in existing envelope
                envelope?.ciphertextMessage = ciphertextData
                envelope?.ciphertextType = ciphertextType
                Logger.log("[ENCRYPT] Attached ciphertext to rotation envelope")
            } else {
                envelope = MessageEnvelope(
                    ciphertextMessage: ciphertextData,
                    ciphertextType: ciphertextType,
                    signalProtocolAddressName: name,
                    deviceId: deviceId
                )
                Logger.log("[ENCRYPT] Created new envelope: sender=\(name), devId=\(deviceId)")
            }
        } catch {
            Logger.log("[ENCRYPT] ERROR: Encryption failed: \(error)")
            return nil
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

        Logger.log("[ENCRYPT] ========== ENCRYPT COMPLETE ==========")
        return envelope
    }

    // MARK: - Decrypt

    /// Decrypt a MessageEnvelope received from a contact.
    /// Returns the plaintext string, or throws on failure.
    func decrypt(envelope: MessageEnvelope, from contact: Contact) throws -> String {
        Logger.log("[DECRYPT] ========== DECRYPTING MESSAGE ==========")
        Logger.log("[DECRYPT] from contact=\(contact.displayName) addr=\(contact.signalProtocolAddressName) devId=\(contact.deviceId)")
        Logger.log("[DECRYPT] envelope: ciphertextType=\(envelope.ciphertextType), ciphertext=\(envelope.ciphertextMessage?.count ?? 0) bytes, hasPreKeyResponse=\(envelope.preKeyResponse != nil), sender=\(envelope.signalProtocolAddressName), senderDevId=\(envelope.deviceId)")

        guard isInitialized, let inMemStore = protocolStore else {
            Logger.log("[DECRYPT] ERROR: Protocol not initialized!")
            throw ProtocolError.notInitialized
        }

        // If envelope contains updated pre-keys, process them first
        if envelope.preKeyResponse != nil && envelope.ciphertextMessage != nil {
            Logger.log("[DECRYPT] Message has updated preKeyResponse, processing first...")
            let ok = processPreKeyResponse(envelope: envelope, contact: contact)
            Logger.log("[DECRYPT] preKeyResponse processing result: \(ok)")
        }

        guard let ciphertextData = envelope.ciphertextMessage else {
            Logger.log("[DECRYPT] ERROR: No ciphertext data in envelope!")
            throw ProtocolError.decryptionFailed("No ciphertext data in envelope")
        }

        let address = try ProtocolAddress(
            name: contact.signalProtocolAddressName,
            deviceId: UInt32(contact.deviceId)
        )
        Logger.log("[DECRYPT] Decrypting from address: \(address.name).\(address.deviceId)")

        // Check if session exists
        let existingSession = try inMemStore.loadSession(for: address, context: context)
        Logger.log("[DECRYPT] Session exists for this address: \(existingSession != nil)")

        // Check if identity exists
        let existingIdentity = try inMemStore.identity(for: address, context: context)
        Logger.log("[DECRYPT] Identity exists for this address: \(existingIdentity != nil)")

        let plaintext: Data
        let msgType = CiphertextMessage.MessageType(rawValue: UInt8(envelope.ciphertextType))
        Logger.log("[DECRYPT] ciphertextType raw=\(envelope.ciphertextType), msgType=\(String(describing: msgType)) (3=preKey, 2=whisper)")

        if msgType == .preKey {
            Logger.log("[DECRYPT] Decrypting as PreKey message...")
            // PreKey message — first message in a conversation
            do {
                let preKeyMessage = try PreKeySignalMessage(bytes: ciphertextData)
                Logger.log("[DECRYPT] PreKeySignalMessage parsed OK: preKeyId=\(String(describing: preKeyMessage.preKeyId)), signedPreKeyId=\(preKeyMessage.signedPreKeyId)")
                plaintext = try signalDecryptPreKey(
                    message: preKeyMessage,
                    from: address,
                    sessionStore: inMemStore,
                    identityStore: inMemStore,
                    preKeyStore: inMemStore,
                    signedPreKeyStore: inMemStore,
                    kyberPreKeyStore: inMemStore,
                    context: context
                )
                Logger.log("[DECRYPT] PreKey decrypt SUCCESS, plaintext=\(plaintext.count) bytes")
            } catch {
                Logger.log("[DECRYPT] ERROR: PreKey decrypt FAILED: \(error)")
                throw error
            }
        } else {
            Logger.log("[DECRYPT] Decrypting as Whisper (Signal) message...")
            // Whisper message — subsequent messages in established session
            do {
                let signalMessage = try SignalMessage(bytes: ciphertextData)
                Logger.log("[DECRYPT] SignalMessage parsed OK")
                plaintext = try signalDecrypt(
                    message: signalMessage,
                    from: address,
                    sessionStore: inMemStore,
                    identityStore: inMemStore,
                    context: context
                )
                Logger.log("[DECRYPT] Whisper decrypt SUCCESS, plaintext=\(plaintext.count) bytes")
            } catch {
                Logger.log("[DECRYPT] ERROR: Whisper decrypt FAILED: \(error)")
                throw error
            }
        }

        // Persist session state after decrypt
        persistSessionState(for: address)

        guard let decryptedMessage = String(data: plaintext, encoding: .utf8) else {
            Logger.log("[DECRYPT] ERROR: Failed to decode plaintext as UTF-8")
            throw ProtocolError.decryptionFailed("Failed to decode plaintext as UTF-8")
        }
        Logger.log("[DECRYPT] Decrypted message: \"\(decryptedMessage)\"")

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

        Logger.log("[DECRYPT] ========== DECRYPT COMPLETE ==========")
        return decryptedMessage
    }

    // MARK: - PreKeyResponse (Invite Message)

    /// Create a PreKeyResponse envelope to send as an invite.
    func createPreKeyResponseEnvelope() -> MessageEnvelope? {
        Logger.log("[INVITE] ========== CREATING PREKEY RESPONSE (INVITE) ==========")
        guard let name = accountName, let inMemStore = protocolStore else {
            Logger.log("[INVITE] ERROR: No account or store!")
            return nil
        }
        Logger.log("[INVITE] myAccount=\(name), myDeviceId=\(deviceId)")

        do {
            let identityKeyPair = try inMemStore.identityKeyPair(context: context)
            let registrationId = try inMemStore.localRegistrationId(context: context)
            Logger.log("[INVITE] identityKey=\(identityKeyPair.identityKey.serialize().count) bytes, regId=\(registrationId)")

            // Get current signed pre-key
            let signedPreKeyId = UInt32(metadata.activeSignedPreKeyId)
            Logger.log("[INVITE] activeSignedPreKeyId=\(signedPreKeyId)")
            let signedPreKeyRecord = try inMemStore.loadSignedPreKey(id: signedPreKeyId, context: context)
            let signedPreKeyPublic = try signedPreKeyRecord.publicKey()
            Logger.log("[INVITE] signedPreKey loaded OK, pubKey=\(signedPreKeyPublic.serialize().count) bytes, signature=\(signedPreKeyRecord.signature.count) bytes")

            // Get first available one-time pre-key
            let preKeys = store.loadPreKeys()
            Logger.log("[INVITE] Available one-time preKeys: \(preKeys.count)")
            var preKeyData: PreKeyData?
            if let firstPreKey = preKeys.first {
                let preKeyRecord = try PreKeyRecord(bytes: firstPreKey.record)
                let preKeyPublic = try preKeyRecord.publicKey()
                preKeyData = PreKeyData(
                    keyId: firstPreKey.id,
                    publicKey: preKeyPublic.serialize()
                )
                Logger.log("[INVITE] Using one-time preKey id=\(firstPreKey.id), pubKey=\(preKeyPublic.serialize().count) bytes")
            } else {
                Logger.log("[INVITE] WARNING: No one-time preKeys available!")
            }

            let signedPreKeyData = SignedPreKeyData(
                keyId: Int32(signedPreKeyId),
                publicKey: signedPreKeyPublic.serialize(),
                signature: signedPreKeyRecord.signature
            )

            let deviceItem = PreKeyResponseItemData(
                deviceId: deviceId,
                registrationId: Int32(registrationId),
                signedPreKey: signedPreKeyData,
                preKey: preKeyData ?? PreKeyData(keyId: 0, publicKey: Data())
            )

            var response = PreKeyResponseData(
                identityKey: identityKeyPair.identityKey.serialize(),
                devices: [deviceItem]
            )

            // Add Kyber pre-key data
            let kyberPreKeys = store.loadKyberPreKeys()
            Logger.log("[INVITE] Available kyber preKeys: \(kyberPreKeys.count)")
            if let lastKyber = kyberPreKeys.last {
                let kyberRecord = try KyberPreKeyRecord(bytes: lastKyber.record)
                let kyberPubKey = try kyberRecord.publicKey()
                response.kyberPubKey = kyberPubKey.serialize()
                response.kyberPreKeyId = lastKyber.id
                response.kyberSignature = kyberRecord.signature
                Logger.log("[INVITE] Kyber preKey id=\(lastKyber.id), pubKey=\(kyberPubKey.serialize().count) bytes, signature=\(kyberRecord.signature.count) bytes")
            } else {
                Logger.log("[INVITE] WARNING: No Kyber preKeys available!")
            }

            let envelope = MessageEnvelope(
                preKeyResponse: response,
                signalProtocolAddressName: name,
                deviceId: deviceId
            )
            Logger.log("[INVITE] ========== INVITE ENVELOPE CREATED OK ==========")
            Logger.log("[INVITE] sender=\(name), deviceId=\(deviceId), hasPreKeyResponse=true")
            return envelope
        } catch {
            Logger.log("[INVITE] ERROR: Failed to create PreKeyResponse envelope: \(error)")
            return nil
        }
    }

    /// Process a received PreKeyResponse (establish session with sender).
    func processPreKeyResponse(envelope: MessageEnvelope, contact: Contact) -> Bool {
        Logger.log("[PROCESS_PKR] ========== PROCESSING PREKEY RESPONSE ==========")
        Logger.log("[PROCESS_PKR] from contact=\(contact.displayName) addr=\(contact.signalProtocolAddressName) devId=\(contact.deviceId)")

        guard let preKeyResponse = envelope.preKeyResponse,
              let inMemStore = protocolStore else {
            Logger.log("[PROCESS_PKR] ERROR: No preKeyResponse or protocolStore is nil!")
            return false
        }

        Logger.log("[PROCESS_PKR] identityKey=\(preKeyResponse.identityKey.count) bytes, devices=\(preKeyResponse.devices.count)")
        Logger.log("[PROCESS_PKR] kyberPubKey=\(preKeyResponse.kyberPubKey?.count ?? 0) bytes, kyberPreKeyId=\(preKeyResponse.kyberPreKeyId ?? -1), kyberSignature=\(preKeyResponse.kyberSignature?.count ?? 0) bytes")

        do {
            // Reconstruct PreKeyBundle from preKeyResponse
            let remoteIdentityKey = try IdentityKey(bytes: preKeyResponse.identityKey)
            Logger.log("[PROCESS_PKR] Remote identity key parsed OK")

            guard let deviceItem = preKeyResponse.devices.first else {
                Logger.log("[PROCESS_PKR] ERROR: No device items in PreKeyResponse")
                return false
            }
            Logger.log("[PROCESS_PKR] deviceItem: devId=\(deviceItem.deviceId), regId=\(deviceItem.registrationId)")
            Logger.log("[PROCESS_PKR] signedPreKey: keyId=\(deviceItem.signedPreKey.keyId), pubKey=\(deviceItem.signedPreKey.publicKey.count)b, sig=\(deviceItem.signedPreKey.signature.count)b")
            Logger.log("[PROCESS_PKR] preKey: keyId=\(deviceItem.preKey.keyId), pubKey=\(deviceItem.preKey.publicKey.count)b")

            let signedPreKeyPublic = try PublicKey(deviceItem.signedPreKey.publicKey)
            Logger.log("[PROCESS_PKR] signedPreKeyPublic parsed OK")

            let preKeyPublic = try PublicKey(deviceItem.preKey.publicKey)
            Logger.log("[PROCESS_PKR] preKeyPublic parsed OK")

            // Kyber pre-key is required for PreKeyBundle constructor
            guard let kyberPubKeyData = preKeyResponse.kyberPubKey,
                  let kyberPreKeyId = preKeyResponse.kyberPreKeyId,
                  let kyberSignatureData = preKeyResponse.kyberSignature else {
                Logger.log("[PROCESS_PKR] ERROR: Missing Kyber pre-key data! kyberPubKey=\(preKeyResponse.kyberPubKey != nil), kyberPreKeyId=\(preKeyResponse.kyberPreKeyId != nil), kyberSignature=\(preKeyResponse.kyberSignature != nil)")
                return false
            }

            let kyberPubKey = try KEMPublicKey(kyberPubKeyData)
            Logger.log("[PROCESS_PKR] Kyber public key parsed OK (id=\(kyberPreKeyId))")

            Logger.log("[PROCESS_PKR] Creating PreKeyBundle...")
            let bundle = try PreKeyBundle(
                registrationId: UInt32(deviceItem.registrationId),
                deviceId: UInt32(deviceItem.deviceId),
                prekeyId: UInt32(deviceItem.preKey.keyId),
                prekey: preKeyPublic,
                signedPrekeyId: UInt32(deviceItem.signedPreKey.keyId),
                signedPrekey: signedPreKeyPublic,
                signedPrekeySignature: deviceItem.signedPreKey.signature,
                identity: remoteIdentityKey,
                kyberPrekeyId: UInt32(kyberPreKeyId),
                kyberPrekey: kyberPubKey,
                kyberPrekeySignature: kyberSignatureData
            )
            Logger.log("[PROCESS_PKR] PreKeyBundle created OK")

            let address = try ProtocolAddress(
                name: contact.signalProtocolAddressName,
                deviceId: UInt32(contact.deviceId)
            )
            Logger.log("[PROCESS_PKR] Target address: \(address.name).\(address.deviceId)")

            // Check for existing session before processing
            let existingSession = try inMemStore.loadSession(for: address, context: context)
            Logger.log("[PROCESS_PKR] Existing session before processing: \(existingSession != nil)")

            // Process bundle to establish session
            try processPreKeyBundle(
                bundle,
                for: address,
                sessionStore: inMemStore,
                identityStore: inMemStore,
                context: context
            )
            Logger.log("[PROCESS_PKR] processPreKeyBundle completed OK!")

            // Verify session was created
            let newSession = try inMemStore.loadSession(for: address, context: context)
            Logger.log("[PROCESS_PKR] Session after processing: \(newSession != nil)")

            // Persist session and identity
            persistSessionState(for: address)
            persistIdentityState(for: address)

            Logger.log("[PROCESS_PKR] Session established with \(contact.displayName)")
            Logger.log("[PROCESS_PKR] ========== PROCESS PKR COMPLETE ==========")
        } catch {
            Logger.log("[PROCESS_PKR] ERROR: Failed to process PreKeyResponse: \(error)")
            return false
        }

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

        // Delete session for this contact from in-memory store
        // (InMemorySignalProtocolStore does not expose deleteSession,
        // so we remove it from persistent storage only)
        let addressKey = "\(contact.signalProtocolAddressName).\(contact.deviceId)"
        var sessions = store.loadSessions()
        sessions.removeValue(forKey: addressKey)
        try? store.saveSessions(sessions)

        var identities = store.loadIdentities()
        identities.removeValue(forKey: addressKey)
        try? store.saveIdentities(identities)

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
        guard let inMemStore = protocolStore, let name = accountName else { return nil }

        do {
            let localIdentityKeyPair = try inMemStore.identityKeyPair(context: context)
            let localPublicKey = localIdentityKeyPair.publicKey

            // Look up remote identity from the identity store
            let address = try ProtocolAddress(
                name: contact.signalProtocolAddressName,
                deviceId: UInt32(contact.deviceId)
            )
            guard let remoteIdentity = try inMemStore.identity(for: address, context: context) else {
                Logger.log("ERROR: No remote identity found for \(contact.displayName)")
                return nil
            }
            let remotePublicKey = remoteIdentity.publicKey

            let generator = NumericFingerprintGenerator(iterations: 5200)
            let fingerprint = try generator.create(
                version: 2,
                localIdentifier: Data(name.utf8),
                localKey: localPublicKey,
                remoteIdentifier: Data(contact.signalProtocolAddressName.utf8),
                remoteKey: remotePublicKey
            )

            // Split the formatted string into 12 groups of 5 digits
            let formatted = fingerprint.displayable.formatted
            var groups: [String] = []
            var index = formatted.startIndex
            while index < formatted.endIndex {
                let end = formatted.index(index, offsetBy: 5, limitedBy: formatted.endIndex) ?? formatted.endIndex
                groups.append(String(formatted[index..<end]))
                index = end
            }

            return groups
        } catch {
            Logger.log("ERROR: Failed to generate fingerprint: \(error)")
            return nil
        }
    }

    // MARK: - Key Rotation (Private)

    private func rotateSignedPreKey() {
        Logger.log("Rotating signed pre-key...")

        guard let inMemStore = protocolStore else { return }

        do {
            let identityKeyPair = try inMemStore.identityKeyPair(context: context)
            let newSignedPreKeyId = UInt32(metadata.nextSignedPreKeyId)
            let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
            let newPrivateKey = PrivateKey.generate()
            let signature = identityKeyPair.privateKey.generateSignature(
                message: newPrivateKey.publicKey.serialize()
            )

            let newSignedPreKey = try SignedPreKeyRecord(
                id: newSignedPreKeyId,
                timestamp: timestamp,
                privateKey: newPrivateKey,
                signature: signature
            )

            try inMemStore.storeSignedPreKey(newSignedPreKey, id: newSignedPreKeyId, context: context)

            // Persist to disk
            var signedPreKeys = store.loadSignedPreKeys()
            signedPreKeys.append(SerializableSignedPreKey(
                id: Int32(newSignedPreKeyId),
                record: newSignedPreKey.serialize(),
                timestamp: Int64(timestamp)
            ))
            try store.saveSignedPreKeys(signedPreKeys)

            metadata.activeSignedPreKeyId = Int32(newSignedPreKeyId)
            metadata.nextSignedPreKeyId = Int32(newSignedPreKeyId) + 1
            metadata.scheduleNextSignedPreKeyRefresh()
            metadata.isSignedPreKeyRegistered = true
        } catch {
            Logger.log("ERROR: Failed to rotate signed pre-key: \(error)")
        }
    }

    private func rotateKyberPreKey() {
        Logger.log("Rotating Kyber pre-key...")

        guard let inMemStore = protocolStore else { return }

        do {
            let identityKeyPair = try inMemStore.identityKeyPair(context: context)

            // Determine next kyber pre-key ID
            let kyberPreKeys = store.loadKyberPreKeys()
            let nextId = UInt32((kyberPreKeys.map { $0.id }.max() ?? -1) + 1)
            let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)

            let kyberKeyPair = KEMKeyPair.generate()
            let signature = identityKeyPair.privateKey.generateSignature(
                message: kyberKeyPair.publicKey.serialize()
            )

            let kyberPreKey = try KyberPreKeyRecord(
                id: nextId,
                timestamp: timestamp,
                keyPair: kyberKeyPair,
                signature: signature
            )

            try inMemStore.storeKyberPreKey(kyberPreKey, id: nextId, context: context)

            // Persist to disk
            var updatedKyberPreKeys = kyberPreKeys
            updatedKyberPreKeys.append(SerializableKyberPreKey(
                id: Int32(nextId),
                record: kyberPreKey.serialize(),
                timestamp: Int64(timestamp)
            ))
            try store.saveKyberPreKeys(updatedKyberPreKeys)

            metadata.scheduleNextKyberPreKeyRefresh()
        } catch {
            Logger.log("ERROR: Failed to rotate Kyber pre-key: \(error)")
        }
    }

    // MARK: - Session & Identity Persistence Helpers

    /// Persist session record for a specific address from in-memory store to disk.
    private func persistSessionState(for address: ProtocolAddress) {
        guard let inMemStore = protocolStore else {
            Logger.log("[PERSIST] ERROR: protocolStore is nil, cannot persist session!")
            return
        }
        do {
            if let sessionRecord = try inMemStore.loadSession(for: address, context: context) {
                let addressKey = "\(address.name).\(address.deviceId)"
                var sessions = store.loadSessions()
                let serialized = sessionRecord.serialize()
                sessions[addressKey] = serialized
                try store.saveSessions(sessions)
                Logger.log("[PERSIST] Session saved for \(addressKey): \(serialized.count) bytes (total sessions: \(sessions.count))")
            } else {
                Logger.log("[PERSIST] WARN: No session found in memory for \(address.name).\(address.deviceId)")
            }
        } catch {
            Logger.log("[PERSIST] ERROR: Failed to persist session state: \(error)")
        }
    }

    /// Persist identity for a specific address from in-memory store to disk.
    private func persistIdentityState(for address: ProtocolAddress) {
        guard let inMemStore = protocolStore else {
            Logger.log("[PERSIST] ERROR: protocolStore is nil, cannot persist identity!")
            return
        }
        do {
            if let identity = try inMemStore.identity(for: address, context: context) {
                let addressKey = "\(address.name).\(address.deviceId)"
                var identities = store.loadIdentities()
                identities[addressKey] = identity.serialize()
                try store.saveIdentities(identities)
                Logger.log("[PERSIST] Identity saved for \(addressKey): \(identity.serialize().count) bytes (total identities: \(identities.count))")
            } else {
                Logger.log("[PERSIST] WARN: No identity found in memory for \(address.name).\(address.deviceId)")
            }
        } catch {
            Logger.log("[PERSIST] ERROR: Failed to persist identity state: \(error)")
        }
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
