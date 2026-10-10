import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

final class InboxTestStore: SecureRecordStore {
    var data: Data?
    var fail = false
    var writesUntilFailure: Int?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws {
        if let remaining = writesUntilFailure {
            if remaining == 0 { throw SecureExchangeError.recordStore(-1) }
            writesUntilFailure = remaining - 1
        }
        if fail { throw SecureExchangeError.recordStore(-1) }
        self.data = data
    }
}
@MainActor struct InboxFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-inbox-\(UUID())")
    let responder: SecureEndpointController
    let users: [SecureEndpointController]
    let issuer = Curve25519.Signing.PrivateKey()
    let trust: EnrollmentTrust
    let credential: Data
    let registry = InboxTestStore()
    init(count: Int = 2) throws {
        let root = self.root
        responder = try SecureEndpointController(rootURL: root, role: .responder, recordStore: EnrollmentTestStore())
        users = try (0..<count).map { try SecureEndpointController(rootURL: root.appendingPathComponent("public-\($0)"), role: .publicUser, recordStore: EnrollmentTestStore()) }
        let realm = UUID()
        trust = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300)
        credential = try EnrollmentCredential.issue(card: responder.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer).bytes
    }
    func inbox() throws -> RegisteredResponderInbox {
        try RegisteredResponderInbox(secure: responder, credential: credential, trust: trust, registryStore: registry, now: { 150 })
    }
    func bootstrap(_ index: Int, inbox: RegisteredResponderInbox) throws -> EnrollmentBootstrap {
        let credential = try EnrollmentCredential.issue(card: users[index].card, realm: trust.realm, notBefore: 100, expires: 200, issuer: issuer)
        let b = try EnrollmentBootstrap(secure: users[index], credential: credential.bytes, trust: trust, now: { 150 })
        let challenge = try inbox.receive(b.hello())
        let ready = try inbox.receive(b.answerChallenge(challenge))
        try b.acceptReady(ready)
        return b
    }
}
@Test @MainActor func registeredInboxSeparatesIdenticalSampleIDsAndActions() throws {
    let f = try InboxFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    let a = try f.bootstrap(0, inbox: inbox), b = try f.bootstrap(1, inbox: inbox)
    #expect(inbox.rows.isEmpty)
    try f.users[0].perform(.sos, value: "Synthetic A")
    try f.users[1].perform(.sos, value: "Synthetic B")
    try a.confirm(inbox.receive(#require(try a.nextPacket())))
    try b.confirm(inbox.receive(#require(try b.nextPacket())))
    #expect(inbox.rows.count == 2)
    let id = f.users[0].card.fingerprint
    try inbox.perform(conversationID: id, action: .acknowledge)
    #expect(inbox.rows.first(where: { $0.id == id })?.snapshot.pendingTransfers == 1)
    #expect(inbox.rows.first(where: { $0.id != id })?.snapshot.pendingTransfers == 0)
    let restarted = try f.inbox()
    #expect(restarted.rows.count == 2)
    #expect(restarted.rows.first(where: { $0.id == id })?.snapshot.pendingTransfers == 1)
}
@Test @MainActor func registeredInboxRegistryFailureWithholdsReceiptAndRetriesExactHistory() throws {
    let f = try InboxFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox(), b = try f.bootstrap(0, inbox: inbox)
    try f.users[0].perform(.sos, value: "Synthetic retry")
    let packet = try #require(try b.nextPacket())
    f.registry.writesUntilFailure = 1
    #expect(throws: (any Error).self) { try inbox.receive(packet) }
    #expect(inbox.rows.isEmpty)
    f.registry.writesUntilFailure = nil
    inbox.stop()
    let restarted = try f.inbox()
    let retry = try f.bootstrap(0, inbox: restarted)
    try retry.confirm(restarted.receive(packet))
    #expect(restarted.rows.count == 1)
    #expect(f.users[0].endpoint.snapshot?.pendingTransfers == 0)
}

@Test @MainActor func registeredInboxRejectsAuthenticCrossConversationPacketsAndInvalidAdmission() throws {
    let f = try InboxFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    let a = try f.bootstrap(0, inbox: inbox), b = try f.bootstrap(1, inbox: inbox)
    let invalid = try SecureEnvelope(identity: f.users[0].enrollmentIdentity(), peer: f.responder.card).seal(Data("not a workflow event".utf8))
    #expect(throws: EndpointError.self) { try inbox.receive(invalid) }
    #expect(inbox.rows.isEmpty)
    try f.users[0].perform(.sos, value: "Synthetic A")
    try f.users[1].perform(.sos, value: "Synthetic B")
    let ap = try #require(try a.nextPacket()), bp = try #require(try b.nextPacket())
    let ar = try inbox.receive(ap), br = try inbox.receive(bp)
    #expect(throws: SecureExchangeError.wrongRecipient) { try a.confirm(br) }
    #expect(f.users[0].endpoint.snapshot?.pendingTransfers == 1)
    #expect(f.users[1].endpoint.snapshot?.pendingTransfers == 1)
    try a.confirm(ar); try b.confirm(br)
    let missing = InboxTestStore()
    #expect(throws: SecureExchangeError.recordMissing) {
        try RegisteredResponderInbox(secure: f.responder, credential: f.credential, trust: f.trust, registryStore: missing, now: { 150 })
    }
    let url = f.root.appendingPathComponent("registered-inbox").appendingPathComponent(f.responder.card.fingerprint).appendingPathComponent(f.users[0].card.fingerprint + ".sqlite")
    try FileManager.default.removeItem(at: url)
    #expect(throws: SecureExchangeError.historyMissing) { try inbox.perform(conversationID: f.users[0].card.fingerprint, action: .reply, value: "Synthetic") }
    #expect(throws: SecureExchangeError.historyMissing) { try f.inbox() }
}

@Test @MainActor func registeredInboxBoundsProvisionalProofsAndExpiresGlobally() throws {
    let f = try InboxFixture(count: 5); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    var clock = 100.0
    inbox.elapsed = { clock }
    var proofs: [EnrollmentBootstrap] = []
    for i in 0..<5 {
        let credential = try EnrollmentCredential.issue(card: f.users[i].card, realm: f.trust.realm, notBefore: 100, expires: 200, issuer: f.issuer)
        proofs.append(try EnrollmentBootstrap(secure: f.users[i], credential: credential.bytes, trust: f.trust, now: { 150 }))
    }
    for i in 0..<4 { _ = try inbox.receive(proofs[i].hello()) }
    #expect(throws: EnrollmentError.busy) { try inbox.receive(proofs[4].hello()) }
    #expect(inbox.rows.isEmpty)
    clock = 110
    _ = try inbox.receive(proofs[4].hello())
    #expect(inbox.rows.isEmpty)
}

@Test @MainActor func registeredInboxCapacityPreservesSixteenExactConversations() throws {
    let f = try InboxFixture(count: 17); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    for i in 0..<16 {
        let b = try f.bootstrap(i, inbox: inbox)
        try f.users[i].perform(.sos, value: "Synthetic capacity \(i)")
        try b.confirm(inbox.receive(#require(try b.nextPacket())))
    }
    #expect(inbox.rows.count == 16)
    #expect(throws: EnrollmentError.busy) { try f.bootstrap(16, inbox: inbox) }
    #expect(try f.inbox().rows.count == 16)
}

@Test @MainActor func registeredInboxAutomaticallyExchangesAcrossThreeRealSocketEndpoints() async throws {
    let f = try InboxFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    let controllers = try f.users.map { user in
        let credential = try EnrollmentCredential.issue(card: user.card, realm: f.trust.realm, notBefore: 100, expires: 200, issuer: f.issuer)
        return try RegisteredExchangeController(secure: user, credential: credential.bytes, trust: f.trust, now: { 150 })
    }
    try inbox.start()
    defer { inbox.stop(); controllers.forEach { $0.stop() } }
    for (i, controller) in controllers.enumerated() {
        try controller.perform(.sos, value: "Synthetic socket \(i)")
        try controller.start()
    }
    var deadline = ContinuousClock.now + .seconds(20)
    while (inbox.rows.count != 2 || f.users.contains(where: { $0.endpoint.snapshot?.pendingTransfers != 0 })) && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(inbox.rows.count == 2, "Inbox: \(inbox.status); peers \(inbox.transport.peers.count); public: \(controllers.map { $0.status })")
    for i in 0..<2 {
        try inbox.perform(conversationID: f.users[i].card.fingerprint, action: .acknowledge)
        try inbox.perform(conversationID: f.users[i].card.fingerprint, action: .reply, value: "Synthetic private reply \(i)")
    }
    deadline = ContinuousClock.now + .seconds(20)
    while inbox.rows.contains(where: { $0.snapshot.pendingTransfers != 0 }) && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(inbox.rows.allSatisfy { $0.snapshot.pendingTransfers == 0 })
    for i in 0..<2 {
        #expect(f.users[i].endpoint.snapshot?.state.originalDelivery == .humanAcknowledged)
        #expect(f.users[i].endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic private reply \(i)" }) == true)
        #expect(f.users[i].endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic private reply \(1-i)" }) == false)
    }
    // Leave A unreachable with pending responder work; reachable B still progresses.
    controllers[0].stop()
    try inbox.perform(conversationID: f.users[0].card.fingerprint, action: .reply, value: "Synthetic offline A")
    try inbox.perform(conversationID: f.users[1].card.fingerprint, action: .reply, value: "Synthetic reachable B")
    deadline = ContinuousClock.now + .seconds(15)
    while f.users[1].endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic reachable B" }) != true && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(f.users[1].endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic reachable B" }) == true)
    #expect(inbox.rows.first(where: { $0.id == f.users[0].card.fingerprint })?.snapshot.pendingTransfers == 1)
    inbox.stop()
    try inbox.perform(conversationID: f.users[1].card.fingerprint, action: .reply, value: "Synthetic saved over restart")
    try inbox.start()
    deadline = ContinuousClock.now + .seconds(20)
    while f.users[1].endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic saved over restart" }) != true && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(f.users[1].endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic saved over restart" }) == true)
}

@Test @MainActor func registeredInboxSavesResponderWorkWhileStopped() throws {
    let f = try InboxFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox(), b = try f.bootstrap(0, inbox: inbox)
    try f.users[0].perform(.sos, value: "Synthetic stopped")
    try b.confirm(inbox.receive(#require(try b.nextPacket())))
    inbox.stop()
    try inbox.perform(conversationID: f.users[0].card.fingerprint, action: .reply, value: "Synthetic saved while stopped")
    #expect(inbox.rows.first?.snapshot.pendingTransfers == 1)
}

@Test @MainActor func registeredInboxRejectsCorruptRegistryAndExpiredPreparedIdentity() throws {
    let f = try InboxFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    f.registry.data = Data("corrupt registry".utf8)
    #expect(throws: SecureExchangeError.recordInvalid) { try f.inbox() }
    #expect(throws: SecureExchangeError.staleSession) { try inbox.receive(Data("invalid".utf8)) }
    #expect(throws: EnrollmentError.expired) {
        try RegisteredResponderInbox(secure: f.responder, credential: f.credential, trust: f.trust, registryStore: InboxTestStore(), now: { 200 })
    }
}
@Test @MainActor func registeredInboxStopStartDiscardsProvisionalProofsAndAllowsFreshAdmission() throws {
    let f = try InboxFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    let publicCredential = try EnrollmentCredential.issue(card: f.users[0].card, realm: f.trust.realm, notBefore: 100, expires: 200, issuer: f.issuer)
    let old = try EnrollmentBootstrap(secure: f.users[0], credential: publicCredential.bytes, trust: f.trust, now: { 150 })
    let finish = try old.answerChallenge(inbox.receive(old.hello()))
    inbox.stop()
    try inbox.start(); defer { inbox.stop() }
    #expect(throws: EnrollmentError.wrongTranscript) { try inbox.receive(finish) }
    let fresh = try f.bootstrap(0, inbox: inbox)
    try f.users[0].perform(.sos, value: "Synthetic fresh proof")
    try fresh.confirm(inbox.receive(#require(try fresh.nextPacket())))
    #expect(inbox.rows.count == 1)
}

@Test @MainActor func registeredInboxRejectsAuthenticSameShapeDatabaseTransplantAndEmptyHistory() throws {
    let f = try InboxFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox()
    for i in 0..<2 {
        let b = try f.bootstrap(i, inbox: inbox)
        try f.users[i].perform(.sos, value: "Synthetic same shape")
        try b.confirm(inbox.receive(#require(try b.nextPacket())))
    }
    inbox.stop()
    let folder = f.root.appendingPathComponent("registered-inbox").appendingPathComponent(f.responder.card.fingerprint)
    let a = folder.appendingPathComponent(f.users[0].card.fingerprint + ".sqlite")
    let b = folder.appendingPathComponent(f.users[1].card.fingerprint + ".sqlite")
    let original = try Data(contentsOf: a)
    try Data(contentsOf: b).write(to: a, options: .atomic)
    #expect(throws: SecureExchangeError.historyMissing) { try f.inbox() }
    try original.write(to: a, options: .atomic)
    try Data().write(to: a, options: .atomic)
    #expect(throws: SecureExchangeError.historyMissing) { try f.inbox() }
}

@Test @MainActor func registeredInboxExplicitWorkspacePreservesPinnedLegacyIdentityAndHistory() throws {
    let f = try InboxFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    try f.responder.pair(f.users[0].card.base64)
    try f.users[0].pair(f.responder.card.base64)
    try f.users[0].perform(.sos, value: "Synthetic legacy history")
    let legacyPacket = try #require(try f.users[0].nextPacket())
    try f.users[0].confirm(f.responder.accept(legacyPacket))
    let before = f.responder.endpoint.snapshot
    let inbox = try f.inbox()
    #expect(inbox.rows.isEmpty)
    let b = try f.bootstrap(1, inbox: inbox)
    try f.users[1].perform(.sos, value: "Synthetic new workspace")
    try b.confirm(inbox.receive(#require(try b.nextPacket())))
    #expect(inbox.rows.map(\.id) == [f.users[1].card.fingerprint])
    #expect(f.responder.peerCard == f.users[0].card)
    #expect(f.responder.endpoint.snapshot?.state.messages.count == before?.state.messages.count)
    #expect(f.responder.endpoint.snapshot?.state.hasRequest == true)
    #expect(f.responder.endpoint.snapshot?.pendingTransfers == before?.pendingTransfers)
}

@Test @MainActor func registeredInboxAllowsKnownSQLiteRecoverySidecarAndRejectsUnknownOne() throws {
    let f = try InboxFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox(), b = try f.bootstrap(0, inbox: inbox)
    try f.users[0].perform(.sos, value: "Synthetic journal")
    try b.confirm(inbox.receive(#require(try b.nextPacket())))
    inbox.stop()
    let folder = f.root.appendingPathComponent("registered-inbox").appendingPathComponent(f.responder.card.fingerprint)
    let journal = folder.appendingPathComponent(f.users[0].card.fingerprint + ".sqlite-journal")
    try Data().write(to: journal)
    #expect(try f.inbox().rows.count == 1)
    try Data().write(to: folder.appendingPathComponent("unknown.sqlite-journal"))
    #expect(throws: SecureExchangeError.recordInvalid) { try f.inbox() }
}

@Test @MainActor func registeredInboxWorkerDoesNotSendAfterRegistryReplacement() async throws {
    let f = try InboxFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox(), publicTransport = LocalExchangeTransport(registrationTimeout: .seconds(3))
    try inbox.start()
    defer { inbox.stop(); publicTransport.stop() }
    let b = try f.bootstrap(0, inbox: inbox)
    try f.users[0].perform(.sos, value: "Synthetic registry fence")
    try b.confirm(inbox.receive(#require(try b.nextPacket())))
    var received = 0
    publicTransport.onIncoming = { packet in
        received += 1
        return try f.users[0].accept(packet)
    }
    let name = "RescueRegistered-public-\(f.users[0].card.fingerprint.prefix(16))-\(UUID().uuidString.prefix(8))"
    try publicTransport.start(name: name)
    let deadline = ContinuousClock.now + .seconds(10)
    while !inbox.transport.peers.contains(where: {
        if case .service(let discovered, _, _, _) = $0.endpoint { return discovered == name }
        return false
    }) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    #expect(!inbox.transport.peers.isEmpty)
    // Save while the registry is current, then replace it before yielding to the worker.
    try inbox.perform(conversationID: f.users[0].card.fingerprint, action: .reply, value: "Synthetic must stay saved")
    f.registry.data = Data("replaced registry".utf8)
    try await Task.sleep(for: .seconds(3))
    #expect(received == 0)
    #expect(inbox.rows.first?.snapshot.pendingTransfers == 1)
}

@Test @MainActor func registeredInboxWorkerDoesNotConfirmAfterRegistryChangesDuringExchange() async throws {
    let f = try InboxFixture(count: 1); defer { try? FileManager.default.removeItem(at: f.root) }
    let inbox = try f.inbox(), publicTransport = LocalExchangeTransport(registrationTimeout: .seconds(3))
    try inbox.start()
    defer { inbox.stop(); publicTransport.stop() }
    let b = try f.bootstrap(0, inbox: inbox)
    try f.users[0].perform(.sos, value: "Synthetic midflight registry fence")
    try b.confirm(inbox.receive(#require(try b.nextPacket())))
    var received = 0
    publicTransport.onIncoming = { packet in
        // The exact legitimate peer commits the message and returns its authentic receipt.
        let receipt = try f.users[0].accept(packet)
        received += 1
        f.registry.data = Data("registry replaced during awaited exchange".utf8)
        return receipt
    }
    try publicTransport.start(name: "RescueRegistered-public-\(f.users[0].card.fingerprint.prefix(16))-\(UUID().uuidString.prefix(8))")
    try inbox.perform(conversationID: f.users[0].card.fingerprint, action: .reply, value: "Synthetic unconfirmed after replacement")
    let deadline = ContinuousClock.now + .seconds(10)
    while received == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
    #expect(received > 0)
    try await Task.sleep(for: .milliseconds(600))
    #expect(inbox.rows.first?.snapshot.pendingTransfers == 1)
    #expect(f.users[0].endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic unconfirmed after replacement" }) == true)
}
