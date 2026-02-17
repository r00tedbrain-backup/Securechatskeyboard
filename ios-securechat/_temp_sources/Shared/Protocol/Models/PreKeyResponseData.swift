import Foundation

/// The PreKeyResponse data model for serialization.
/// Contains ECC identity key, device pre-keys, and optional Kyber PQC keys.
/// Equivalent to Android's PreKeyResponse.java
struct PreKeyResponseData: Codable, Equatable {
    /// Base64-encoded identity key
    var identityKey: Data

    /// List of device pre-key items
    var devices: [PreKeyResponseItemData]

    // PQC (Kyber) fields
    var kyberPubKey: Data?
    var kyberPreKeyId: Int32?
    var kyberSignature: Data?

    init(identityKey: Data, devices: [PreKeyResponseItemData]) {
        self.identityKey = identityKey
        self.devices = devices
    }
}

/// A single device's pre-key data within a PreKeyResponse.
/// Equivalent to Android's PreKeyResponseItem.java
struct PreKeyResponseItemData: Codable, Equatable {
    var deviceId: Int32
    var registrationId: Int32
    var signedPreKey: SignedPreKeyData
    var preKey: PreKeyData
}

/// Signed pre-key data for serialization.
/// Equivalent to Android's SignedPreKeyEntity.java
struct SignedPreKeyData: Codable, Equatable {
    var keyId: Int32
    var publicKey: Data  // serialized ECPublicKey
    var signature: Data
}

/// One-time pre-key data for serialization.
/// Equivalent to Android's PreKeyEntity.java
struct PreKeyData: Codable, Equatable {
    var keyId: Int32
    var publicKey: Data  // serialized ECPublicKey
}
