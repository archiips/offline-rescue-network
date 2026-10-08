import Foundation
import CryptoKit

// Bounded Apple-only secure adapter: RFC 9180 base-mode HPKE (X25519/SHA256/ChaChaPoly) plus a distinct
// Ed25519 sender signature. Synthetic sample exchange only; not an audited protocol or identity proof.

public enum SecureExchangeError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case invalidCard, wrongRole, ownCard, peerAlreadyPinned, notPaired
    case payloadSize, packetSize, notEnvelope, wrongSender, wrongRecipient, reflected, badSignature, unreadable
    case historyMissing, recordMissing, recordInvalid, recordStore(Int32), staleSession, storageLocation

    public var description: String {
        switch self {
        case .invalidCard: "Rejected malformed pairing card"
        case .wrongRole: "Pairing card must be the opposite sample role"
        case .ownCard: "Rejected this endpoint's own pairing card"
        case .peerAlreadyPinned: "A different peer is already paired; start a new secure session first"
        case .notPaired: "Pair with the opposite endpoint first"
        case .payloadSize: "Message size outside secure limits"
        case .packetSize: "Rejected secure packet: size outside limits"
        case .notEnvelope: "Rejected packet: not a secure envelope"
        case .wrongSender: "Rejected packet from an unpaired sender or old session"
        case .wrongRecipient: "Rejected packet addressed to another endpoint or old session"
        case .reflected: "Rejected this endpoint's own packet"
        case .badSignature: "Rejected packet: signature check failed"
        case .unreadable: "Rejected packet: decryption failed"
        case .historyMissing: "Paired secure history missing; start a new session and re-pair both endpoints"
        case .recordMissing: "Secure keys missing while saved secure sessions exist; nothing was replaced"
        case .recordInvalid: "Saved secure key record unreadable; nothing was replaced"
        case .recordStore(let status): "Secure key storage failed (\(status)); nothing was replaced"
        case .staleSession: "Secure session changed elsewhere; select the role again or restart this endpoint"
        case .storageLocation: "Secure storage must be a local folder"
        }
    }
    public var errorDescription: String? { description }
}

/// Public ORP1 card: magic4, role1, epoch UUID16, Ed25519 public32, X25519 public32.
/// Importing one asserts attended sample authority only, not a verified identity.
public struct SecurePairingCard: Equatable, Hashable, Sendable {
    public static let size = 85
    static let magic = Data("ORP1".utf8)
    private static let base64Size = 116

    public let bytes: Data
    public let role: EndpointRole
    let epoch: UUID
    let signingKey: Curve25519.Signing.PublicKey
    let agreementKey: Curve25519.KeyAgreement.PublicKey
    /// SHA-256 over all 85 bytes, as packets pin it.
    let digest: Data

    public var base64: String { bytes.base64EncodedString() }
    /// Full lowercase hex SHA-256; compare all of it on the other device before pairing.
    public var fingerprint: String { digest.map { String(format: "%02x", $0) }.joined() }

    /// Strict canonical standard base64 only: no whitespace, URL alphabet, or alternate padding bits.
    public init(base64: String) throws {
        guard base64.utf8.count == Self.base64Size, let bytes = Data(base64Encoded: base64),
              bytes.base64EncodedString() == base64 else { throw SecureExchangeError.invalidCard }
        try self.init(bytes: bytes)
    }

    public init(bytes input: Data) throws {
        let bytes = Data(input)
        guard bytes.count == Self.size, bytes.prefix(4) == Self.magic,
              let role = EndpointRole(rawValue: Int(bytes[4])) else { throw SecureExchangeError.invalidCard }
        let signing = bytes[21..<53], agreement = bytes[53..<85]
        let zero = Data(count: 32)
        guard signing != agreement, signing != zero, agreement != zero,
              let signingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: signing),
              let agreementKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: agreement),
              Self.contributes(agreementKey) else { throw SecureExchangeError.invalidCard }
        self.bytes = bytes
        self.role = role
        epoch = bytes[5..<21].withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        self.signingKey = signingKey
        self.agreementKey = agreementKey
        digest = Data(SHA256.hash(data: bytes))
    }

    /// Rejects low-order X25519 points, whose shared secret is all zero for every private key.
    private static func contributes(_ key: Curve25519.KeyAgreement.PublicKey) -> Bool {
        guard let secret = try? Curve25519.KeyAgreement.PrivateKey().sharedSecretFromKeyAgreement(with: key) else { return false }
        return secret.withUnsafeBytes { raw in raw.contains { $0 != 0 } }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.bytes == rhs.bytes }
    public func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}

/// One role's private signing and encryption keys plus session epoch. Never exported as a card.
public struct SecureIdentity: Sendable {
    public let role: EndpointRole
    let epoch: UUID
    let signingKey: Curve25519.Signing.PrivateKey
    let agreementKey: Curve25519.KeyAgreement.PrivateKey
    public let card: SecurePairingCard

    /// Fresh random keys and epoch.
    public init(role: EndpointRole) {
        var signing = Curve25519.Signing.PrivateKey()
        var agreement = Curve25519.KeyAgreement.PrivateKey()
        // Keep the two public keys distinct so cards always parse; collision is practically impossible.
        while signing.publicKey.rawRepresentation == agreement.publicKey.rawRepresentation {
            signing = .init(); agreement = .init()
        }
        // Valid by construction; fresh keys always satisfy the card checks.
        try! self.init(role: role, epoch: UUID(), signingKey: signing, agreementKey: agreement)
    }

    init(role: EndpointRole, epoch: UUID, signingKey: Curve25519.Signing.PrivateKey,
         agreementKey: Curve25519.KeyAgreement.PrivateKey) throws {
        self.role = role
        self.epoch = epoch
        self.signingKey = signingKey
        self.agreementKey = agreementKey
        var bytes = SecurePairingCard.magic
        bytes.append(UInt8(role.rawValue))
        withUnsafeBytes(of: epoch.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(signingKey.publicKey.rawRepresentation)
        bytes.append(agreementKey.publicKey.rawRepresentation)
        card = try SecurePairingCard(bytes: bytes)
    }
}

/// ORS1: magic4 + sender card SHA256 32 + recipient card SHA256 32 + HPKE encapsulated key32
/// + ChaChaPoly ciphertext (1...4096 plus 16-byte tag) + Ed25519 signature64.
/// Fresh HPKE context per packet; header, sizes, pins and signature are checked before decrypting.
public struct SecureEnvelope: Sendable {
    public static let maximumPlaintext = 4096
    public static let headerSize = 100
    public static let minimumPayload = headerSize + 1 + 16 + 64
    /// Largest sealed packet: 4276 bytes.
    public static let maximumPayload = headerSize + maximumPlaintext + 16 + 64

    private static let magic = Data("ORS1".utf8)
    private static let infoDomain = Data("offline-rescue/ORS1/HPKE/base/X25519-SHA256-ChaChaPoly".utf8)
    private static let signatureDomain = Data("offline-rescue/ORS1/signature".utf8)
    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    private let identity: SecureIdentity
    private let peer: SecurePairingCard

    /// Requires the opposite role and a card other than this identity's own.
    public init(identity: SecureIdentity, peer: SecurePairingCard) throws {
        guard peer != identity.card else { throw SecureExchangeError.ownCard }
        guard peer.role != identity.role else { throw SecureExchangeError.wrongRole }
        self.identity = identity
        self.peer = peer
    }

    public func seal(_ plaintext: Data) throws -> Data {
        guard (1...Self.maximumPlaintext).contains(plaintext.count) else { throw SecureExchangeError.payloadSize }
        let pins = Self.magic + identity.card.digest + peer.digest
        var sender = try HPKE.Sender(recipientKey: peer.agreementKey, ciphersuite: Self.suite, info: Self.infoDomain + pins)
        let header = pins + sender.encapsulatedKey
        guard header.count == Self.headerSize else { throw SecureExchangeError.notEnvelope }
        let ciphertext = try sender.seal(plaintext, authenticating: header)
        let signature = try identity.signingKey.signature(for: Self.signatureDomain + header + ciphertext)
        return header + ciphertext + signature
    }

    public func open(_ input: Data) throws -> Data {
        guard (Self.minimumPayload...Self.maximumPayload).contains(input.count) else { throw SecureExchangeError.packetSize }
        let packet = Data(input)
        guard packet.prefix(4) == Self.magic else { throw SecureExchangeError.notEnvelope }
        let sender = packet[4..<36], recipient = packet[36..<68]
        if sender == identity.card.digest { throw SecureExchangeError.reflected }
        guard sender == peer.digest else { throw SecureExchangeError.wrongSender }
        guard recipient == identity.card.digest else { throw SecureExchangeError.wrongRecipient }
        let header = packet.prefix(Self.headerSize)
        let ciphertext = packet[Self.headerSize..<(packet.count - 64)]
        let signature = packet.suffix(64)
        guard peer.signingKey.isValidSignature(signature, for: Self.signatureDomain + header + ciphertext) else {
            throw SecureExchangeError.badSignature
        }
        do {
            var receiver = try HPKE.Recipient(privateKey: identity.agreementKey, ciphersuite: Self.suite,
                                              info: Self.infoDomain + packet.prefix(68), encapsulatedKey: packet[68..<100])
            return try receiver.open(ciphertext, authenticating: header)
        } catch { throw SecureExchangeError.unreadable }
    }
}
