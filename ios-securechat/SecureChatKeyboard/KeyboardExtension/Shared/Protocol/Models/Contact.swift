import Foundation

/// Represents a contact in the encrypted messaging system.
/// Equivalent to Android's Contact.java
struct Contact: Codable, Identifiable, Equatable, Hashable {
    let id: String // signalProtocolAddressName (UUID string)
    var firstName: String
    var lastName: String
    var deviceId: Int32
    var signalProtocolAddressName: String
    var verified: Bool

    init(firstName: String,
         lastName: String,
         signalProtocolAddressName: String,
         deviceId: Int32,
         verified: Bool = false) {
        self.id = signalProtocolAddressName
        self.firstName = firstName
        self.lastName = lastName
        self.signalProtocolAddressName = signalProtocolAddressName
        self.deviceId = deviceId
        self.verified = verified
    }

    var displayName: String {
        if lastName.isEmpty {
            return firstName
        }
        return "\(firstName) \(lastName)"
    }

    static func == (lhs: Contact, rhs: Contact) -> Bool {
        return lhs.signalProtocolAddressName == rhs.signalProtocolAddressName
            && lhs.deviceId == rhs.deviceId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(signalProtocolAddressName)
        hasher.combine(deviceId)
    }
}
