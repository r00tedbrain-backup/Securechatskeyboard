import Foundation

/// The type of encrypted message detected from a MessageEnvelope.
/// Equivalent to Android's MessageType.java
enum MessageType {
    /// A PreKeyResponse only (invite message with key bundle)
    case preKeyResponseMessage

    /// A regular Signal encrypted message (PREKEY_TYPE or WHISPER_TYPE)
    case signalMessage

    /// A Signal message bundled with an updated PreKeyResponse (key rotation)
    case updatedPreKeyResponseAndSignalMessage

    /// Determine message type from a MessageEnvelope
    static func from(_ envelope: MessageEnvelope) -> MessageType? {
        let hasPreKey = envelope.preKeyResponse != nil
        let hasCiphertext = envelope.ciphertextMessage != nil

        if hasPreKey && hasCiphertext {
            return .updatedPreKeyResponseAndSignalMessage
        } else if hasPreKey {
            return .preKeyResponseMessage
        } else if hasCiphertext {
            return .signalMessage
        }
        return nil
    }
}
