import Foundation

/// Base64 encoder: serializes MessageEnvelope to compact JSON, then Base64-encodes it.
/// Equivalent to Android's Base64Encoder.java
struct Base64MessageEncoder: MessageEncoder {

    func encode(_ envelope: MessageEnvelope) throws -> String {
        Logger.log("[B64_ENC] Encoding: sender=\(envelope.signalProtocolAddressName)")
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let data = try encoder.encode(envelope)
        let result = data.base64EncodedString()
        Logger.log("[B64_ENC] Encoded: \(data.count) bytes -> \(result.count) chars base64")
        return result
    }

    func decode(_ text: String) throws -> MessageEnvelope {
        Logger.log("[B64_DEC] Attempting to decode \(text.count) chars as base64...")
        guard let data = Data(base64Encoded: text) else {
            Logger.log("[B64_DEC] ERROR: Invalid Base64 string")
            throw EncodingError.decodingFailed("Invalid Base64 string")
        }
        Logger.log("[B64_DEC] Base64 decoded to \(data.count) bytes")
        do {
            let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: data)
            Logger.log("[B64_DEC] SUCCESS: sender=\(envelope.signalProtocolAddressName)")
            return envelope
        } catch {
            Logger.log("[B64_DEC] ERROR: JSON decode failed: \(error)")
            throw error
        }
    }
}
