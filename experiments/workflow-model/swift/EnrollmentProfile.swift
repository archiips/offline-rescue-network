import Foundation
import CryptoKit

/// Public preparation bundle. An organizer fingerprint is checked BEFORE an outage; discovery
/// cannot install an issuer. The signature binds credential, revocation snapshot and trust cutoff.
public struct EnrollmentProfile: Codable, Sendable {
    struct Claims: Codable {
        var domain: String
        var realm: UUID
        var issuer: Data
        var validUntil: Int64
        var credential: Data
        var revoked: [UUID]
        var responders: [Data]?
    }
    public let domain: String
    public let realm: UUID
    public let issuer: Data
    public let validUntil: Int64
    public let credential: Data
    public let revoked: [UUID]
    public let signature: Data
    public let responders: [Data]?
    private var claims: Claims { .init(domain: domain, realm: realm, issuer: issuer, validUntil: validUntil, credential: credential, revoked: revoked, responders: responders) }
    /// Registrar-side only; never provide an issuer secret to the public app.
    public static func issue(realm: UUID, issuer: Curve25519.Signing.PrivateKey, validUntil: Int64,
                             credential: Data, revoked: Set<UUID> = [], responders: [Data] = []) throws -> Self {
        guard revoked.count <= 1024, responders.count <= 4, validUntil > 0 else { throw EnrollmentError.malformed }
        let claims = Claims(domain: "OREP1", realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: validUntil,
                            credential: credential, revoked: revoked.sorted { $0.uuidString < $1.uuidString }, responders: responders.isEmpty ? nil : responders)
        let profile = try Self(domain: claims.domain, realm: realm, issuer: claims.issuer, validUntil: validUntil,
                        credential: credential, revoked: claims.revoked, signature: issuer.signature(for: EnrollmentWire.encode(claims)), responders: claims.responders)
        _ = try profile.encoded()
        return profile
    }
    public var issuerFingerprint: String { SHA256.hash(data: issuer).map { String(format: "%02x", $0) }.joined() }
    public func encoded() throws -> Data { try EnrollmentWire.encode(self) }
    public static func decode(_ bytes: Data) throws -> Self {
        let profile = try EnrollmentWire.decode(Self.self, bytes)
        guard profile.domain == "OREP1", profile.issuer.count == 32, profile.signature.count == 64,
              (profile.responders?.count ?? 0) <= 4, profile.revoked.count <= 1024, Set(profile.revoked).count == profile.revoked.count,
              profile.revoked == profile.revoked.sorted(by: { $0.uuidString < $1.uuidString }) else { throw EnrollmentError.malformed }
        return profile
    }
    public func validate(card: SecurePairingCard, issuerApproved: Bool, at now: Int64) throws -> EnrollmentTrust {
        guard issuerApproved else { throw EnrollmentError.wrongIdentity }
        guard domain == "OREP1", issuer.count == 32, signature.count == 64,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: issuer),
              key.isValidSignature(signature, for: try EnrollmentWire.encode(claims)) else { throw EnrollmentError.invalidSignature }
        let trust = try EnrollmentTrust(realm: realm, issuer: issuer, validUntil: validUntil, revoked: Set(revoked))
        guard try trust.verify(credential, expectedRole: card.role, at: now).card == card else { throw EnrollmentError.wrongIdentity }
        _ = try verifiedResponders(trust: trust, at: now)
        return trust
    }
    /// Call with the policy returned by this profile's approved validate operation.
    public func verifiedResponders(trust: EnrollmentTrust, at now: Int64) throws -> [EnrollmentCredential] {
        guard (responders?.count ?? 0) <= 4 else { throw EnrollmentError.malformed }
        var cards = Set<Data>()
        return try (responders ?? []).map { bytes in
            let credential = try trust.verify(bytes, expectedRole: .responder, at: now)
            guard cards.insert(credential.card.bytes).inserted else { throw EnrollmentError.wrongIdentity }
            return credential
        }
    }
}
