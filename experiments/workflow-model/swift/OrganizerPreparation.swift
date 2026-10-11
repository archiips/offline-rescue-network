import Foundation
import CryptoKit

struct OrganizerPreparationHello: Codable { var domain: String; var card: Data; var nonce: Data }
struct OrganizerPreparationChallengeClaims: Codable {
    var domain: String; var realm: UUID; var issuer: Data; var hello: Data; var nonce: Data; var expires: Int64
}
struct OrganizerPreparationChallenge: Codable { var claims: OrganizerPreparationChallengeClaims; var signature: Data }
struct OrganizerPreparationProofClaims: Codable {
    var domain: String; var realm: UUID; var issuer: Data; var card: Data; var hello: Data; var challenge: Data
}
struct OrganizerPreparationProof: Codable { var claims: OrganizerPreparationProofClaims; var signature: Data }
struct OrganizerPreparationResultClaims: Codable { var domain: String; var proof: Data; var profile: EnrollmentProfile }
struct OrganizerPreparationResult: Codable { var claims: OrganizerPreparationResultClaims; var signature: Data }
private func preparationDigest(_ bytes: Data) -> Data { Data(SHA256.hash(data: bytes)) }
private func preparationNonce() -> Data {
    var generator = SystemRandomNumberGenerator()
    return Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
}

/// Synthetic advance-preparation only. Starting this object explicitly opens public issuance;
/// responder authority is granted exclusively by the organizer's complete-card allowlist.
@MainActor public final class OrganizerPreparationService {
    private struct Session {
        let hello: Data; let challenge: Data; let card: SecurePairingCard; let began: Double
        var proof: Data?; var response: Data?
    }
    private let issuer: Curve25519.Signing.PrivateKey
    private let realm: UUID
    private let revoked: Set<UUID>
    private let authorized: Set<Data>
    private let responderCards: [Data]
    private let now: () -> Int64
    private let elapsed: () -> Double
    private var sessions: [Data: Session] = [:]
    private var active = true
    public init(issuer: Curve25519.Signing.PrivateKey, realm: UUID, revoked: Set<UUID> = [],
                authorizedResponderCards: Set<Data> = [], now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) },
                elapsed: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.issuer = issuer; self.realm = realm; self.revoked = revoked
        responderCards = authorizedResponderCards.sorted { $0.lexicographicallyPrecedes($1) }
        authorized = Set(authorizedResponderCards.map(preparationDigest)); self.now = now; self.elapsed = elapsed
    }
    public func stop() { active = false; sessions.removeAll() }
    private func fresh(_ session: Session) -> Bool {
        let time = elapsed()
        return time.isFinite && session.began.isFinite && time >= session.began && time - session.began < 10
    }
    public func challenge(_ input: Data) throws -> Data {
        guard active else { throw EnrollmentError.stopped }
        guard responderCards.count <= 4 else { throw EnrollmentError.malformed }
        for bytes in responderCards {
            guard let card = try? SecurePairingCard(bytes: bytes), card.role == .responder else { throw EnrollmentError.malformed }
        }
        let hello = try EnrollmentWire.decode(OrganizerPreparationHello.self, input)
        guard hello.domain == "OREQ1", hello.nonce.count == 32 else { throw EnrollmentError.malformed }
        let card = try SecurePairingCard(bytes: hello.card)
        guard card.role == .publicUser || authorized.contains(card.digest) else { throw EnrollmentError.wrongRole }
        sessions = sessions.filter { fresh($0.value) }
        guard sessions.count < 64 else { throw EnrollmentError.busy }
        let wall = now(), began = elapsed()
        guard wall >= 0, wall <= Int64.max - 86400, began.isFinite else { throw EnrollmentError.expired }
        let claims = OrganizerPreparationChallengeClaims(domain: "ORQC1", realm: realm,
            issuer: issuer.publicKey.rawRepresentation, hello: preparationDigest(input), nonce: preparationNonce(), expires: wall + 10)
        let bytes = try EnrollmentWire.encode(OrganizerPreparationChallenge(claims: claims,
            signature: issuer.signature(for: EnrollmentWire.encode(claims))))
        sessions[preparationDigest(bytes)] = Session(hello: input, challenge: bytes, card: card, began: began)
        return bytes
    }
    public func issue(_ input: Data) throws -> Data {
        guard active else { throw EnrollmentError.stopped }
        let proof = try EnrollmentWire.decode(OrganizerPreparationProof.self, input), claims = proof.claims
        guard claims.domain == "ORQP1", proof.signature.count == 64,
              claims.challenge.count == 32, claims.hello.count == 32, claims.issuer.count == 32,
              var session = sessions[claims.challenge], fresh(session),
              claims.realm == realm, claims.issuer == preparationDigest(issuer.publicKey.rawRepresentation),
              claims.hello == preparationDigest(session.hello), claims.card == session.card.bytes,
              session.card.signingKey.isValidSignature(proof.signature, for: try EnrollmentWire.encode(claims)) else { throw EnrollmentError.wrongTranscript }
        let challenge = try EnrollmentWire.decode(OrganizerPreparationChallenge.self, session.challenge)
        let wall = now()
        guard wall >= 0, wall < challenge.claims.expires, wall <= Int64.max - 86400 else { throw EnrollmentError.expired }
        if let previous = session.proof {
            guard previous == input, let response = session.response else { throw EnrollmentError.wrongTranscript }
            return response
        }
        let credential = try EnrollmentCredential.issue(card: session.card, realm: realm,
            notBefore: max(0, wall - 300), expires: wall + 86400, issuer: issuer)
        let directory: [Data]
        if session.card.role == .publicUser {
            directory = try responderCards.map { bytes in
                try EnrollmentCredential.issue(card: SecurePairingCard(bytes: bytes), realm: realm,
                    notBefore: max(0, wall - 300), expires: wall + 86400, issuer: issuer).bytes
            }
        } else { directory = [] }
        let profile = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: wall + 86400,
            credential: credential.bytes, revoked: revoked, responders: directory)
        let result = OrganizerPreparationResultClaims(domain: "ORQR1", proof: preparationDigest(input), profile: profile)
        let response = try EnrollmentWire.encode(OrganizerPreparationResult(claims: result,
            signature: issuer.signature(for: EnrollmentWire.encode(result))))
        session.proof = input; session.response = response; sessions[claims.challenge] = session
        return response
    }
}

/// Returns validated public profile bytes only. It never grants or persists issuer trust.
@MainActor public final class OrganizerPreparationClient {
    private let identity: SecureIdentity
    private let now: () -> Int64
    private let elapsed: () -> Double
    private var began: Double?
    private var request: Data?
    private var challenge: OrganizerPreparationChallenge?
    private var proof: Data?
    private var active = true
    public var card: SecurePairingCard { identity.card }
    public init(identity: SecureIdentity, now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) },
                elapsed: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.identity = identity; self.now = now; self.elapsed = elapsed
    }
    private var fresh: Bool {
        guard let began else { return false }
        let time = elapsed()
        return began.isFinite && time.isFinite && time >= began && time - began < 10
    }
    public func stop() { active = false; request = nil; challenge = nil; proof = nil; began = nil }
    public func hello() throws -> Data {
        guard active else { throw EnrollmentError.stopped }
        let bytes = try EnrollmentWire.encode(OrganizerPreparationHello(domain: "OREQ1", card: card.bytes, nonce: preparationNonce()))
        request = bytes; challenge = nil; proof = nil; began = elapsed(); return bytes
    }
    public func prove(_ input: Data) throws -> Data {
        guard active, fresh, let request else { throw EnrollmentError.stopped }
        let challenge = try EnrollmentWire.decode(OrganizerPreparationChallenge.self, input), claims = challenge.claims
        let wall = now()
        guard claims.domain == "ORQC1", claims.issuer.count == 32, claims.nonce.count == 32,
              claims.hello == preparationDigest(request), challenge.signature.count == 64,
              wall >= 0, claims.expires > wall, claims.expires - wall <= 10,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: claims.issuer),
              key.isValidSignature(challenge.signature, for: try EnrollmentWire.encode(claims)) else { throw EnrollmentError.wrongTranscript }
        let proofClaims = OrganizerPreparationProofClaims(domain: "ORQP1", realm: claims.realm,
            issuer: preparationDigest(claims.issuer), card: card.bytes, hello: preparationDigest(request), challenge: preparationDigest(input))
        let bytes = try EnrollmentWire.encode(OrganizerPreparationProof(claims: proofClaims,
            signature: identity.signingKey.signature(for: EnrollmentWire.encode(proofClaims))))
        self.challenge = challenge; proof = bytes; return bytes
    }
    public func profile(_ input: Data) throws -> Data {
        guard active, fresh, let challenge, let proof else { throw EnrollmentError.stopped }
        let result = try EnrollmentWire.decode(OrganizerPreparationResult.self, input)
        guard result.claims.domain == "ORQR1", result.claims.proof == preparationDigest(proof),
              result.signature.count == 64, now() < challenge.claims.expires,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: challenge.claims.issuer),
              key.isValidSignature(result.signature, for: try EnrollmentWire.encode(result.claims)) else { throw EnrollmentError.wrongTranscript }
        let bytes = try result.claims.profile.encoded()
        let profile = try EnrollmentProfile.decode(bytes)
        guard profile.realm == challenge.claims.realm, profile.issuer == challenge.claims.issuer else { throw EnrollmentError.wrongIdentity }
        _ = try profile.validate(card: card, issuerApproved: true, at: now())
        return bytes
    }
}
