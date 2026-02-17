import Foundation

/// A stored plaintext message record, used for local chat history.
/// Equivalent to Android's StorageMessage.java
struct StorageMessage: Codable, Equatable, Identifiable {
    var id: String { "\(contactUUID)-\(timestamp.timeIntervalSince1970)" }

    let contactUUID: String   // contact address name (UUID)
    let senderUUID: String
    let recipientUUID: String
    let timestamp: Date
    let unencryptedMessage: String

    init(contactUUID: String,
         senderUUID: String,
         recipientUUID: String,
         timestamp: Date = Date(),
         unencryptedMessage: String) {
        self.contactUUID = contactUUID
        self.senderUUID = senderUUID
        self.recipientUUID = recipientUUID
        self.timestamp = timestamp
        self.unencryptedMessage = unencryptedMessage
    }
}
