import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@Test func preparedProfileBindsCredentialAndNeverOverridesLocalIssuerApproval() throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID(), identity = SecureIdentity(role: .publicUser)
    let credential = try EnrollmentCredential.issue(card: identity.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let profile = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: 200, credential: credential.bytes)
    let bytes = try profile.encoded()
    let loaded = try EnrollmentProfile.decode(bytes)
    #expect(try loaded.validate(card: identity.card, issuerApproved: true, at: 150).realm == realm)
    #expect(throws: EnrollmentError.self) { try loaded.validate(card: identity.card, issuerApproved: false, at: 150) }
    #expect(throws: EnrollmentError.self) { try loaded.validate(card: SecureIdentity(role: .publicUser).card, issuerApproved: true, at: 150) }
    #expect(throws: EnrollmentError.self) { try loaded.validate(card: identity.card, issuerApproved: true, at: 200) }
}


@Test func preparedProfileSignsRevocationAndExpiryPolicy() throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID(), identity = SecureIdentity(role: .publicUser)
    let credential = try EnrollmentCredential.issue(card: identity.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let revoked = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: 200, credential: credential.bytes, revoked: [credential.serial])
    #expect(throws: EnrollmentError.self) { try revoked.validate(card: identity.card, issuerApproved: true, at: 150) }
    var payload = try JSONSerialization.jsonObject(with: revoked.encoded()) as! [String: Any]
    payload["revoked"] = [String]()
    let forged = try EnrollmentProfile.decode(JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]))
    #expect(throws: EnrollmentError.self) { try forged.validate(card: identity.card, issuerApproved: true, at: 150) }
    let profile = try EnrollmentProfile.issue(realm: realm, issuer: issuer, validUntil: 160, credential: credential.bytes)
    payload = try JSONSerialization.jsonObject(with: profile.encoded()) as! [String: Any]
    payload["validUntil"] = 190
    let extended = try EnrollmentProfile.decode(JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes]))
    #expect(throws: EnrollmentError.self) { try extended.validate(card: identity.card, issuerApproved: true, at: 170) }
}
