import Foundation
import CryptoKit

/// Experimental drill authorization. Trust anchors are prepared outside discovery; no agency claim.
public enum EnrollmentError: Error, Equatable, Sendable {
    case malformed, invalidSignature, wrongRealm, wrongRole, expired, revoked, wrongIdentity
    case wrongTranscript, stopped, busy, alreadyPaired
}

enum EnrollmentWire {
    static let maximumSize = 4096
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let bytes = try? encoder.encode(value), (1...maximumSize).contains(bytes.count) else { throw EnrollmentError.malformed }
        return bytes
    }
    static func decode<T: Codable>(_ type: T.Type, _ input: Data) throws -> T {
        guard (1...maximumSize).contains(input.count),
              let value = try? JSONDecoder().decode(type, from: input),
              try encode(value) == input else { throw EnrollmentError.malformed }
        return value
    }
}

public struct EnrollmentCredential: Sendable {
    struct Claims: Codable {
        var domain: String
        var realm: UUID
        var serial: UUID
        var notBefore: Int64
        var expires: Int64
        var card: Data
    }
    struct Signed: Codable {
        var domain: String
        var realm: UUID
        var serial: UUID
        var notBefore: Int64
        var expires: Int64
        var card: Data
        var signature: Data
        var claims: Claims { .init(domain: domain, realm: realm, serial: serial, notBefore: notBefore, expires: expires, card: card) }
    }
    public let bytes: Data
    public let card: SecurePairingCard
    public let serial: UUID
    public let expires: Int64
    let signed: Signed
    private init(_ signed: Signed) throws {
        guard signed.domain == "OREC1", signed.notBefore >= 0,
              signed.expires > signed.notBefore, signed.expires - signed.notBefore <= 604800,
              signed.signature.count == 64 else { throw EnrollmentError.malformed }
        card = try SecurePairingCard(bytes: signed.card)
        bytes = try EnrollmentWire.encode(signed)
        serial = signed.serial; expires = signed.expires; self.signed = signed
    }
    /// Registrar-side only. The public app must never contain an issuer private key.
    public static func issue(card: SecurePairingCard, realm: UUID, notBefore: Int64, expires: Int64,
                             issuer: Curve25519.Signing.PrivateKey) throws -> Self {
        let claims = Claims(domain: "OREC1", realm: realm, serial: UUID(), notBefore: notBefore, expires: expires, card: card.bytes)
        let signature = try issuer.signature(for: EnrollmentWire.encode(claims))
        return try Self(.init(domain: claims.domain, realm: realm, serial: claims.serial, notBefore: notBefore, expires: expires, card: card.bytes, signature: signature))
    }
    static func decode(_ bytes: Data) throws -> Self {
        try Self(EnrollmentWire.decode(Signed.self, bytes))
    }
}

/// Locally provisioned policy, never accepted from a discovered peer. Revocation is only as current
/// as the prepared policy; wall-clock correctness is an explicit experimental assumption.
public struct EnrollmentTrust: Sendable {
    public let realm: UUID
    public let validUntil: Int64
    private let issuer: Curve25519.Signing.PublicKey
    private let revoked: Set<UUID>
    public init(realm: UUID, issuer: Data, validUntil: Int64, revoked: Set<UUID> = []) throws {
        guard issuer.count == 32, validUntil > 0, revoked.count <= 1024,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: issuer) else { throw EnrollmentError.malformed }
        self.realm = realm; self.issuer = key; self.validUntil = validUntil; self.revoked = revoked
    }
    public func verify(_ bytes: Data, expectedRole: EndpointRole, at now: Int64) throws -> EnrollmentCredential {
        let credential: EnrollmentCredential
        do { credential = try .decode(bytes) } catch { throw EnrollmentError.malformed }
        guard issuer.isValidSignature(credential.signed.signature, for: try EnrollmentWire.encode(credential.signed.claims)) else { throw EnrollmentError.invalidSignature }
        guard credential.signed.realm == realm else { throw EnrollmentError.wrongRealm }
        guard credential.card.role == expectedRole else { throw EnrollmentError.wrongRole }
        guard now >= 0, now < validUntil, now >= credential.signed.notBefore, now < credential.expires else { throw EnrollmentError.expired }
        guard !revoked.contains(credential.serial) else { throw EnrollmentError.revoked }
        return credential
    }
}
