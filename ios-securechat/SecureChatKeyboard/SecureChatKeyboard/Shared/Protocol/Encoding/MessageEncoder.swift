import Foundation

/// Protocol for message encoding strategies.
/// Equivalent to Android's Encoder interface.
protocol MessageEncoder {
    /// Encode a MessageEnvelope to a string for transmission.
    func encode(_ envelope: MessageEnvelope) throws -> String

    /// Decode a string back to a MessageEnvelope.
    func decode(_ text: String) throws -> MessageEnvelope
}

/// The active encoding mode.
enum EncodingMode: String, Codable, CaseIterable {
    case raw = "Raw"
    case fairyTale = "Fairy Tale"
    case base64 = "Base64"

    var encoder: MessageEncoder {
        switch self {
        case .raw: return RawEncoder()
        case .fairyTale: return FairyTaleEncoder()
        case .base64: return Base64MessageEncoder()
        }
    }
}

enum EncodingError: LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let msg): return "Encoding failed: \(msg)"
        case .decodingFailed(let msg): return "Decoding failed: \(msg)"
        }
    }
}
