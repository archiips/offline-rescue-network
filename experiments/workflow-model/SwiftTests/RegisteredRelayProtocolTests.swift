import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

private struct RegisteredRelayFixture {
    let issuer = Curve25519.Signing.PrivateKey()
    let realm = UUID()
    let sender = SecureIdentity(role: .publicUser)
    let recipient = SecureIdentity(role: .responder)
    func credential(_ identity: SecureIdentity, realm override: UUID? = nil, issuer key: Curve25519.Signing.PrivateKey? = nil) throws -> EnrollmentCredential {
        try .issue(card: identity.card, realm: override ?? realm, notBefore: 100, expires: 300, issuer: key ?? issuer)
    }
    func trust(revoked: Set<UUID> = []) throws -> EnrollmentTrust {
        try .init(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 250, revoked: revoked)
    }
    func packet() throws -> RelayPacket {
        try .make(kind: .event, priority: .urgent, expiry: 240, correlation: Data(count: 32),
                  sealed: SecureEnvelope(identity: sender, peer: recipient.card).seal(Data([1])), identity: sender, recipient: recipient.card)
    }
    func wrapper() throws -> RegisteredRelayPacket {
        try .init(senderCredential: credential(sender).bytes, recipientCredential: credential(recipient).bytes, packet: packet())
    }
}

@Test func registeredRelayWrapperPreservesExactPacketAndVerifiesCredentials() throws {
    let f = RegisteredRelayFixture(), wrapper = try f.wrapper()
    let loaded = try RegisteredRelayPacket(bytes: wrapper.bytes)
    #expect(loaded.bytes == wrapper.bytes && loaded.packet == wrapper.packet)
    let cards = try loaded.authenticate(trust: f.trust(), now: 150)
    #expect(cards.sender == f.sender.card && cards.recipient == f.recipient.card)
    #expect(throws: (any Error).self) { try loaded.authenticate(trust: f.trust(), now: 250) }
    #expect(throws: (any Error).self) { try loaded.authenticate(trust: f.trust(), now: 99) }
    // A renewed valid credential for the same exact card grants equivalent authorization.
    let renewed = try RegisteredRelayPacket(senderCredential: f.credential(f.sender).bytes, recipientCredential: wrapper.recipientCredential, packet: wrapper.packet)
    #expect(try renewed.authenticate(trust: f.trust(), now: 150).sender == f.sender.card)
    let reverse = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: 240, correlation: wrapper.packet.digest,
        sealed: SecureEnvelope(identity: f.recipient, peer: f.sender.card).seal(Data([2])), identity: f.recipient, recipient: f.sender.card)
    let receipt = try RegisteredRelayPacket(senderCredential: wrapper.recipientCredential, recipientCredential: wrapper.senderCredential, packet: reverse)
    #expect(try receipt.authenticate(trust: f.trust(), now: 150).recipient == f.sender.card)

}

@Test func registeredRelayWrapperRejectsCredentialSubstitutionAndAuthorityMismatch() throws {
    let f = RegisteredRelayFixture(), packet = try f.packet(), recipient = try f.credential(f.recipient)
    let other = SecureIdentity(role: .publicUser)
    for credential in [try f.credential(other), try f.credential(f.sender, realm: UUID()), try f.credential(f.sender, issuer: .init())] {
        let wrapper = try RegisteredRelayPacket(senderCredential: credential.bytes, recipientCredential: recipient.bytes, packet: packet)
        #expect(throws: (any Error).self) { try wrapper.authenticate(trust: f.trust(), now: 150) }
    }
    let sender = try f.credential(f.sender)
    let wrapper = try RegisteredRelayPacket(senderCredential: sender.bytes, recipientCredential: recipient.bytes, packet: packet)
    #expect(throws: (any Error).self) { try wrapper.authenticate(trust: f.trust(revoked: [sender.serial]), now: 150) }
    let bothPublic = try RegisteredRelayPacket(senderCredential: sender.bytes, recipientCredential: f.credential(other).bytes, packet: packet)
    #expect(throws: (any Error).self) { try bothPublic.authenticate(trust: f.trust(), now: 150) }
}

@Test func registeredRelayWrapperRejectsFramingAndPacketPolicyViolations() throws {
    let f = RegisteredRelayFixture(), wrapper = try f.wrapper()
    for bytes in [wrapper.bytes + Data([0]), Data(wrapper.bytes.dropLast()), Data(repeating: 0, count: 4277), Data("ORRG1".utf8)] {
        #expect(throws: (any Error).self) { try RegisteredRelayPacket(bytes: bytes) }
    }
    #expect(throws: (any Error).self) {
        try RegisteredRelayPacket(senderCredential: Data(repeating: 1, count: 4096), recipientCredential: Data(repeating: 2, count: 4096), packet: wrapper.packet)
    }
    var lengths = wrapper.bytes
    lengths.replaceSubrange(5..<9, with: [255,255,255,255])
    #expect(throws: (any Error).self) { try RegisteredRelayPacket(bytes: lengths) }
    var policy = wrapper.bytes
    let offset = policy.count - wrapper.packet.bytes.count
    policy[offset + 4] = 2
    #expect(throws: (any Error).self) { try RegisteredRelayPacket(bytes: policy) }
}

@Test func preparedResponderDirectoryPreservesLegacyCanonicalProfileAndSignedMembership() throws {
    let f = RegisteredRelayFixture(), own = try f.credential(f.sender), responder = try f.credential(f.recipient)
    let old = try EnrollmentProfile.issue(realm: f.realm, issuer: f.issuer, validUntil: 250, credential: own.bytes)
    #expect(old.responders == nil)
    let oldBytes = try old.encoded()
    #expect(!String(decoding: oldBytes, as: UTF8.self).contains("responders"))
    #expect(try EnrollmentProfile.decode(oldBytes).encoded() == oldBytes)
    #expect(try old.validate(card: f.sender.card, issuerApproved: true, at: 150).realm == f.realm)
    let profile = try EnrollmentProfile.issue(realm: f.realm, issuer: f.issuer, validUntil: 250, credential: own.bytes, responders: [responder.bytes])
    let loaded = try EnrollmentProfile.decode(profile.encoded())
    let trust = try loaded.validate(card: f.sender.card, issuerApproved: true, at: 150)
    #expect(try loaded.verifiedResponders(trust: trust, at: 150).map(\.card) == [f.recipient.card])
    var object = try #require(JSONSerialization.jsonObject(with: profile.encoded()) as? [String: Any])
    object["responders"] = []
    let tampered = try EnrollmentProfile.decode(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys,.withoutEscapingSlashes]))
    #expect(throws: (any Error).self) { try tampered.validate(card: f.sender.card, issuerApproved: true, at: 150) }
}

@Test func preparedResponderDirectoryRejectsWrongRoleIssuerRevocationDuplicateAndBounds() throws {
    let f = RegisteredRelayFixture(), own = try f.credential(f.sender), responder = try f.credential(f.recipient)
    for candidate in [own, try f.credential(f.recipient, issuer: .init()), try f.credential(f.recipient, realm: UUID())] {
        let profile = try EnrollmentProfile.issue(realm: f.realm, issuer: f.issuer, validUntil: 250, credential: own.bytes, responders: [candidate.bytes])
        #expect(throws: (any Error).self) { try profile.validate(card: f.sender.card, issuerApproved: true, at: 150) }
    }
    let revoked = try EnrollmentProfile.issue(realm: f.realm, issuer: f.issuer, validUntil: 250, credential: own.bytes, revoked: [responder.serial], responders: [responder.bytes])
    #expect(throws: (any Error).self) { try revoked.validate(card: f.sender.card, issuerApproved: true, at: 150) }
    let duplicate = try EnrollmentProfile.issue(realm: f.realm, issuer: f.issuer, validUntil: 250, credential: own.bytes, responders: [responder.bytes, responder.bytes])
    #expect(throws: (any Error).self) { try duplicate.validate(card: f.sender.card, issuerApproved: true, at: 150) }
    #expect(throws: (any Error).self) { try EnrollmentProfile.issue(realm: f.realm, issuer: f.issuer, validUntil: 250, credential: own.bytes, responders: Array(repeating: responder.bytes, count: 5)) }
}
