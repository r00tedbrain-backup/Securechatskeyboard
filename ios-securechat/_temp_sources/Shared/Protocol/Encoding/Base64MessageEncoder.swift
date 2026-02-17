import Foundation

/// Base64 encoder: serializes MessageEnvelope to compact JSON, then Base64-encodes it.
/// Equivalent to Android's Base64Encoder.java
struct Base64MessageEncoder: MessageEncoder {

    func encode(_ envelope: MessageEnvelope) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(envelope)
        return data.base64EncodedString()
    }

    func decode(_ text: String) throws -> MessageEnvelope {
        guard let data = Data(base64Encoded: text) else {
            throw EncodingError.decodingFailed("Invalid Base64 string")
        }
        return try JSONDecoder().decode(MessageEnvelope.self, from: data)
    }
}
