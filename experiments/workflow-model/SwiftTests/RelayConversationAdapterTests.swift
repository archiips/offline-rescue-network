import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

private final class AdapterRecord: SecureRecordStore {
    var value: Data?
    func read() throws -> Data? { value }
    func write(_ data: Data) throws { value = data }
}
@MainActor private final class AdapterFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-relay-adapter-\(UUID())")
    let publicOwner: SecureEndpointController
    let responderOwner: SecureEndpointController
    let conversation: EndpointController
    var valid = true
    var accepted = 0
    var confirmed = 0
    var receipt = Data()
    init() throws {
        publicOwner = try SecureEndpointController(rootURL: root.appendingPathComponent("public"), role: .publicUser, recordStore: AdapterRecord())
        responderOwner = try SecureEndpointController(rootURL: root.appendingPathComponent("responder"), role: .responder, recordStore: AdapterRecord())
        conversation = EndpointController(storageURL: root.appendingPathComponent("conversation.sqlite"), role: .responder,
            storageBinding: responderOwner.card.fingerprint + ":" + publicOwner.card.fingerprint)
        #expect(try publicOwner.perform(.sos, value: "SYNTHETIC adapter request"))
    }
    func publicAdapter() -> RelayEndpointController {
        RelayEndpointController(owner: publicOwner, endpoint: publicOwner.endpoint, peer: responderOwner.card,
            validate: { if !self.valid { throw EnrollmentError.stopped } },
            acceptPlaintext: { try self.publicOwner.endpoint.accept($0) },
            onConfirmed: { self.confirmed += 1 }, clock: { 1000 })
    }
    func responderAdapter() -> RelayEndpointController {
        RelayEndpointController(owner: responderOwner, endpoint: conversation, peer: publicOwner.card,
            validate: { if !self.valid { throw EnrollmentError.stopped } },
            acceptPlaintext: { self.accepted += 1; self.receipt = try self.conversation.accept($0); return self.receipt },
            onConfirmed: {}, clock: { 1000 })
    }
    deinit { try? FileManager.default.removeItem(at: root) }
}

@Test @MainActor func relayConversationAdapterUsesBoundStoreAndExactRetriesWithoutOwnerPin() throws {
    let f = try AdapterFixture(), publicAdapter = f.publicAdapter(), responderAdapter = f.responderAdapter()
    let event = try #require(try publicAdapter.outgoing())
    #expect(try f.publicAdapter().outgoing() == event)
    let acceptance = try responderAdapter.receive(event.bytes)
    let repeatedAcceptance = try f.responderAdapter().receive(event.bytes)
    let repeatedReceipt = try RelayAcceptance(bytes: repeatedAcceptance).verify(original: event,
        destination: f.responderOwner.card, origin: f.publicOwner.card, now: 1000)
    #expect(f.conversation.snapshot?.state.hasRequest == true)
    #expect(f.responderOwner.endpoint.snapshot?.state.hasRequest == false)
    #expect(f.publicOwner.peerCard == nil && f.responderOwner.peerCard == nil)
    let returned = try #require(try RelayAcceptance(bytes: acceptance).verify(original: event,
        destination: f.responderOwner.card, origin: f.publicOwner.card, now: 1000))
    #expect(repeatedReceipt == returned)
    _ = try publicAdapter.receive(returned.bytes)
    #expect(f.confirmed == 1 && f.publicOwner.endpoint.snapshot?.pendingTransfers == 0)
    #expect(try publicAdapter.outgoing() == nil)
}

@Test @MainActor func relayConversationAdapterValidationPrecedesCacheWritesAndAcceptance() throws {
    let f = try AdapterFixture(), publicAdapter = f.publicAdapter(), responderAdapter = f.responderAdapter()
    let event = try #require(try publicAdapter.outgoing())
    f.valid = false
    #expect(throws: EnrollmentError.stopped) { try responderAdapter.cacheCount() }
    #expect(throws: EnrollmentError.stopped) { try responderAdapter.receive(event.bytes) }
    #expect(throws: EnrollmentError.stopped) { try publicAdapter.outgoing() }
    #expect(!FileManager.default.fileExists(atPath: responderAdapter.cacheURL.path))
    #expect(!FileManager.default.fileExists(atPath: responderAdapter.cacheGuardURL.path))
    #expect(f.accepted == 0 && f.confirmed == 0)
}

@Test @MainActor func relayConversationAdapterRejectsSignedMismatchedReceiptBeforeConfirmationHook() throws {
    let f = try AdapterFixture(), publicAdapter = f.publicAdapter(), responderAdapter = f.responderAdapter()
    let event = try #require(try publicAdapter.outgoing())
    _ = try responderAdapter.receive(event.bytes)
    let identity = try f.responderOwner.enrollmentIdentity()
    let badReceipt = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: 2000,
        correlation: Data(repeating: 7, count: 32),
        sealed: SecureEnvelope(identity: identity, peer: f.publicOwner.card).seal(f.receipt),
        identity: identity, recipient: f.publicOwner.card)
    #expect(throws: RelayProtocolError.correlation) { try publicAdapter.receive(badReceipt.bytes) }
    #expect(f.confirmed == 0 && f.publicOwner.endpoint.snapshot?.pendingTransfers == 1)
}

@Test @MainActor func relayConversationAdapterRejectsTamperingAndLostCache() throws {
    let f = try AdapterFixture(), publicAdapter = f.publicAdapter(), responderAdapter = f.responderAdapter()
    let event = try #require(try publicAdapter.outgoing())
    var tampered = event.bytes; tampered[tampered.count - 1] ^= 1
    #expect(throws: RelayProtocolError.badSignature) { try responderAdapter.receive(tampered) }
    #expect(f.accepted == 0 && f.conversation.snapshot?.state.hasRequest == false)
    try FileManager.default.removeItem(at: publicAdapter.cacheURL)
    #expect(throws: RelayProtocolError.cacheGuard) { try f.publicAdapter().outgoing() }
    #expect(f.confirmed == 0)
}

@Test @MainActor func relayConversationAdapterLegacyInitializerFollowsRotatedEndpoint() throws {
    let f = try AdapterFixture()
    try f.publicOwner.pair(f.responderOwner.card.base64)
    let adapter = RelayEndpointController(secure: f.publicOwner, clock: { 1000 })
    _ = try #require(try adapter.outgoing())
    let oldCache = adapter.cacheURL
    try f.publicOwner.resetSession()
    #expect(throws: SecureExchangeError.notPaired) { try adapter.outgoing() }
    try f.publicOwner.pair(f.responderOwner.card.base64)
    #expect(adapter.cacheURL != oldCache)
    #expect(try adapter.outgoing() == nil)
}

@Test @MainActor func relayConversationAdapterFixedConversationRejectsRotatedOwnerKeys() throws {
    let f = try AdapterFixture(), adapter = f.publicAdapter()
    try f.publicOwner.resetSession()
    #expect(throws: EnrollmentError.wrongIdentity) { try adapter.outgoing() }
    #expect(!FileManager.default.fileExists(atPath: adapter.cacheGuardURL.path))
}
