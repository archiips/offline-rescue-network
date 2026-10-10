import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@Test func enrollmentCredentialBindsIssuerRealmRoleAndCard() throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let person = SecureIdentity(role: .publicUser)
    let credential = try EnrollmentCredential.issue(card: person.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let trust = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300)
    #expect(try trust.verify(credential.bytes, expectedRole: .publicUser, at: 100).card == person.card)
    #expect(throws: EnrollmentError.self) { try trust.verify(credential.bytes, expectedRole: .responder, at: 150) }
    #expect(throws: EnrollmentError.self) { try trust.verify(credential.bytes, expectedRole: .publicUser, at: 99) }
    #expect(throws: EnrollmentError.self) { try trust.verify(credential.bytes, expectedRole: .publicUser, at: 200) }
    let other = try EnrollmentTrust(realm: UUID(), issuer: issuer.publicKey.rawRepresentation, validUntil: 300)
    #expect(throws: EnrollmentError.self) { try other.verify(credential.bytes, expectedRole: .publicUser, at: 150) }
    let forged = try EnrollmentCredential.issue(card: person.card, realm: realm, notBefore: 100, expires: 200, issuer: .init())
    #expect(throws: EnrollmentError.self) { try trust.verify(forged.bytes, expectedRole: .publicUser, at: 150) }
}

@Test func enrollmentRevocationAndTrustExpiryFailClosed() throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let credential = try EnrollmentCredential.issue(card: SecureIdentity(role: .responder).card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let revoked = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300, revoked: [credential.serial])
    #expect(throws: EnrollmentError.self) { try revoked.verify(credential.bytes, expectedRole: .responder, at: 150) }
    let stale = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 150)
    #expect(throws: EnrollmentError.self) { try stale.verify(credential.bytes, expectedRole: .responder, at: 150) }
    #expect(throws: EnrollmentError.self) { try stale.verify(credential.bytes, expectedRole: .responder, at: -1) }
    #expect(throws: EnrollmentError.self) { try EnrollmentCredential.issue(card: credential.card, realm: realm, notBefore: 100, expires: 100, issuer: issuer) }
}

@Test func enrollmentRejectsCanonicalAndEqualShapeTampering() throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let credential = try EnrollmentCredential.issue(card: SecureIdentity(role: .responder).card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let trust = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300)
    var payload = try JSONSerialization.jsonObject(with: credential.bytes) as! [String: Any]
    payload["expires"] = 201 // valid shape and same encoded length; signature must bind semantics
    let changed = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    #expect(changed.count == credential.bytes.count)
    #expect(throws: EnrollmentError.self) { try trust.verify(changed, expectedRole: .responder, at: 150) }
    var spaced = credential.bytes; spaced.append(0x20)
    #expect(throws: EnrollmentError.self) { try trust.verify(spaced, expectedRole: .responder, at: 150) }
    payload["extra"] = true
    let extra = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
    #expect(throws: EnrollmentError.self) { try trust.verify(extra, expectedRole: .responder, at: 150) }
    #expect(throws: EnrollmentError.self) { try trust.verify(Data(repeating: 0, count: 4097), expectedRole: .responder, at: 150) }
}
