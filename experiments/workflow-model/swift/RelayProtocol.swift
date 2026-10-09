import Foundation
import CryptoKit

// Custom signed sample relay formats around ORS1 envelopes. Not BPv7; not an audited protocol. All integers
// are big endian and every format has an exact length with no trailing bytes.

public enum RelayProtocolError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case malformed, policy, wrongSender, wrongRecipient, badSignature, innerMismatch, expired, expiryTooFar
    case wrongPacket, returnInvalid, correlation, cacheMismatch, cacheExpired, plaintextSize, busy, unknownPeer

    public var description: String {
        switch self {
        case .malformed: "Rejected relay packet: malformed"
        case .policy: "Rejected relay packet: kind, priority, hop or correlation outside policy"
        case .wrongSender: "Rejected relay packet from an unpaired sender"
        case .wrongRecipient: "Rejected relay packet addressed elsewhere"
        case .badSignature: "Rejected relay packet: signature check failed"
        case .innerMismatch: "Rejected relay packet: inner envelope pins or signature differ"
        case .expired: "Rejected relay packet: expired"
        case .expiryTooFar: "Rejected relay packet: expiry too far ahead"
        case .wrongPacket: "Rejected acceptance for a different packet or destination"
        case .returnInvalid: "Rejected acceptance: return receipt missing, unexpected or not correlated"
        case .correlation: "Rejected receipt: not correlated with a saved relay event"
        case .cacheMismatch: "Saved relay packet does not match this message; nothing was replaced"
        case .cacheExpired: "Saved relay packet expired; start a new secure session to send again"
        case .plaintextSize: "Message too large for a relay packet"
        case .busy: "A relay flush is already in progress"
        case .unknownPeer: "Relay accepts only the two pinned opposite-role cards"
        }
    }
    public var errorDescription: String? { description }
}

public enum RelayKind: UInt8, Sendable { case event = 0, receipt = 1 }

/// ORL1: magic4, kind1, urgency1, expiry8 (positive Int64), hops1 (=2), sender card SHA256 32, recipient
/// SHA256 32, correlation32 (zero for events; original ORL1 SHA256 for receipts), sealed length2, ORS1
/// sealed 181...3919, Ed25519 signature64 over the domain and every preceding byte.
public struct RelayPacket: Equatable, Sendable {
    public static let overhead = 177
    public static let minimumSize = overhead + SecureEnvelope.minimumPayload
    public static let maximumSize = 4096
    public static let maximumSealed = maximumSize - overhead
    public static let maximumEventPlaintext = maximumSealed - (SecureEnvelope.minimumPayload - 1)
    /// Sample expiry assigned at creation; wall-clock seconds, no trusted-clock claim.
    public static let maximumLifetime: Int64 = 86_400
    /// Accepted expiry horizon, allowing sample devices' clocks to disagree by up to one lifetime.
    static let acceptedHorizon: Int64 = 2 * maximumLifetime
    static let hops: UInt8 = 2
    private static let magic = Data("ORL1".utf8)
    private static let signatureDomain = Data("offline-rescue/ORL1/signature".utf8)

    public let bytes: Data
    public let kind: RelayKind
    public let priority: RelayPriority
    public let expiry: Int64
    let sender: Data
    let recipient: Data
    let correlation: Data
    let sealed: Data
    /// SHA-256 of all bytes; the custody, cache and correlation identity.
    public let digest: Data
    public var id: String { RelayEndpointController.hex(digest) }

    /// Structure and policy only; `verify` checks pins, signatures and time.
    public init(bytes input: Data) throws {
        let bytes = Data(input)
        guard (Self.minimumSize...Self.maximumSize).contains(bytes.count), bytes.prefix(4) == Self.magic else {
            throw RelayProtocolError.malformed
        }
        let length = Int(bytes[111]) << 8 | Int(bytes[112])
        let expiry = bytes[6..<14].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        guard bytes.count == Self.overhead + length, (SecureEnvelope.minimumPayload...Self.maximumSealed).contains(length),
              expiry >= 1, expiry <= UInt64(Int64.max) else { throw RelayProtocolError.malformed }
        let correlation = bytes[79..<111]
        guard let kind = RelayKind(rawValue: bytes[4]), let priority = RelayPriority(rawValue: Int32(bytes[5])), bytes[14] == Self.hops,
              (kind == .event) == correlation.allSatisfy({ $0 == 0 }), kind == .event || priority == .ordinary else {
            throw RelayProtocolError.policy
        }
        self.bytes = bytes
        self.kind = kind
        self.priority = priority
        self.expiry = Int64(expiry)
        sender = bytes[15..<47]
        recipient = bytes[47..<79]
        self.correlation = Data(correlation)
        sealed = bytes[113..<(bytes.count - 64)]
        digest = Data(SHA256.hash(data: bytes))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }

    /// Requires exact sender/recipient pins, both signatures and now < expiry <= now + horizon.
    public func verify(from senderCard: SecurePairingCard, to recipientCard: SecurePairingCard, now: Int64) throws {
        guard sender == senderCard.digest else { throw RelayProtocolError.wrongSender }
        guard recipient == recipientCard.digest else { throw RelayProtocolError.wrongRecipient }
        guard senderCard.signingKey.isValidSignature(bytes.suffix(64), for: Self.signatureDomain + bytes.prefix(bytes.count - 64)) else {
            throw RelayProtocolError.badSignature
        }
        guard SecureEnvelope.isSigned(sealed, sender: senderCard, recipient: recipientCard) else { throw RelayProtocolError.innerMismatch }
        guard expiry > now else { throw RelayProtocolError.expired }
        let (remaining, overflow) = expiry.subtractingReportingOverflow(now)
        guard !overflow, remaining <= Self.acceptedHorizon else { throw RelayProtocolError.expiryTooFar }
    }

    static func make(kind: RelayKind, priority: RelayPriority, expiry: Int64, correlation: Data, sealed: Data,
                     identity: SecureIdentity, recipient: SecurePairingCard) throws -> RelayPacket {
        guard correlation.count == 32, (SecureEnvelope.minimumPayload...maximumSealed).contains(sealed.count) else {
            throw RelayProtocolError.plaintextSize
        }
        return try RelayPacket(bytes: encode(kind: kind.rawValue, urgency: UInt8(priority.rawValue), expiry: expiry, hops: hops,
                                             sender: identity.card.digest, recipient: recipient.digest, correlation: correlation,
                                             sealed: sealed, signer: identity.signingKey))
    }

    /// Raw signed encoding without policy checks; `init(bytes:)` and `verify` decide acceptance.
    static func encode(kind: UInt8, urgency: UInt8, expiry: Int64, hops: UInt8, sender: Data, recipient: Data,
                       correlation: Data, sealed: Data, signer: Curve25519.Signing.PrivateKey) -> Data {
        var bytes = magic + Data([kind, urgency])
        withUnsafeBytes(of: expiry.bigEndian) { bytes.append(contentsOf: $0) }
        bytes.append(hops)
        bytes += sender + recipient + correlation
        bytes += Data([UInt8(truncatingIfNeeded: sealed.count >> 8), UInt8(truncatingIfNeeded: sealed.count)]) + sealed
        // CryptoKit signing fails only for unusable keys, which SecureIdentity cannot hold.
        return bytes + (try! signer.signature(for: signatureDomain + bytes))
    }
}

/// ORA1 destination acceptance: magic4, original ORL1 SHA256 32, destination card SHA256 32, return length2
/// (0 or one ORL1 of 358...4096), return bytes, Ed25519 signature64 by the destination.
public struct RelayAcceptance: Sendable {
    public static let overhead = 134
    public static let maximumSize = overhead + RelayPacket.maximumSize
    private static let magic = Data("ORA1".utf8)
    private static let signatureDomain = Data("offline-rescue/ORA1/signature".utf8)

    public let bytes: Data
    let original: Data
    let destination: Data
    let returned: Data?

    public init(bytes input: Data) throws {
        let bytes = Data(input)
        guard (Self.overhead...Self.maximumSize).contains(bytes.count), bytes.prefix(4) == Self.magic else {
            throw RelayProtocolError.malformed
        }
        let length = Int(bytes[68]) << 8 | Int(bytes[69])
        guard bytes.count == Self.overhead + length,
              length == 0 || (RelayPacket.minimumSize...RelayPacket.maximumSize).contains(length) else { throw RelayProtocolError.malformed }
        self.bytes = bytes
        original = bytes[4..<36]
        destination = bytes[36..<68]
        returned = length == 0 ? nil : Data(bytes[70..<(70 + length)])
    }

    /// Validates this acceptance for exactly `original`; returns the reverse receipt for events, nil for receipts.
    public func verify(original packet: RelayPacket, destination card: SecurePairingCard, origin: SecurePairingCard,
                       now: Int64) throws -> RelayPacket? {
        guard original == packet.digest, destination == card.digest, packet.recipient == card.digest else {
            throw RelayProtocolError.wrongPacket
        }
        guard card.signingKey.isValidSignature(bytes.suffix(64), for: Self.signatureDomain + bytes.prefix(bytes.count - 64)) else {
            throw RelayProtocolError.badSignature
        }
        switch packet.kind {
        case .receipt:
            guard returned == nil else { throw RelayProtocolError.returnInvalid }
            return nil
        case .event:
            guard let returned, let receipt = try? RelayPacket(bytes: returned), receipt.kind == .receipt,
                  receipt.correlation == packet.digest else { throw RelayProtocolError.returnInvalid }
            try receipt.verify(from: card, to: origin, now: now)
            return receipt
        }
    }

    static func make(original: RelayPacket, identity: SecureIdentity, returning: RelayPacket?) throws -> RelayAcceptance {
        try RelayAcceptance(bytes: encode(original: original.digest, destination: identity.card.digest,
                                          returned: returning?.bytes, signer: identity.signingKey))
    }

    static func encode(original: Data, destination: Data, returned: Data?, signer: Curve25519.Signing.PrivateKey) -> Data {
        let body = returned ?? Data()
        var bytes = magic + original + destination
        bytes += Data([UInt8(truncatingIfNeeded: body.count >> 8), UInt8(truncatingIfNeeded: body.count)]) + body
        return bytes + (try! signer.signature(for: signatureDomain + bytes))
    }
}

/// ORC1 upload response: magic4 + ORL1 SHA256 32. Unsigned; claims only local relay admission, never delivery.
public enum RelayCustodyReceipt {
    public static let size = 36
    private static let magic = Data("ORC1".utf8)
    public static func make(_ packet: RelayPacket) -> Data { magic + packet.digest }
    public static func id(from bytes: Data) throws -> String {
        let bytes = Data(bytes)
        guard bytes.count == size, bytes.prefix(4) == magic else { throw RelayProtocolError.malformed }
        return RelayEndpointController.hex(bytes.suffix(32))
    }
}
