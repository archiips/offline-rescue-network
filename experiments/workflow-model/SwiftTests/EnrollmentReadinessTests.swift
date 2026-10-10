import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@Test func readinessUsesEarlierCredentialOrPolicyCutoffAndRequiresApproval() throws {
    let identity = SecureIdentity(role: .publicUser)
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let credential = try EnrollmentCredential.issue(card: identity.card, realm: realm, notBefore: 100, expires: 250, issuer: issuer)
    let shortPolicy = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: 200, credential: credential.bytes)
    let longPolicy = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: 300, credential: credential.bytes)
    let summary = try EnrollmentReadiness(profile: shortPolicy, card: identity.card, issuerApproved: true, at: 150)
    #expect(summary.validUntil == 200)
    #expect(summary.role == .publicUser && summary.realm == realm)
    #expect(summary.issuerFingerprint == shortPolicy.issuerFingerprint)
    #expect(try EnrollmentReadiness(profile: longPolicy, card: identity.card, issuerApproved: true, at: 150).validUntil == 250)
    #expect(throws: EnrollmentError.wrongIdentity) {
        try EnrollmentReadiness(profile: shortPolicy, card: identity.card, issuerApproved: false, at: 150)
    }
    #expect(throws: EnrollmentError.expired) {
        try EnrollmentReadiness(profile: shortPolicy, card: identity.card, issuerApproved: true, at: 200)
    }
    #expect(throws: EnrollmentError.expired) {
        try EnrollmentReadiness(profile: longPolicy, card: identity.card, issuerApproved: true, at: 250)
    }
}

@Test func readinessRejectsRevokedOrDifferentDeviceWithoutTrustingSummaryFields() throws {
    let identity = SecureIdentity(role: .responder), other = SecureIdentity(role: .responder)
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let credential = try EnrollmentCredential.issue(card: identity.card, realm: realm, notBefore: 100, expires: 250, issuer: issuer)
    let revoked = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: 200, credential: credential.bytes, revoked: [credential.serial])
    #expect(throws: EnrollmentError.revoked) {
        try EnrollmentReadiness(profile: revoked, card: identity.card, issuerApproved: true, at: 150)
    }
    let valid = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: 200, credential: credential.bytes)
    #expect(throws: EnrollmentError.wrongIdentity) {
        try EnrollmentReadiness(profile: valid, card: other.card, issuerApproved: true, at: 150)
    }
}
