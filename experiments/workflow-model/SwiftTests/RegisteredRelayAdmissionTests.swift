import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@MainActor private struct RegisteredRelayFixture {
    let base: InboxFixture
    let credentials: [Data]
    init(count: Int = 2) throws {
        let fixture = try InboxFixture(count: count)
        base = fixture
        credentials = try fixture.users.map { try EnrollmentCredential.issue(card: $0.card, realm: fixture.trust.realm,
            notBefore: 100, expires: 200, issuer: fixture.issuer).bytes }
    }
    func user(_ index: Int, trust: EnrollmentTrust? = nil) throws -> RegisteredExchangeController {
        try RegisteredExchangeController(secure: base.users[index], credential: credentials[index],
            trust: trust ?? base.trust, responders: [base.credential], now: { 150 })
    }
    func relay() throws -> RegisteredRelayService {
        try RegisteredRelayService(storageURL: base.root.appendingPathComponent("registered-custody.sqlite"), trust: base.trust, now: { 150 })
    }
}

@MainActor @Test func registeredRelayAdmitsUnpairedSOSAndDelaysPinUntilReverseReceipt() async throws {
    let f = try RegisteredRelayFixture(); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let inbox = try f.base.inbox(), user = try f.user(0), relay = try f.relay()
    try user.perform(.sos, value: "SYNTHETIC delayed first contact")
    let outgoing = try #require(try user.registeredRelayOutgoing())
    _ = try relay.admit(outgoing.bytes)
    #expect(f.base.users[0].peerCard == nil)
    #expect(user.snapshot?.pendingTransfers == 1)
    let forward = try await relay.flush(eligibleDestinations: [f.base.responder.card.digest]) { bytes, destination in
        #expect(destination == f.base.responder.card)
        return try inbox.receiveRegisteredRelay(bytes)
    }
    guard case .delivered = forward else { Issue.record("SOS not forwarded: \(forward)"); return }
    #expect(inbox.rows.count == 1)
    #expect(f.base.users[0].peerCard == nil)
    #expect(user.snapshot?.pendingTransfers == 1)
    #expect(try relay.count() == 1)
    let reverse = try await relay.flush(eligibleDestinations: [f.base.users[0].card.digest]) { bytes, destination in
        #expect(destination == f.base.users[0].card)
        return try user.receiveRegisteredRelay(bytes)
    }
    guard case .delivered = reverse else { Issue.record("Receipt not forwarded: \(reverse)"); return }
    #expect(f.base.users[0].peerCard == f.base.responder.card)
    #expect(user.snapshot?.pendingTransfers == 0)
    #expect(user.snapshot?.state.originalDelivery == .deviceReceived)
    #expect(try relay.count() == 0)
    let id = f.base.users[0].card.fingerprint
    try inbox.perform(conversationID: id, action: .acknowledge)
    _ = try relay.admit(#require(try inbox.registeredRelayOutgoing(conversationID: id)).bytes)
    _ = try await relay.flush(eligibleDestinations: [f.base.users[0].card.digest]) { bytes, _ in try user.receiveRegisteredRelay(bytes) }
    #expect(user.snapshot?.state.originalDelivery == .humanAcknowledged)
    _ = try await relay.flush(eligibleDestinations: [f.base.responder.card.digest]) { bytes, _ in try inbox.receiveRegisteredRelay(bytes) }
    try inbox.perform(conversationID: id, action: .reply, value: "SYNTHETIC relay reply")
    _ = try relay.admit(#require(try inbox.registeredRelayOutgoing(conversationID: id)).bytes)
    _ = try await relay.flush(eligibleDestinations: [f.base.users[0].card.digest]) { bytes, _ in try user.receiveRegisteredRelay(bytes) }
    #expect(user.snapshot?.state.messages.last?.text == "SYNTHETIC relay reply")
    _ = try await relay.flush(eligibleDestinations: [f.base.responder.card.digest]) { bytes, _ in try inbox.receiveRegisteredRelay(bytes) }
    #expect(inbox.rows.first?.snapshot.pendingTransfers == 0)
}

@MainActor @Test func registeredRelayKeepsPublicConversationsAndRestartWrappersSeparate() throws {
    let f = try RegisteredRelayFixture(); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let a = try f.user(0), b = try f.user(1), inbox = try f.base.inbox()
    try a.perform(.sos, value: "SYNTHETIC A"); try b.perform(.sos, value: "SYNTHETIC B")
    let first = try #require(try a.registeredRelayOutgoing()), second = try #require(try b.registeredRelayOutgoing())
    let resumed = try f.user(0)
    #expect(try resumed.registeredRelayOutgoing()?.bytes == first.bytes)
    _ = try inbox.receiveRegisteredRelay(first.bytes)
    _ = try inbox.receiveRegisteredRelay(second.bytes)
    #expect(inbox.rows.count == 2)
    #expect(inbox.rows.allSatisfy { $0.snapshot.pendingTransfers == 0 })
    let response = try RelayAcceptance(bytes: inbox.receiveRegisteredRelay(first.bytes))
    let inner = try #require(try response.verify(original: first.packet, destination: f.base.responder.card, origin: f.base.users[0].card, now: 150))
    let receipt = try RegisteredRelayPacket(senderCredential: f.base.credential, recipientCredential: f.credentials[0], packet: inner)
    #expect(throws: (any Error).self) { try b.receiveRegisteredRelay(receipt.bytes) }
    #expect(b.snapshot?.pendingTransfers == 1)
    #expect(f.base.users[1].peerCard == nil)
    let reloaded = try f.base.inbox()
    #expect(reloaded.rows.count == 2)
}

@MainActor @Test func registeredRelayRejectsRevokedFirstContactBeforeAdmission() throws {
    let f = try RegisteredRelayFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let user = try f.user(0)
    try user.perform(.sos, value: "SYNTHETIC revoked")
    let wrapper = try #require(try user.registeredRelayOutgoing())
    let serial = try EnrollmentCredential.decode(f.credentials[0]).serial
    let trust = try EnrollmentTrust(realm: f.base.trust.realm, issuer: f.base.issuer.publicKey.rawRepresentation,
        validUntil: 300, revoked: [serial])
    let inbox = try RegisteredResponderInbox(secure: f.base.responder, credential: f.base.credential,
        trust: trust, registryStore: f.base.registry, now: { 150 })
    #expect(throws: EnrollmentError.revoked) { try inbox.receiveRegisteredRelay(wrapper.bytes) }
    #expect(inbox.rows.isEmpty)
    #expect(user.snapshot?.pendingTransfers == 1)
    #expect(f.base.users[0].peerCard == nil)
}

@MainActor @Test func registeredRelayReceiptOnlyAndMalformedEventCannotAdmitInboxConversation() throws {
    let f = try RegisteredRelayFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let inbox = try f.base.inbox(), identity = try f.base.users[0].enrollmentIdentity()
    let sealed = try SecureEnvelope(identity: identity, peer: f.base.responder.card).seal(Data("not a workflow event".utf8))
    let receipt = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: 190,
        correlation: Data(repeating: 1, count: 32), sealed: sealed, identity: identity, recipient: f.base.responder.card)
    let receiptWrapper = try RegisteredRelayPacket(senderCredential: f.credentials[0], recipientCredential: f.base.credential, packet: receipt)
    #expect(throws: (any Error).self) { try inbox.receiveRegisteredRelay(receiptWrapper.bytes) }
    #expect(inbox.rows.isEmpty)
    let event = try RelayPacket.make(kind: .event, priority: .ordinary, expiry: 190,
        correlation: Data(count: 32), sealed: sealed, identity: identity, recipient: f.base.responder.card)
    let eventWrapper = try RegisteredRelayPacket(senderCredential: f.credentials[0], recipientCredential: f.base.credential, packet: event)
    #expect(throws: (any Error).self) { try inbox.receiveRegisteredRelay(eventWrapper.bytes) }
    #expect(inbox.rows.isEmpty)
    #expect(f.base.users[0].peerCard == nil)
}

@MainActor @Test func registeredRelayAdmissionCapacityPreservesExistingSixteenConversations() throws {
    let f = try RegisteredRelayFixture(count: 17); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let inbox = try f.base.inbox()
    for index in 0..<16 {
        let user = try f.user(index)
        try user.perform(.sos, value: "SYNTHETIC capacity \(index)")
        _ = try inbox.receiveRegisteredRelay(#require(try user.registeredRelayOutgoing()).bytes)
    }
    #expect(inbox.rows.count == 16)
    let overflow = try f.user(16)
    try overflow.perform(.sos, value: "SYNTHETIC overflow")
    #expect(throws: EnrollmentError.busy) { try inbox.receiveRegisteredRelay(#require(try overflow.registeredRelayOutgoing()).bytes) }
    #expect(inbox.rows.count == 16)
    #expect(overflow.snapshot?.pendingTransfers == 1)
    #expect(try f.base.inbox().rows.count == 16)
}

@MainActor @Test func registeredRelayMalformedCandidatesRemainBoundedAndExpireWithoutAdmission() throws {
    let f = try RegisteredRelayFixture(count: 5); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let inbox = try f.base.inbox()
    var elapsed = 100.0
    inbox.elapsed = { elapsed }
    func malformed(_ index: Int) throws -> Data {
        let identity = try f.base.users[index].enrollmentIdentity()
        let inner = try RelayPacket.make(kind: .event, priority: .urgent, expiry: 190, correlation: Data(count: 32),
            sealed: SecureEnvelope(identity: identity, peer: f.base.responder.card).seal(Data("not a C++ workflow event".utf8)),
            identity: identity, recipient: f.base.responder.card)
        return try RegisteredRelayPacket(senderCredential: f.credentials[index], recipientCredential: f.base.credential, packet: inner).bytes
    }
    for index in 0..<4 { #expect(throws: (any Error).self) { try inbox.receiveRegisteredRelay(malformed(index)) } }
    #expect(throws: EnrollmentError.busy) { try inbox.receiveRegisteredRelay(malformed(4)) }
    #expect(inbox.rows.isEmpty)
    let ready = try f.user(4)
    try ready.perform(.sos, value: "SYNTHETIC after provisional expiry")
    let valid = try #require(try ready.registeredRelayOutgoing())
    #expect(throws: EnrollmentError.busy) { try inbox.receiveRegisteredRelay(valid.bytes) }
    elapsed += 10
    _ = try inbox.receiveRegisteredRelay(valid.bytes)
    #expect(inbox.rows.count == 1)
    #expect(inbox.rows.first?.id == f.base.users[4].card.fingerprint)
}

@MainActor @Test func registeredRelayUnselectedAuthorizedResponderCannotPoisonPublicCache() throws {
    let f = try RegisteredRelayFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let user = try f.user(0), other = SecureIdentity(role: .responder)
    let credential = try EnrollmentCredential.issue(card: other.card, realm: f.base.trust.realm, notBefore: 100, expires: 200, issuer: f.base.issuer)
    try user.perform(.sos, value: "SYNTHETIC selected responder")
    let inner = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: 190, correlation: Data(repeating: 1, count: 32),
        sealed: SecureEnvelope(identity: other, peer: f.base.users[0].card).seal(Data("not a receipt".utf8)), identity: other, recipient: f.base.users[0].card)
    let wrong = try RegisteredRelayPacket(senderCredential: credential.bytes, recipientCredential: f.credentials[0], packet: inner)
    // Credential, role, realm and envelope authentication all succeed; rejection must be selected-card binding.
    #expect(try wrong.authenticate(trust: f.base.trust, now: 150).sender == other.card)
    #expect(throws: EnrollmentError.wrongIdentity) { try user.receiveRegisteredRelay(wrong.bytes) }
    let guardURL = f.base.users[0].endpoint.storageURL.deletingPathExtension().appendingPathExtension("relay-cache.guard")
    #expect(!FileManager.default.fileExists(atPath: guardURL.path))
    let valid = try #require(try user.registeredRelayOutgoing())
    #expect(try valid.authenticate(trust: f.base.trust, now: 150).recipient == f.base.responder.card)
    #expect(f.base.users[0].peerCard == nil)
}

@MainActor @Test func registeredRelayWrapperCacheRejectsSameCardCredentialSubstitution() throws {
    let f = try RegisteredRelayFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let user = try f.user(0)
    try user.perform(.sos, value: "SYNTHETIC wrapper binding")
    let original = try #require(try user.registeredRelayOutgoing())
    let renewed = try EnrollmentCredential.issue(card: f.base.users[0].card, realm: f.base.trust.realm,
        notBefore: 100, expires: 200, issuer: f.base.issuer)
    let changed = try RegisteredRelayPacket(senderCredential: renewed.bytes, recipientCredential: original.recipientCredential, packet: original.packet)
    #expect(changed.bytes.count == original.bytes.count && changed.bytes != original.bytes)
    #expect(try changed.authenticate(trust: f.base.trust, now: 150).sender == f.base.users[0].card)
    let cacheURL = f.base.users[0].endpoint.storageURL.deletingPathExtension().appendingPathExtension("registered-relay.sqlite")
    let cache = try RelayQueue(storageURL: cacheURL)
    let row = try #require(try cache.lookup(id: original.packet.id))
    _ = try cache.remove(id: row.id)
    _ = try cache.cacheAdmit(id: row.id, flow: row.flow, priority: row.priority, expiry: row.expiry, hops: 2,
        payload: changed.bytes + row.payload.suffix(64), now: 150)
    #expect(throws: RelayProtocolError.cacheMismatch) { try user.registeredRelayOutgoing() }
    #expect(user.snapshot?.pendingTransfers == 1)
    #expect(f.base.users[0].peerCard == nil)
}

@MainActor @Test func registeredRelayStoppedControllersRejectIncomingAndOutgoingWork() throws {
    let f = try RegisteredRelayFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.base.root) }
    let user = try f.user(0), inbox = try f.base.inbox()
    try user.perform(.sos, value: "SYNTHETIC stopped")
    let event = try #require(try user.registeredRelayOutgoing())
    let accepted = try RelayAcceptance(bytes: inbox.receiveRegisteredRelay(event.bytes))
    let receipt = try #require(try accepted.verify(original: event.packet, destination: f.base.responder.card, origin: f.base.users[0].card, now: 150))
    let reverse = try RegisteredRelayPacket(senderCredential: f.base.credential, recipientCredential: f.credentials[0], packet: receipt)
    user.stop(); inbox.stop()
    #expect(throws: EnrollmentError.stopped) { try user.receiveRegisteredRelay(reverse.bytes) }
    #expect(throws: EnrollmentError.stopped) { try user.registeredRelayOutgoing() }
    #expect(throws: EnrollmentError.stopped) { try inbox.receiveRegisteredRelay(event.bytes) }
    #expect(throws: EnrollmentError.stopped) { try inbox.registeredRelayOutgoing(conversationID: f.base.users[0].card.fingerprint) }
    #expect(user.snapshot?.pendingTransfers == 1)
    #expect(f.base.users[0].peerCard == nil)
}
