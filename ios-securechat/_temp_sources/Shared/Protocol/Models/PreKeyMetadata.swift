import Foundation

/// Metadata for managing pre-key rotation schedules.
/// Equivalent to Android's PreKeyMetadataStore.java / PreKeyMetadataStoreImpl.java
struct PreKeyMetadata: Codable {

    // MARK: - ECC Pre-Key Metadata

    var nextSignedPreKeyId: Int32 = 0
    var activeSignedPreKeyId: Int32 = 0
    var isSignedPreKeyRegistered: Bool = false
    var signedPreKeyFailureCount: Int32 = 0
    var nextOneTimePreKeyId: Int32 = 0
    var nextSignedPreKeyRefreshTime: Int64 = 0
    var oldSignedPreKeyDeletionTime: Int64 = 0

    // MARK: - PQC (Kyber) Pre-Key Metadata

    var nextKyberPreKeyRefreshTime: Int64 = 0
    var oldKyberPreKeyDeletionTime: Int64 = 0

    // MARK: - Constants (matching Android's KeyUtil values)

    /// Pre-key rotation interval: 2 days (in milliseconds)
    static let signedPreKeyMaxDays: Int64 = 2 * 24 * 60 * 60 * 1000
    /// Archive age before deletion: 2 days (in milliseconds)
    static let signedPreKeyArchiveAge: Int64 = 2 * 24 * 60 * 60 * 1000
    /// Number of one-time pre-keys to generate
    static let oneTimePreKeyCount: Int32 = 2

    // MARK: - Rotation Check Helpers

    var needsSignedPreKeyRefresh: Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return now >= nextSignedPreKeyRefreshTime
    }

    var needsOldSignedPreKeyDeletion: Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return now >= oldSignedPreKeyDeletionTime
    }

    var needsKyberPreKeyRefresh: Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return now >= nextKyberPreKeyRefreshTime
    }

    var needsOldKyberPreKeyDeletion: Bool {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return now >= oldKyberPreKeyDeletionTime
    }

    // MARK: - Schedule Helpers

    mutating func scheduleNextSignedPreKeyRefresh() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        nextSignedPreKeyRefreshTime = now + Self.signedPreKeyMaxDays
        oldSignedPreKeyDeletionTime = now + Self.signedPreKeyArchiveAge
    }

    mutating func scheduleNextKyberPreKeyRefresh() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        nextKyberPreKeyRefreshTime = now + Self.signedPreKeyMaxDays
        oldKyberPreKeyDeletionTime = now + Self.signedPreKeyArchiveAge
    }
}
