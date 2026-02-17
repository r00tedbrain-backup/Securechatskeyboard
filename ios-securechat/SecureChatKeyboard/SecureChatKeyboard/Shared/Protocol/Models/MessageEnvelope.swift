import Foundation

/// The envelope that wraps all encrypted message data for transmission.
/// Serialized as a JSON array for compact representation.
/// Equivalent to Android's MessageEnvelope.java
struct MessageEnvelope: Codable, Equatable {
    var preKeyResponse: PreKeyResponseData?
    var ciphertextMessage: Data?
    var ciphertextType: Int32
    var timestamp: Int64
    var signalProtocolAddressName: String
    var deviceId: Int32

    init(ciphertextMessage: Data,
         ciphertextType: Int32,
         signalProtocolAddressName: String,
         deviceId: Int32) {
        self.preKeyResponse = nil
        self.ciphertextMessage = ciphertextMessage
        self.ciphertextType = ciphertextType
        self.signalProtocolAddressName = signalProtocolAddressName
        self.deviceId = deviceId
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }

    init(preKeyResponse: PreKeyResponseData,
         signalProtocolAddressName: String,
         deviceId: Int32) {
        self.preKeyResponse = preKeyResponse
        self.ciphertextMessage = nil
        self.ciphertextType = 0
        self.signalProtocolAddressName = signalProtocolAddressName
        self.deviceId = deviceId
        self.timestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }

    var timestampAsDate: Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
    }
}
