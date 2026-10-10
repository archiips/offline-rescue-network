import Foundation

/// A validated preparation summary, not evidence of a reachable responder or delivery.
public struct EnrollmentReadiness: Sendable {
    public let role: EndpointRole
    public let realm: UUID
    public let validUntil: Int64
    public let issuerFingerprint: String

    public init(profile: EnrollmentProfile, card: SecurePairingCard, issuerApproved: Bool, at now: Int64) throws {
        let trust = try profile.validate(card: card, issuerApproved: issuerApproved, at: now)
        let credential = try trust.verify(profile.credential, expectedRole: card.role, at: now)
        role = card.role
        realm = profile.realm
        validUntil = min(profile.validUntil, credential.expires)
        issuerFingerprint = profile.issuerFingerprint
    }
}
