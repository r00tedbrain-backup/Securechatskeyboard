import Foundation

/// Raw encoder: outputs the MessageEnvelope as a JSON string.
/// Equivalent to Android's RawEncoder.java
struct RawEncoder: MessageEncoder {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [] // compact, no pretty-print
        return e
    }()

    private let decoder = JSONDecoder()

    func encode(_ envelope: MessageEnvelope) throws -> String {
        Logger.log("[RAW_ENC] Encoding envelope: sender=\(envelope.signalProtocolAddressName), hasPKR=\(envelope.preKeyResponse != nil), hasCipher=\(envelope.ciphertextMessage != nil)")
        let data = try encoder.encode(envelope)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodingError.encodingFailed("Failed to convert JSON data to string")
        }
        Logger.log("[RAW_ENC] Encoded JSON length=\(json.count)")
        return json
    }

    func decode(_ text: String) throws -> MessageEnvelope {
        Logger.log("[RAW_DEC] Attempting to decode \(text.count) chars as JSON...")
        guard let data = text.data(using: .utf8) else {
            Logger.log("[RAW_DEC] ERROR: Failed to convert string to UTF-8 data")
            throw EncodingError.decodingFailed("Failed to convert string to data")
        }
        do {
            let envelope = try decoder.decode(MessageEnvelope.self, from: data)
            Logger.log("[RAW_DEC] SUCCESS: sender=\(envelope.signalProtocolAddressName), devId=\(envelope.deviceId), hasPKR=\(envelope.preKeyResponse != nil), hasCipher=\(envelope.ciphertextMessage != nil), cipherType=\(envelope.ciphertextType)")
            return envelope
        } catch {
            Logger.log("[RAW_DEC] FAILED: \(error)")
            throw error
        }
    }
}
