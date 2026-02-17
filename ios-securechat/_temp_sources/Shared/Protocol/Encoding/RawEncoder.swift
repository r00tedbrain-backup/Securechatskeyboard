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
        let data = try encoder.encode(envelope)
        guard let json = String(data: data, encoding: .utf8) else {
            throw EncodingError.encodingFailed("Failed to convert JSON data to string")
        }
        return json
    }

    func decode(_ text: String) throws -> MessageEnvelope {
        guard let data = text.data(using: .utf8) else {
            throw EncodingError.decodingFailed("Failed to convert string to data")
        }
        return try decoder.decode(MessageEnvelope.self, from: data)
    }
}
