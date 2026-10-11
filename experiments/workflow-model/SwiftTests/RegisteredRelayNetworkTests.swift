import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

private final class RegisteredNetworkRecord: SecureRecordStore {
    var bytes: Data?
    func read() throws -> Data? { bytes }
    func write(_ data: Data) throws { bytes = data }
}
@MainActor private final class RegisteredNetworkFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-registered-network-\(UUID())")
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let a: SecureEndpointController, b: SecureEndpointController
    let ca: Data, cb: Data
    let trust: EnrollmentTrust
    let service: RegisteredRelayService
    let host: RegisteredRelayHostNetwork
    let publicNetwork: RegisteredRelayEndpointNetwork, responderNetwork: RegisteredRelayEndpointNetwork
    init() throws {
        a = try SecureEndpointController(rootURL: root.appendingPathComponent("public"), role: .publicUser, recordStore: RegisteredNetworkRecord())
        b = try SecureEndpointController(rootURL: root.appendingPathComponent("responder"), role: .responder, recordStore: RegisteredNetworkRecord())
        ca = try EnrollmentCredential.issue(card: a.card, realm: realm, notBefore: 900, expires: 2000, issuer: issuer).bytes
        cb = try EnrollmentCredential.issue(card: b.card, realm: realm, notBefore: 900, expires: 2000, issuer: issuer).bytes
        trust = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 2000)
        service = try RegisteredRelayService(storageURL: root.appendingPathComponent("custody.sqlite"), trust: trust, now: { 1000 })
        let hint = RegisteredRelayRouting.hint(realm: realm, issuer: issuer.publicKey.rawRepresentation)
        host = RegisteredRelayHostNetwork(service: service, routingHint: hint)
        let a = a, b = b, ca = ca, cb = cb, trust = trust
        let ra = RelayEndpointController(owner: a, endpoint: a.endpoint, peer: b.card, validate: {},
            acceptPlaintext: { try a.endpoint.accept($0) }, onConfirmed: {}, clock: { 1000 })
        let rb = RelayEndpointController(owner: b, endpoint: b.endpoint, peer: a.card, validate: {},
            acceptPlaintext: { try b.endpoint.accept($0) }, onConfirmed: {}, clock: { 1000 })
        publicNetwork = RegisteredRelayEndpointNetwork(card: a.card, routingHint: hint,
            answerReadiness: { try RelayReadinessProbe.answer($0, identity: a.enrollmentIdentity()) },
            receive: { bytes in
                let wrapper = try RegisteredRelayPacket(bytes: bytes); _ = try wrapper.authenticate(trust: trust, now: 1000)
                return try ra.receive(wrapper.packet.bytes)
            }, outgoing: { try ra.outgoing().map { [try RegisteredRelayPacket(senderCredential: ca, recipientCredential: cb, packet: $0)] } ?? [] })
        responderNetwork = RegisteredRelayEndpointNetwork(card: b.card, routingHint: hint,
            answerReadiness: { try RelayReadinessProbe.answer($0, identity: b.enrollmentIdentity()) },
            receive: { bytes in
                let wrapper = try RegisteredRelayPacket(bytes: bytes); _ = try wrapper.authenticate(trust: trust, now: 1000)
                return try rb.receive(wrapper.packet.bytes)
            }, outgoing: { try rb.outgoing().map { [try RegisteredRelayPacket(senderCredential: cb, recipientCredential: ca, packet: $0)] } ?? [] })
        #expect(try a.perform(.sos, value: "SYNTHETIC registered relay"))
    }
    func publicNetworkPacket() throws -> RegisteredRelayPacket? {
        let adapter = RelayEndpointController(owner: a, endpoint: a.endpoint, peer: b.card, validate: {},
            acceptPlaintext: { try self.a.endpoint.accept($0) }, onConfirmed: {}, clock: { 1000 })
        return try adapter.outgoing().map { try RegisteredRelayPacket(senderCredential: ca, recipientCredential: cb, packet: $0) }
    }
    func stop() { host.stop(); publicNetwork.stop(); responderNetwork.stop() }
    deinit { try? FileManager.default.removeItem(at: root) }
}
@MainActor private func waitRegistered(_ condition: () throws -> Bool, seconds: Int = 15) async throws {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while try !condition() {
        guard ContinuousClock.now < deadline else { throw EndpointError(message: "Registered relay condition timed out") }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@Test @MainActor func registeredRelayNetworkSequentialContactsKeepCustodySeparateFromReceipt() async throws {
    let f = try RegisteredNetworkFixture(); defer { f.stop() }
    try f.host.start(); try f.publicNetwork.start()
    try await waitRegistered { try f.service.count() == 1 }
    let original = try #require(try f.publicNetworkPacket())
    let queue = try RelayQueue(storageURL: f.service.storageURL)
    #expect(f.a.endpoint.snapshot?.pendingTransfers == 1)
    f.publicNetwork.stop()
    try f.responderNetwork.start()
    try await waitRegistered { f.b.endpoint.snapshot?.state.hasRequest == true }
    try await waitRegistered { try queue.lookup(id: original.packet.id) == nil }
    f.responderNetwork.stop()
    #expect(f.a.endpoint.snapshot?.pendingTransfers == 1)
    try f.publicNetwork.start()
    try await waitRegistered { f.a.endpoint.snapshot?.pendingTransfers == 0 }
    // An exact original retry may have arrived while its reverse receipt was in custody. Returning
    // the responder drains that idempotent retry; origin confirmation was already proved without it.
    try f.responderNetwork.start()
    try await waitRegistered { try f.service.count() == 0 }
    f.host.stop(); f.publicNetwork.stop()
    #expect(!f.host.transport.active && !f.publicNetwork.transport.active)
}

@Test @MainActor func registeredRelayNetworkForgedDestinationCannotConsumeAttemptsAndLaterAuthenticContactWorks() async throws {
    let f = try RegisteredNetworkFixture(); defer { f.stop() }
    try f.host.start(); try f.publicNetwork.start()
    try await waitRegistered { try f.service.count() == 1 }
    let packet = try #require(try f.publicNetworkPacket())
    let queue = try RelayQueue(storageURL: f.service.storageURL)
    let fake = LocalExchangeTransport(registeredRelayTimeout: .seconds(1))
    defer { fake.stop() }
    var probes = 0
    fake.onIncoming = { _ in probes += 1; return Data("forged readiness".utf8) }
    try fake.start(name: "RescueRegRelayEndpoint-\(f.b.card.fingerprint.prefix(16))-00000000", browse: false)
    try await waitRegistered { probes > 0 }
    try await Task.sleep(for: .seconds(18))
    #expect(try queue.lookup(id: packet.packet.id)?.attempts == 0)
    f.publicNetwork.stop()
    try f.responderNetwork.start()
    try await waitRegistered { f.b.endpoint.snapshot?.state.hasRequest == true }
    try await waitRegistered { try queue.lookup(id: packet.packet.id) == nil }
    f.responderNetwork.stop()
    try f.publicNetwork.start()
    try await waitRegistered { f.a.endpoint.snapshot?.pendingTransfers == 0 }
    f.host.stop()
    let stopped = probes
    try await Task.sleep(for: .milliseconds(2300))
    #expect(probes == stopped)
}

@Test @MainActor func registeredRelayNetworkStopAtDestinationCommitPreservesCustodyForRetry() async throws {
    let f = try RegisteredNetworkFixture(); defer { f.stop() }
    try f.host.start(); try f.publicNetwork.start()
    try await waitRegistered { try f.service.count() == 1 }
    let original = try #require(try f.publicNetworkPacket())
    f.publicNetwork.stop()
    let queue = try RelayQueue(storageURL: f.service.storageURL)
    let adapter = RelayEndpointController(owner: f.b, endpoint: f.b.endpoint, peer: f.a.card, validate: {},
        acceptPlaintext: { try f.b.endpoint.accept($0) }, onConfirmed: {}, clock: { 1000 })
    let destination = LocalExchangeTransport(registeredRelayTimeout: .seconds(1))
    defer { destination.stop() }
    destination.onIncoming = { bytes in
        if bytes.starts(with: Data("ORRQ1".utf8)) {
            return try RelayReadinessProbe.answer(bytes, identity: f.b.enrollmentIdentity())
        }
        let wrapper = try RegisteredRelayPacket(bytes: bytes)
        _ = try wrapper.authenticate(trust: f.trust, now: 1000)
        let result = try adapter.receive(wrapper.packet.bytes)
        f.host.stop() // Destination committed, but the host's awaited response has not resumed.
        return result
    }
    try destination.start(name: "RescueRegRelayEndpoint-\(f.b.card.fingerprint.prefix(16))-00000000", browse: false)
    try await waitRegistered { !f.host.transport.active }
    #expect(f.b.endpoint.snapshot?.state.hasRequest == true)
    #expect(f.a.endpoint.snapshot?.pendingTransfers == 1)
    #expect(try queue.lookup(id: original.packet.id)?.payload == original.bytes)
    #expect(try f.service.count() == 1)
    destination.stop()
    try f.host.start(); try f.responderNetwork.start()
    try await waitRegistered { try queue.lookup(id: original.packet.id) == nil }
    f.responderNetwork.stop(); try f.publicNetwork.start()
    try await waitRegistered { f.a.endpoint.snapshot?.pendingTransfers == 0 }
    #expect(f.b.endpoint.snapshot?.state.messages.filter { $0.kind == .request }.count == 1)
}
