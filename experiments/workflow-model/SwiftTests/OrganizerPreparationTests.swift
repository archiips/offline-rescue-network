import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@MainActor @Test func organizerPreparationPossessionAndExactRetry() throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let service = OrganizerPreparationService(issuer: issuer, realm: realm, now: { 100 }, elapsed: { 1 })
    let identity = SecureIdentity(role: .publicUser), client = OrganizerPreparationClient(identity: SecureIdentity(role: .publicUser), now: { 100 })
    let hello = try client.hello(), challenge = try service.challenge(hello)
    let proof = try client.prove(challenge)
    let response = try service.issue(proof)
    #expect(try service.issue(proof) == response)
    let profile = try EnrollmentProfile.decode(client.profile(response))
    #expect(try profile.validate(card: client.card, issuerApproved: true, at: 100).realm == realm)
    #expect(throws: EnrollmentError.self) { try profile.validate(card: identity.card, issuerApproved: true, at: 100) }
    #expect(throws: EnrollmentError.self) { try profile.validate(card: client.card, issuerApproved: false, at: 100) }
    service.stop()
    #expect(throws: EnrollmentError.self) { try service.issue(proof) }
}

@MainActor @Test func organizerPreparationRejectsUnauthorizedResponderAndExpiredChallenge() throws {
    var time = 1.0
    let issuer = Curve25519.Signing.PrivateKey(), responder = SecureIdentity(role: .responder)
    let service = OrganizerPreparationService(issuer: issuer, realm: UUID(), now: { 100 }, elapsed: { time })
    let denied = OrganizerPreparationClient(identity: responder, now: { 100 })
    #expect(throws: EnrollmentError.self) { try service.challenge(denied.hello()) }
    let allowed = OrganizerPreparationService(issuer: issuer, realm: UUID(), authorizedResponderCards: [responder.card.bytes], now: { 100 }, elapsed: { time })
    let proof = try denied.prove(allowed.challenge(denied.hello()))
    time = 11
    #expect(throws: EnrollmentError.self) { try allowed.issue(proof) }
}

@MainActor @Test func organizerPreparationRejectsForgeryCrossChallengeAndCapacity() throws {
    let service = OrganizerPreparationService(issuer: .init(), realm: UUID(), now: { 100 }, elapsed: { 1 })
    let one = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 }), two = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 })
    let challenge = try service.challenge(one.hello())
    _ = try two.hello()
    #expect(throws: EnrollmentError.self) { try two.prove(challenge) }
    let proof = try one.prove(challenge)
    var value = try EnrollmentWire.decode(OrganizerPreparationProof.self, proof)
    value.signature = Data(repeating: 0, count: 64)
    #expect(throws: EnrollmentError.self) { try service.issue(EnrollmentWire.encode(value)) }
    value = try EnrollmentWire.decode(OrganizerPreparationProof.self, proof)
    value.claims.realm = UUID()
    #expect(throws: EnrollmentError.self) { try service.issue(EnrollmentWire.encode(value)) }
    for _ in 0..<63 { let client = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 }); _ = try service.challenge(client.hello()) }
    #expect(throws: EnrollmentError.self) { try service.challenge(OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 }).hello()) }
    #expect(throws: EnrollmentError.self) { try service.challenge(Data(repeating: 0, count: 4097)) }
}

@MainActor @Test func organizerPreparationBindsResultAndRejectsStoppedClient() throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let first = OrganizerPreparationService(issuer: issuer, realm: realm, now: { 100 }, elapsed: { 1 })
    let second = OrganizerPreparationService(issuer: issuer, realm: realm, now: { 100 }, elapsed: { 1 })
    let client = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 })
    let hello = try client.hello(), challenge = try first.challenge(hello)
    var altered = try EnrollmentWire.decode(OrganizerPreparationChallenge.self, challenge)
    altered.claims.realm = UUID()
    #expect(throws: EnrollmentError.self) { try client.prove(EnrollmentWire.encode(altered)) }
    let proof = try client.prove(challenge)
    _ = try second.challenge(hello)
    #expect(throws: EnrollmentError.self) { try second.issue(proof) }
    let result = try first.issue(proof)
    var changed = try EnrollmentWire.decode(OrganizerPreparationResult.self, result)
    changed.claims.proof = Data(repeating: 0, count: 32)
    #expect(throws: EnrollmentError.self) { try client.profile(EnrollmentWire.encode(changed)) }
    #expect(throws: EnrollmentError.self) { try client.profile(result + Data("\n".utf8)) }
    client.stop()
    #expect(throws: EnrollmentError.self) { try client.profile(result) }
    #expect(throws: EnrollmentError.self) { try client.hello() }
}

@MainActor @Test func organizerPreparationCapacityRecoversAndRejectsClockRegression() throws {
    var time = 1.0
    let service = OrganizerPreparationService(issuer: .init(), realm: UUID(), now: { 100 }, elapsed: { time })
    let client = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 })
    let proof = try client.prove(service.challenge(client.hello()))
    time = 0
    #expect(throws: EnrollmentError.self) { try service.issue(proof) }
    time = 20
    let renewed = try client.prove(service.challenge(client.hello()))
    #expect(try client.profile(service.issue(renewed)).count < 4096)
}

@MainActor @Test func organizerPreparationCopiedCardDoesNotProvePossessionAndClientExpires() throws {
    var elapsed = 1.0
    let service = OrganizerPreparationService(issuer: .init(), realm: UUID(), now: { 100 }, elapsed: { elapsed })
    let client = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 }, elapsed: { elapsed })
    let challenge = try service.challenge(client.hello()), proof = try client.prove(challenge)
    var forged = try EnrollmentWire.decode(OrganizerPreparationProof.self, proof)
    forged.signature = try Curve25519.Signing.PrivateKey().signature(for: EnrollmentWire.encode(forged.claims))
    #expect(throws: EnrollmentError.self) { try service.issue(EnrollmentWire.encode(forged)) }
    let response = try service.issue(proof)
    elapsed = 11
    #expect(throws: EnrollmentError.self) { try client.profile(response) }
    #expect(throws: EnrollmentError.self) { try service.issue(proof) }
}

@MainActor @Test func organizerPreparationIncludesBoundedAuthorizedResponderDirectory() throws {
    let responders = (0..<4).map { _ in SecureIdentity(role: .responder) }
    let service = OrganizerPreparationService(issuer: .init(), realm: UUID(), authorizedResponderCards: Set(responders.map { $0.card.bytes }), now: { 100 }, elapsed: { 1 })
    let client = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 })
    let proof = try client.prove(service.challenge(client.hello())), result = try service.issue(proof)
    #expect(result.count <= 4096)
    var tampered = try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
    var resultClaims = try #require(tampered["claims"] as? [String: Any])
    var nestedProfile = try #require(resultClaims["profile"] as? [String: Any])
    nestedProfile["responders"] = [String]()
    resultClaims["profile"] = nestedProfile; tampered["claims"] = resultClaims
    let alteredResult = try JSONSerialization.data(withJSONObject: tampered, options: [.sortedKeys, .withoutEscapingSlashes])
    #expect(throws: EnrollmentError.self) { try client.profile(alteredResult) }
    #expect(try service.issue(proof) == result)
    let profile = try EnrollmentProfile.decode(client.profile(result))
    let trust = try profile.validate(card: client.card, issuerApproved: true, at: 100)
    #expect(Set(try profile.verifiedResponders(trust: trust, at: 100).map { $0.card.bytes }) == Set(responders.map { $0.card.bytes }))
    let responder = OrganizerPreparationClient(identity: responders[0], now: { 100 })
    let responderProfile = try EnrollmentProfile.decode(responder.profile(service.issue(responder.prove(service.challenge(responder.hello())))))
    #expect(responderProfile.responders == nil)
    let stranger = OrganizerPreparationClient(identity: .init(role: .responder), now: { 100 })
    #expect(throws: EnrollmentError.self) { try service.challenge(stranger.hello()) }
}

@MainActor @Test func organizerPreparationRejectsOversizedOrWrongRoleDirectory() throws {
    let cards = Set((0..<5).map { _ in SecureIdentity(role: .responder).card.bytes })
    let oversized = OrganizerPreparationService(issuer: .init(), realm: UUID(), authorizedResponderCards: cards, now: { 100 }, elapsed: { 1 })
    let client = OrganizerPreparationClient(identity: .init(role: .publicUser), now: { 100 })
    #expect(throws: EnrollmentError.self) { try oversized.challenge(client.hello()) }
    let wrong = OrganizerPreparationService(issuer: .init(), realm: UUID(), authorizedResponderCards: [client.card.bytes], now: { 100 }, elapsed: { 1 })
    #expect(throws: EnrollmentError.self) { try wrong.challenge(client.hello()) }
}
