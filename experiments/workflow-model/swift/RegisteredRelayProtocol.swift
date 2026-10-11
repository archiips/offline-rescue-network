import Foundation

/// Credential-bearing routing metadata around the unchanged signed/encrypted ORL1.
/// Credentials are public; issuer trust is provisioned separately and never installed from this frame.
public struct RegisteredRelayPacket: Sendable {
    public static let maximumSize = 4276
    private static let magic = Data("ORRG1".utf8)
    private static let headerSize = 17
    public let bytes: Data
    public let senderCredential: Data
    public let recipientCredential: Data
    public let packet: RelayPacket

    public init(senderCredential: Data, recipientCredential: Data, packet: RelayPacket) throws {
        guard (1...EnrollmentWire.maximumSize).contains(senderCredential.count),
              (1...EnrollmentWire.maximumSize).contains(recipientCredential.count),
              Self.headerSize + senderCredential.count + recipientCredential.count + packet.bytes.count <= Self.maximumSize else {
            throw EnrollmentError.malformed
        }
        var bytes = Self.magic
        for size in [senderCredential.count, recipientCredential.count, packet.bytes.count] {
            let length = UInt32(size)
            bytes.append(contentsOf: [UInt8(length >> 24), UInt8((length >> 16) & 255), UInt8((length >> 8) & 255), UInt8(length & 255)])
        }
        bytes += senderCredential + recipientCredential + packet.bytes
        try self.init(bytes: bytes)
    }
    /// Strict framing and ORL1 policy only. No trust is granted until authenticate succeeds.
    public init(bytes input: Data) throws {
        guard (Self.headerSize...Self.maximumSize).contains(input.count), input.prefix(5) == Self.magic else {
            throw EnrollmentError.malformed
        }
        let bytes = Data(input)
        func size(_ start: Int) -> Int {
            Int(bytes[start..<(start + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
        }
        let senderSize = size(5), recipientSize = size(9), packetSize = size(13)
        guard (1...EnrollmentWire.maximumSize).contains(senderSize), (1...EnrollmentWire.maximumSize).contains(recipientSize),
              (RelayPacket.minimumSize...RelayPacket.maximumSize).contains(packetSize),
              Self.headerSize + senderSize + recipientSize + packetSize == bytes.count else { throw EnrollmentError.malformed }
        let senderEnd = Self.headerSize + senderSize, recipientEnd = senderEnd + recipientSize
        self.bytes = bytes
        senderCredential = Data(bytes[Self.headerSize..<senderEnd])
        recipientCredential = Data(bytes[senderEnd..<recipientEnd])
        packet = try RelayPacket(bytes: Data(bytes[recipientEnd...]))
    }
    /// The issuer authorizes exact cards; ORL1 authenticates both digests, content and sender possession.
    /// Different still-valid credentials for the same card are equivalent authorization, not a new sender.
    public func authenticate(trust: EnrollmentTrust, now: Int64) throws -> (sender: SecurePairingCard, recipient: SecurePairingCard) {
        let sender = try EnrollmentCredential.decode(senderCredential).card
        let recipient = try EnrollmentCredential.decode(recipientCredential).card
        guard sender.role != recipient.role else { throw EnrollmentError.wrongRole }
        guard try trust.verify(senderCredential, expectedRole: sender.role, at: now).card == sender,
              try trust.verify(recipientCredential, expectedRole: recipient.role, at: now).card == recipient else {
            throw EnrollmentError.wrongIdentity
        }
        try packet.verify(from: sender, to: recipient, now: now)
        return (sender, recipient)
    }
}
