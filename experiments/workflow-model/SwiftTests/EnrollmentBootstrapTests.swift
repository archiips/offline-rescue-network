import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

final class EnrollmentTestStore: SecureRecordStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
}

@MainActor struct EnrollmentFixture {
    let root: URL
    let issuer: Curve25519.Signing.PrivateKey
    let realm: UUID
    let trust: EnrollmentTrust
    let user: SecureEndpointController
    let responder: SecureEndpointController
    let userBootstrap: EnrollmentBootstrap
    let responderBootstrap: EnrollmentBootstrap
    init(now: @escaping @MainActor () -> Int64 = { 150 }) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-enroll-\(UUID())")
        user = try SecureEndpointController(rootURL: root.appendingPathComponent("user"), role: .publicUser, recordStore: EnrollmentTestStore())
        responder = try SecureEndpointController(rootURL: root.appendingPathComponent("responder"), role: .responder, recordStore: EnrollmentTestStore())
        issuer = Curve25519.Signing.PrivateKey(); realm = UUID()
        trust = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300)
        userBootstrap = try EnrollmentBootstrap(secure: user, credential: EnrollmentCredential.issue(card: user.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer).bytes, trust: trust, now: now)
        responderBootstrap = try EnrollmentBootstrap(secure: responder, credential: EnrollmentCredential.issue(card: responder.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer).bytes, trust: trust, now: now)
    }
}

@Test @MainActor func enrollmentBootstrapNeedsPossessionAndCompletedTranscriptBeforePinning() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let hello = try f.userBootstrap.hello()
    let challenge = try f.responderBootstrap.answerHello(hello)
    #expect(f.user.peerCard == nil && f.responder.peerCard == nil)
    let finish = try f.userBootstrap.answerChallenge(challenge)
    #expect(f.user.peerCard == nil && f.responder.peerCard == nil)
    let ready = try f.responderBootstrap.answerFinish(finish)
    #expect(f.responder.peerCard == nil && f.user.peerCard == nil)
    #expect(try f.responderBootstrap.answerFinish(finish) == ready) // lost Ready exact retry
    try f.userBootstrap.acceptReady(ready)
    #expect(f.user.peerCard == nil)
    try f.user.perform(.sos, value: "Synthetic registered SOS")
    let queued = try f.userBootstrap.nextPacket()
    let packet = try #require(queued)
    let receipt = try f.responderBootstrap.acceptApplication(packet)
    try f.userBootstrap.confirm(receipt)
    #expect(f.user.endpoint.snapshot?.state.originalDelivery == .deviceReceived)
    #expect(f.user.peerCard == f.responder.card)
}

@Test @MainActor func enrollmentBootstrapRejectsTranscriptSwapAndStoppedCompletion() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let hello = try f.userBootstrap.hello()
    let challenge = try f.responderBootstrap.answerHello(hello)
    let finish = try f.userBootstrap.answerChallenge(challenge)
    var altered = try EnrollmentWire.decode(EnrollmentBootstrap.Proof.self, finish)
    altered.transcript = Data(repeating: 1, count: 32)
    altered.signature = try f.user.identity.signingKey.signature(for: EnrollmentWire.encode(altered.claims))
    #expect(throws: EnrollmentError.self) { try f.responderBootstrap.answerFinish(EnrollmentWire.encode(altered)) }
    #expect(f.responder.peerCard == nil)
    f.responderBootstrap.stop()
    #expect(throws: EnrollmentError.self) { try f.responderBootstrap.answerFinish(finish) }
    #expect(f.responder.peerCard == nil)
}

@Test @MainActor func enrollmentBootstrapExpiresPendingChallenge() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    var elapsed = 100.0
    f.responderBootstrap.elapsed = { elapsed }
    let challenge = try f.responderBootstrap.answerHello(f.userBootstrap.hello())
    let finish = try f.userBootstrap.answerChallenge(challenge)
    elapsed = 110
    #expect(throws: EnrollmentError.self) { try f.responderBootstrap.answerFinish(finish) }
    #expect(f.responder.peerCard == nil)
}

@Test @MainActor func enrollmentBootstrapRejectsStolenCertificateWithoutPossession() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    var hello = try EnrollmentWire.decode(EnrollmentBootstrap.Proof.self, f.userBootstrap.hello())
    hello.signature = try SecureIdentity(role: .publicUser).signingKey.signature(for: EnrollmentWire.encode(hello.claims))
    #expect(throws: EnrollmentError.self) { try f.responderBootstrap.answerHello(EnrollmentWire.encode(hello)) }
    #expect(f.responder.peerCard == nil)
}

@Test @MainActor func enrollmentBootstrapNeverReplacesSavedPeerAndRejectsStoppedReady() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let hello = try f.userBootstrap.hello()
    let finish = try f.userBootstrap.answerChallenge(f.responderBootstrap.answerHello(hello))
    let ready = try f.responderBootstrap.answerFinish(finish)
    f.userBootstrap.stop()
    #expect(throws: EnrollmentError.self) { try f.userBootstrap.acceptReady(ready) }
    #expect(f.user.peerCard == nil)
    let g = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: g.root) }
    let existing = SecureIdentity(role: .publicUser).card
    try g.responder.pair(existing.base64)
    #expect(throws: EnrollmentError.self) { try g.responderBootstrap.answerHello(g.userBootstrap.hello()) }
    #expect(g.responder.peerCard == existing)
}


@Test @MainActor func enrollmentLostReadyDoesNotPersistResponderPinAndRepeatedHelloUsesOneSlot() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    for _ in 0..<12 { _ = try f.responderBootstrap.answerHello(f.userBootstrap.hello()) }
    let challenge = try f.responderBootstrap.answerHello(f.userBootstrap.hello())
    let finish = try f.userBootstrap.answerChallenge(challenge)
    _ = try f.responderBootstrap.answerFinish(finish)
    #expect(f.responder.peerCard == nil)
    #expect(f.responderBootstrap.pendingCount == 1)
    f.responderBootstrap.stop()
    #expect(f.responder.peerCard == nil)
}


@Test @MainActor func enrollmentIdleReadyExpiresWithoutPersistingEitherPinAndRebootstrapWorks() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    var elapsed = 100.0
    f.userBootstrap.elapsed = { elapsed }; f.responderBootstrap.elapsed = { elapsed }
    let hello = try f.userBootstrap.hello()
    let challenge = try f.responderBootstrap.answerHello(hello)
    let finish = try f.userBootstrap.answerChallenge(challenge)
    let ready = try f.responderBootstrap.answerFinish(finish)
    try f.userBootstrap.acceptReady(ready)
    #expect(try f.responderBootstrap.answerHello(hello) == challenge) // replay must not erase Ready
    elapsed = 110
    try f.user.perform(.sos, value: "Synthetic late request")
    #expect(throws: EnrollmentError.self) { try f.userBootstrap.nextPacket() }
    #expect(f.user.peerCard == nil && f.responder.peerCard == nil)
    let renewed = try f.userBootstrap.answerChallenge(f.responderBootstrap.answerHello(f.userBootstrap.hello()))
    try f.userBootstrap.acceptReady(f.responderBootstrap.answerFinish(renewed))
    let queued = try f.userBootstrap.nextPacket(); let packet = try #require(queued)
    try f.userBootstrap.confirm(f.responderBootstrap.acceptApplication(packet))
    #expect(f.user.peerCard == f.responder.card && f.responder.peerCard == f.user.card)
}

@Test @MainActor func enrollmentConcurrentFinishesRouteProvisionalTrustByAuthenticatedSender() throws {
    let f = try EnrollmentFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    let other = try SecureEndpointController(rootURL: f.root.appendingPathComponent("other"), role: .publicUser, recordStore: EnrollmentTestStore())
    let credential = try EnrollmentCredential.issue(card: other.card, realm: f.realm, notBefore: 100, expires: 200, issuer: f.issuer)
    let otherBootstrap = try EnrollmentBootstrap(secure: other, credential: credential.bytes, trust: f.trust, now: { 150 })
    let finishA = try f.userBootstrap.answerChallenge(f.responderBootstrap.answerHello(f.userBootstrap.hello()))
    let readyA = try f.responderBootstrap.answerFinish(finishA)
    let finishB = try otherBootstrap.answerChallenge(f.responderBootstrap.answerHello(otherBootstrap.hello()))
    _ = try f.responderBootstrap.answerFinish(finishB)
    #expect(try f.responderBootstrap.answerFinish(finishA) == readyA)
    try f.userBootstrap.acceptReady(readyA)
    try f.user.perform(.sos, value: "Synthetic A request")
    let queued = try f.userBootstrap.nextPacket(); let packet = try #require(queued)
    try f.userBootstrap.confirm(f.responderBootstrap.acceptApplication(packet))
    #expect(f.responder.peerCard == f.user.card)
    #expect(other.peerCard == nil)
}


@Test @MainActor func enrolledActiveSessionStopsAuthorizingAtCredentialExpiry() throws {
    var wall: Int64 = 150
    let f = try EnrollmentFixture(now: { wall }); defer { try? FileManager.default.removeItem(at: f.root) }
    let finish = try f.userBootstrap.answerChallenge(f.responderBootstrap.answerHello(f.userBootstrap.hello()))
    try f.userBootstrap.acceptReady(f.responderBootstrap.answerFinish(finish))
    try f.user.perform(.sos, value: "Synthetic expiring session")
    let queued = try f.userBootstrap.nextPacket(); let packet = try #require(queued)
    try f.userBootstrap.confirm(f.responderBootstrap.acceptApplication(packet))
    wall = 200
    #expect(throws: EnrollmentError.self) { try f.userBootstrap.nextPacket() }
    #expect(throws: EnrollmentError.self) { try f.responderBootstrap.acceptApplication(packet) }
    #expect(f.user.peerCard == f.responder.card && f.responder.peerCard == f.user.card)
}
