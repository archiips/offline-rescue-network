import Foundation
import CryptoKit
import SQLite3
import Testing
@testable import RescueDemoState

// Signed relay network checks: real CryptoKit identities, C++ endpoint/cache/relay stores and, where noted,
// real loopback sockets. Record stores are in memory; no Keychain is touched here.

private final class RelayRecordStore: SecureRecordStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ value: Data) throws { data = value }
}

@MainActor private final class TestClock { var now: Int64 = 1_000_000 }

/// Holds an exclusive SQLite lock on a file until released, as another writer would.
private final class FileLock {
    private var db: OpaquePointer?
    init(_ url: URL) throws {
        guard sqlite3_open(url.path, &db) == SQLITE_OK, sqlite3_exec(db, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK else {
            throw RelayError(code: .storage, message: "test lock unavailable")
        }
    }
    func release() { sqlite3_exec(db, "ROLLBACK", nil, nil, nil); sqlite3_close(db); db = nil }
    deinit { if db != nil { release() } }
}

private func randomBytes(_ count: Int) -> Data { Data((0..<count).map { _ in UInt8.random(in: 0...255) }) }

private func flipped(_ data: Data, at index: Int) -> Data {
    var copy = data
    copy[copy.startIndex + index] ^= 0x01
    return copy
}

@MainActor private final class RelayNet {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-relaynet-\(UUID().uuidString)", isDirectory: true)
    let clock = TestClock()
    let publicRecord = RelayRecordStore(), responderRecord = RelayRecordStore()
    var publicSecure: SecureEndpointController
    var responderSecure: SecureEndpointController
    var publicUser: RelayEndpointController
    var responder: RelayEndpointController
    var relay: RelayService
    /// Every ORL1 handed to a destination, in order.
    var delivered: [Data] = []

    init() throws {
        publicSecure = try SecureEndpointController(rootURL: root.appendingPathComponent("public"), role: .publicUser, recordStore: publicRecord)
        responderSecure = try SecureEndpointController(rootURL: root.appendingPathComponent("responder"), role: .responder, recordStore: responderRecord)
        try publicSecure.pair(responderSecure.card.base64)
        try responderSecure.pair(publicSecure.card.base64)
        let clock = clock
        publicUser = RelayEndpointController(secure: publicSecure, clock: { clock.now })
        responder = RelayEndpointController(secure: responderSecure, clock: { clock.now })
        relay = try RelayService(storageURL: root.appendingPathComponent("relay/relay.sqlite"), publicCard: publicSecure.card,
                                 responderCard: responderSecure.card, clock: { clock.now })
    }
    deinit { try? FileManager.default.removeItem(at: root) }

    func restartPublic() throws {
        publicSecure = try SecureEndpointController(rootURL: root.appendingPathComponent("public"), role: .publicUser, recordStore: publicRecord)
        let clock = clock
        publicUser = RelayEndpointController(secure: publicSecure, clock: { clock.now })
    }
    func restartRelay() throws {
        let clock = clock
        relay = try RelayService(storageURL: relay.storageURL, publicCard: publicSecure.card, responderCard: responderSecure.card, clock: { clock.now })
    }
    func upload(_ endpoint: RelayEndpointController) throws -> RelayPacket {
        let packet = try #require(try endpoint.outgoing())
        #expect(try RelayCustodyReceipt.id(from: relay.admit(packet.bytes)) == packet.id)
        return packet
    }
    /// Delivers through the real endpoint adapters; endpoints never see each other directly.
    func flush(drop: Bool = false) async throws -> RelayFlushOutcome {
        try await relay.flush(dropResponse: drop) { [self] bytes, role in
            delivered.append(bytes)
            return try (role == .responder ? responder : publicUser).receive(bytes)
        }
    }
    func pending(_ secure: SecureEndpointController) -> Int { secure.endpoint.snapshot?.pendingTransfers ?? -1 }
    func requests() -> Int { responderSecure.endpoint.snapshot?.state.messages.filter { $0.kind == .request }.count ?? -1 }
    func inspect() throws -> RelayQueue { try RelayQueue(storageURL: relay.storageURL) }
}

private func isFailed(_ outcome: RelayFlushOutcome) -> Bool { if case .failed = outcome { return true }; return false }

// MARK: Wire formats

@MainActor @Test func signedWrapperBoundsAndEveryFieldAreAuthenticated() throws {
    let sender = SecureIdentity(role: .publicUser), recipient = SecureIdentity(role: .responder)
    let envelope = try SecureEnvelope(identity: sender, peer: recipient.card)
    let now: Int64 = 5_000
    let largest = try RelayPacket.make(kind: .event, priority: .urgent, expiry: now + 60, correlation: Data(count: 32),
                                       sealed: try envelope.seal(Data(repeating: 7, count: RelayPacket.maximumEventPlaintext)),
                                       identity: sender, recipient: recipient.card)
    #expect(largest.bytes.count == 4096 && RelayPacket.maximumSize == 4096 && RelayPacket.overhead == 177)
    try largest.verify(from: sender.card, to: recipient.card, now: now)
    #expect(try RelayPacket(bytes: largest.bytes) == largest)
    #expect(largest.id == SHA256.hash(data: largest.bytes).map { String(format: "%02x", $0) }.joined())
    let smallest = try RelayPacket.make(kind: .event, priority: .ordinary, expiry: now + 60, correlation: Data(count: 32),
                                        sealed: try envelope.seal(Data([1])), identity: sender, recipient: recipient.card)
    #expect(smallest.bytes.count == 358)
    #expect(throws: (any Error).self) {
        try RelayPacket.make(kind: .event, priority: .ordinary, expiry: now + 60, correlation: Data(count: 32),
                             sealed: try envelope.seal(Data(repeating: 7, count: RelayPacket.maximumEventPlaintext + 1)),
                             identity: sender, recipient: recipient.card)
    }
    // Every byte position before the ciphertext body, a ciphertext byte and the signature are covered.
    for index in Array(0..<(RelayPacket.overhead - 64)) + [200, smallest.bytes.count - 1] {
        let changed = flipped(smallest.bytes, at: index)
        #expect(throws: (any Error).self, "byte \(index)") {
            try RelayPacket(bytes: changed).verify(from: sender.card, to: recipient.card, now: now)
        }
    }
    #expect(throws: RelayProtocolError.malformed) { try RelayPacket(bytes: smallest.bytes + Data([0])) }
    #expect(throws: RelayProtocolError.malformed) { try RelayPacket(bytes: smallest.bytes.dropLast()) }
    let stranger = SecureIdentity(role: .responder)
    #expect(throws: RelayProtocolError.wrongRecipient) { try smallest.verify(from: sender.card, to: stranger.card, now: now) }
    #expect(throws: RelayProtocolError.wrongSender) { try smallest.verify(from: SecureIdentity(role: .publicUser).card, to: recipient.card, now: now) }
    #expect(throws: RelayProtocolError.expired) { try smallest.verify(from: sender.card, to: recipient.card, now: now + 60) }
    // Signed but outside policy: too far in the future, hops other than 2, nonzero event correlation, urgent receipt.
    func signed(kind: UInt8 = 0, urgency: UInt8 = 0, expiry: Int64 = now + 60, hops: UInt8 = 2, correlation: Data = Data(count: 32),
                inner: Data? = nil, signer: SecureIdentity? = nil) throws -> Data {
        try RelayPacket.encode(kind: kind, urgency: urgency, expiry: expiry, hops: hops, sender: sender.card.digest,
                           recipient: recipient.card.digest, correlation: correlation,
                           sealed: try inner ?? envelope.seal(Data([1])), signer: (signer ?? sender).signingKey)
    }
    #expect(throws: RelayProtocolError.expiryTooFar) {
        try RelayPacket(bytes: try signed(expiry: now + 2 * RelayPacket.maximumLifetime + 1)).verify(from: sender.card, to: recipient.card, now: now)
    }
    #expect(throws: RelayProtocolError.expiryTooFar) {
        // now far in the past: the remaining lifetime overflows Int64 and must not wrap into acceptance.
        try RelayPacket(bytes: try signed()).verify(from: sender.card, to: recipient.card, now: .min)
    }
    #expect(throws: RelayProtocolError.malformed) { try RelayPacket(bytes: try signed(expiry: -1)) }
    #expect(throws: RelayProtocolError.policy) { try RelayPacket(bytes: try signed(hops: 3)) }
    #expect(throws: RelayProtocolError.policy) { try RelayPacket(bytes: try signed(kind: 2)) }
    #expect(throws: RelayProtocolError.policy) { try RelayPacket(bytes: try signed(correlation: randomBytes(32))) }
    #expect(throws: RelayProtocolError.policy) { try RelayPacket(bytes: try signed(kind: 1)) }
    #expect(throws: RelayProtocolError.policy) { try RelayPacket(bytes: try signed(kind: 1, urgency: 1, correlation: randomBytes(32))) }
    #expect(throws: RelayProtocolError.badSignature) {
        try RelayPacket(bytes: try signed(signer: SecureIdentity(role: .publicUser))).verify(from: sender.card, to: recipient.card, now: now)
    }
    // Inner ORS1 must carry the same pins and its own valid signature.
    let foreign = try SecureEnvelope(identity: SecureIdentity(role: .publicUser), peer: recipient.card).seal(Data([1]))
    #expect(throws: RelayProtocolError.innerMismatch) {
        try RelayPacket(bytes: try signed(inner: foreign)).verify(from: sender.card, to: recipient.card, now: now)
    }
    let forgedInner = flipped(try envelope.seal(Data([1])), at: 150)
    #expect(throws: RelayProtocolError.innerMismatch) {
        try RelayPacket(bytes: try signed(inner: forgedInner)).verify(from: sender.card, to: recipient.card, now: now)
    }
}

@MainActor @Test func acceptanceIsBoundToPacketDestinationAndReversedReceipt() throws {
    let origin = SecureIdentity(role: .publicUser), destination = SecureIdentity(role: .responder)
    let forward = try SecureEnvelope(identity: origin, peer: destination.card)
    let reverse = try SecureEnvelope(identity: destination, peer: origin.card)
    let now: Int64 = 100
    let event = try RelayPacket.make(kind: .event, priority: .urgent, expiry: now + 600, correlation: Data(count: 32),
                                     sealed: try forward.seal(Data("event".utf8)), identity: origin, recipient: destination.card)
    let receipt = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: now + 600, correlation: event.digest,
                                       sealed: try reverse.seal(Data(repeating: 3, count: RelayPacket.maximumEventPlaintext)),
                                       identity: destination, recipient: origin.card)
    let accepted = try RelayAcceptance.make(original: event, identity: destination, returning: receipt)
    #expect(accepted.bytes.count == RelayAcceptance.overhead + 4096 && accepted.bytes.count == RelayAcceptance.maximumSize)
    #expect(try RelayAcceptance(bytes: accepted.bytes).verify(original: event, destination: destination.card, origin: origin.card, now: now) == receipt)
    #expect(throws: RelayProtocolError.malformed) { try RelayAcceptance(bytes: accepted.bytes + Data([0])) }
    #expect(throws: (any Error).self) {
        try RelayAcceptance(bytes: flipped(accepted.bytes, at: 40)).verify(original: event, destination: destination.card, origin: origin.card, now: now)
    }
    // Forged signer, another packet's acceptance, and a destination that is not the packet's recipient.
    let forged = try RelayAcceptance.encode(original: event.digest, destination: destination.card.digest, returned: receipt.bytes,
                                        signer: SecureIdentity(role: .responder).signingKey)
    #expect(throws: RelayProtocolError.badSignature) {
        try RelayAcceptance(bytes: forged).verify(original: event, destination: destination.card, origin: origin.card, now: now)
    }
    let other = try RelayPacket.make(kind: .event, priority: .urgent, expiry: now + 600, correlation: Data(count: 32),
                                     sealed: try forward.seal(Data("other".utf8)), identity: origin, recipient: destination.card)
    #expect(throws: RelayProtocolError.wrongPacket) {
        try RelayAcceptance(bytes: accepted.bytes).verify(original: other, destination: destination.card, origin: origin.card, now: now)
    }
    // Event acceptance must return exactly one correlated receipt; receipt acceptance must return none.
    let bare = try RelayAcceptance.make(original: event, identity: destination, returning: nil)
    #expect(throws: RelayProtocolError.returnInvalid) { try bare.verify(original: event, destination: destination.card, origin: origin.card, now: now) }
    let uncorrelated = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: now + 600, correlation: other.digest,
                                            sealed: try reverse.seal(Data("r".utf8)), identity: destination, recipient: origin.card)
    #expect(throws: RelayProtocolError.returnInvalid) {
        try RelayAcceptance.make(original: event, identity: destination, returning: uncorrelated).verify(original: event, destination: destination.card, origin: origin.card, now: now)
    }
    #expect(throws: RelayProtocolError.returnInvalid) {
        try RelayAcceptance.make(original: event, identity: destination, returning: other).verify(original: event, destination: destination.card, origin: origin.card, now: now)
    }
    let shortLived = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: now + 1, correlation: event.digest,
                                          sealed: try reverse.seal(Data("r".utf8)), identity: destination, recipient: origin.card)
    #expect(throws: (any Error).self) {
        try RelayAcceptance.make(original: event, identity: destination, returning: shortLived).verify(original: event, destination: destination.card, origin: origin.card, now: now + 1)
    }
    let receiptAccepted = try RelayAcceptance.make(original: receipt, identity: origin, returning: nil)
    #expect(try receiptAccepted.verify(original: receipt, destination: origin.card, origin: destination.card, now: now) == nil)
    #expect(throws: RelayProtocolError.returnInvalid) {
        try RelayAcceptance.make(original: receipt, identity: origin, returning: event).verify(original: receipt, destination: origin.card, origin: destination.card, now: now)
    }
    let custody = RelayCustodyReceipt.make(event)
    #expect(try custody.count == 36 && custody.prefix(4) == Data("ORC1".utf8) && RelayCustodyReceipt.id(from: custody) == event.id)
    #expect(throws: RelayProtocolError.malformed) { try RelayCustodyReceipt.id(from: custody + Data([0])) }
}

// MARK: Durable endpoint cache

@MainActor @Test func endpointCacheKeepsExactPacketAcrossRestartAndFailsClosed() throws {
    let net = try RelayNet()
    #expect(try net.publicUser.outgoing() == nil)
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let first = try #require(try net.publicUser.outgoing())
    #expect(first.priority == .urgent && first.kind == .event && first.expiry == net.clock.now + RelayPacket.maximumLifetime)
    net.clock.now += 100
    try net.restartPublic()
    #expect(try net.publicUser.outgoing() == first)
    #expect(try net.publicUser.cacheCount() == 1)
    let cacheBytes = try Data(contentsOf: net.publicUser.cacheURL)
    #expect(cacheBytes.range(of: Data("Training Building A".utf8)) == nil)

    // Expired cached mapping fails closed; it is neither removed nor resealed.
    net.clock.now = first.expiry
    #expect(throws: RelayProtocolError.cacheExpired) { try net.publicUser.outgoing() }
    #expect(try net.publicUser.cacheCount() == 1 && net.pending(net.publicSecure) == 1)
    let raw = try #require(try net.publicSecure.endpoint.nextPacket())
    let context = try net.publicSecure.relayContext()
    let id = RelayEndpointController.cacheID(kind: .event, own: context.identity.card, peer: context.peer, raw: raw, correlation: Data(count: 32))
    func saved() throws -> RelayPacket {
        try RelayCacheRecord.open(try #require(try RelayQueue(storageURL: net.publicUser.cacheURL).lookup(id: id)).payload,
                                  mapping: id, owner: context.identity.card)
    }
    #expect(try saved() == first)

    // A later cache write (receipt for a newer inbound event) must not prune the expired pending mapping.
    net.clock.now = first.expiry - 2_000
    _ = try net.responder.receive(first.bytes)
    #expect(try net.responderSecure.perform(.acknowledge))
    let ack = try #require(try net.responder.outgoing())
    net.clock.now = first.expiry + 1
    _ = try RelayAcceptance(bytes: net.publicUser.receive(ack.bytes))
    #expect(try net.publicUser.cacheCount() == 2)
    #expect(try saved() == first)
    #expect(throws: RelayProtocolError.cacheExpired) { try net.publicUser.outgoing() }
}

@MainActor @Test func endpointCacheRejectsWrongContextAndCorruptEntries() throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let raw = try #require(try net.publicSecure.endpoint.nextPacket())
    let (identity, peer, envelope) = try net.publicSecure.relayContext()
    let id = RelayEndpointController.cacheID(kind: .event, own: identity.card, peer: peer, raw: raw, correlation: Data(count: 32))
    #expect(try net.publicUser.cacheCount() == 0) // creates the guarded cache
    let cache = try RelayQueue(storageURL: net.publicUser.cacheURL)
    // A validly signed packet of the wrong kind, in a validly bound record, stored under the event mapping.
    let wrongKind = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: net.clock.now + 600, correlation: randomBytes(32),
                                         sealed: try envelope.seal(raw), identity: identity, recipient: peer)
    #expect(try cache.cacheAdmit(id: id, flow: RelayEndpointController.hex(Data(SHA256.hash(data: raw))), priority: .ordinary,
                                 expiry: wrongKind.expiry, hops: 2,
                                 payload: RelayCacheRecord.seal(wrongKind, mapping: id, identity: identity), now: net.clock.now) == .admitted)
    #expect(throws: RelayProtocolError.cacheMismatch) { try net.publicUser.outgoing() }
    #expect(try cache.count() == 1)

    // A packet for another raw event under a new epoch's mapping: wrong flow binding.
    try net.publicSecure.resetSession()
    try net.responderSecure.resetSession()
    try net.publicSecure.pair(net.responderSecure.card.base64)
    try net.responderSecure.pair(net.publicSecure.card.base64)
    #expect(net.publicUser.cacheURL != cache.storageURL)
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let raw2 = try #require(try net.publicSecure.endpoint.nextPacket())
    let context = try net.publicSecure.relayContext()
    let id2 = RelayEndpointController.cacheID(kind: .event, own: context.identity.card, peer: context.peer, raw: raw2, correlation: Data(count: 32))
    let unrelated = try RelayPacket.make(kind: .event, priority: .urgent, expiry: net.clock.now + 600, correlation: Data(count: 32),
                                         sealed: try context.envelope.seal(Data("unrelated".utf8)), identity: context.identity, recipient: context.peer)
    #expect(try net.publicUser.cacheCount() == 0)
    let fresh = try RelayQueue(storageURL: net.publicUser.cacheURL)
    _ = try fresh.cacheAdmit(id: id2, flow: RelayEndpointController.hex(Data(SHA256.hash(data: raw2))), priority: .urgent,
                             expiry: unrelated.expiry, hops: 2,
                             payload: RelayCacheRecord.seal(unrelated, mapping: id2, identity: context.identity), now: net.clock.now)
    #expect(throws: RelayProtocolError.cacheMismatch) { try net.publicUser.outgoing() }
    // Stale previous-epoch packets are not addressed to the new peer.
    let old = try RelayCacheRecord.open(try #require(try cache.lookup(id: id)).payload, mapping: id, owner: identity.card)
    #expect(throws: (any Error).self) { try net.responder.receive(old.bytes) }
}

// MARK: Relay service

@MainActor @Test func relayCarriesEventReceiptAcknowledgmentAndKeepsOriginPendingUntilReceipt() async throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try net.upload(net.publicUser)
    #expect(try RelayCustodyReceipt.id(from: net.relay.admit(sos.bytes)) == sos.id)
    #expect(try net.relay.count() == 1)
    let relayFile = try Data(contentsOf: net.relay.storageURL)
    #expect(relayFile.range(of: sos.bytes) != nil && relayFile.range(of: Data("Training Building A".utf8)) == nil)
    try net.restartRelay()

    guard case .delivered(let id, 1, let returned?) = try await net.flush() else { Issue.record("SOS not delivered"); return }
    #expect(id == sos.id && net.requests() == 1)
    #expect(net.pending(net.publicSecure) == 1 && net.publicSecure.endpoint.snapshot?.state.originalDelivery == .waiting)
    let receiptItem = try #require(try net.inspect().lookup(id: returned))
    let receipt = try RelayPacket(bytes: receiptItem.payload)
    #expect(receipt.kind == .receipt && receipt.correlation == sos.digest && receipt.priority == .ordinary)
    #expect(try net.relay.count() == 1)

    guard case .delivered(returned, 1, nil) = try await net.flush() else { Issue.record("receipt not delivered"); return }
    #expect(net.pending(net.publicSecure) == 0 && net.publicSecure.endpoint.snapshot?.state.originalDelivery == .deviceReceived)
    // Redelivering the same receipt after pending removal is idempotent through saved history.
    let messages = net.publicSecure.endpoint.snapshot?.state.messages.count
    _ = try RelayAcceptance(bytes: net.publicUser.receive(receipt.bytes)).verify(original: receipt, destination: net.publicSecure.card, origin: net.responderSecure.card, now: net.clock.now)
    #expect(net.pending(net.publicSecure) == 0 && net.publicSecure.endpoint.snapshot?.state.messages.count == messages)

    #expect(try net.responderSecure.perform(.acknowledge))
    let ack = try net.upload(net.responder)
    #expect(ack.priority == .ordinary)
    guard case .delivered(ack.id, 1, _?) = try await net.flush() else { Issue.record("ack not delivered"); return }
    #expect(net.publicSecure.endpoint.snapshot?.state.originalDelivery == .humanAcknowledged && net.pending(net.responderSecure) == 1)
    guard case .delivered(_, 1, nil) = try await net.flush() else { Issue.record("ack receipt not delivered"); return }
    #expect(net.pending(net.responderSecure) == 0 && net.pending(net.publicSecure) == 0)
    #expect(try net.relay.count() == 0)
    #expect(try await net.flush() == .empty)
}

@MainActor @Test func droppedResponseRetriesExactBytesAndCachedReceipt() async throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try net.upload(net.publicUser)
    #expect(try await net.flush(drop: true) == .dropped(id: sos.id, attempts: 1))
    #expect(try net.requests() == 1 && net.pending(net.publicSecure) == 1 && net.relay.count() == 1)
    let firstResponse = try RelayAcceptance(bytes: net.responder.receive(sos.bytes))
    guard case .delivered(sos.id, 2, let returned?) = try await net.flush() else { Issue.record("retry not delivered"); return }
    #expect(net.delivered.count == 2 && net.delivered.allSatisfy { $0 == sos.bytes })
    #expect(net.requests() == 1)
    // The destination's receipt mapping is stable: every acceptance returns the identical ORL1.
    #expect(firstResponse.returned == (try net.inspect().lookup(id: returned))?.payload)
    #expect(try net.responder.cacheCount() == 1)
}

@MainActor @Test func forgedReplayedOrInvalidAcceptanceRetainsCustody() async throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try net.upload(net.publicUser)
    let rogue = SecureIdentity(role: .responder)
    func attempt(_ response: @escaping (Data) throws -> Data) async throws -> RelayFlushOutcome {
        try await net.relay.flush { bytes, _ in try response(bytes) }
    }
    let forged = try RelayAcceptance.encode(original: sos.digest, destination: net.responderSecure.card.digest, returned: nil, signer: rogue.signingKey)
    #expect(isFailed(try await attempt { _ in forged }))
    #expect(isFailed(try await attempt { _ in try RelayAcceptance.make(original: sos, identity: rogue, returning: nil).bytes }))
    #expect(isFailed(try await attempt { _ in RelayCustodyReceipt.make(sos) }))
    // A genuine responder acceptance whose return is not the correlated reverse receipt.
    let responderIdentity = net.responderSecure.identity
    let reverse = try SecureEnvelope(identity: responderIdentity, peer: net.publicSecure.card)
    let wrongReturn = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: net.clock.now + 600, correlation: randomBytes(32),
                                           sealed: try reverse.seal(Data("r".utf8)), identity: responderIdentity, recipient: net.publicSecure.card)
    #expect(isFailed(try await attempt { _ in try RelayAcceptance.make(original: sos, identity: responderIdentity, returning: wrongReturn).bytes }))
    #expect(try net.relay.count() == 1 && net.requests() == 0)
    #expect(try net.inspect().lookup(id: sos.id)?.attempts == 4)

    // Replay a genuine acceptance for the SOS against a later packet.
    let genuine = try net.responder.receive(sos.bytes)
    guard case .delivered = try await attempt({ _ in genuine }) else { Issue.record("genuine acceptance refused"); return }
    #expect(try net.relay.count() == 1)
    _ = try await net.flush() // receipt to public
    #expect(try net.publicSecure.perform(.correction, value: "Training Building A · Floor 4"))
    let correction = try net.upload(net.publicUser)
    #expect(isFailed(try await attempt { _ in genuine }))
    #expect(try net.inspect().lookup(id: correction.id)?.payload == correction.bytes)
}

@MainActor @Test func receiptCorrelationIsEnforcedBeforeConfirmation() throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try #require(try net.publicUser.outgoing())
    let acceptance = try RelayAcceptance(bytes: net.responder.receive(sos.bytes))
    let receipt = try RelayPacket(bytes: try #require(acceptance.returned))
    let raw = try net.publicSecure.relayContext().envelope.open(receipt.sealed)
    let responderIdentity = net.responderSecure.identity
    let reverse = try SecureEnvelope(identity: responderIdentity, peer: net.publicSecure.card)
    let miscorrelated = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: net.clock.now + 600, correlation: randomBytes(32),
                                             sealed: try reverse.seal(raw), identity: responderIdentity, recipient: net.publicSecure.card)
    #expect(throws: RelayProtocolError.correlation) { try net.publicUser.receive(miscorrelated.bytes) }
    #expect(net.pending(net.publicSecure) == 1)
    // An event sent where a receipt is expected, and the endpoint's own packet reflected back, are rejected.
    #expect(throws: (any Error).self) { try net.publicUser.receive(sos.bytes) }
    _ = try net.publicUser.receive(receipt.bytes)
    #expect(net.pending(net.publicSecure) == 0)
    // After confirmation, a different-correlation copy still cannot pass.
    #expect(throws: RelayProtocolError.correlation) { try net.publicUser.receive(miscorrelated.bytes) }
    _ = try net.publicUser.receive(receipt.bytes)
}

@MainActor @Test func storageFailuresLeaveRetrySafeState() async throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try #require(try net.publicUser.outgoing())

    // Custody save fails: nothing admitted, origin unchanged.
    try FileManager.default.createDirectory(at: net.relay.storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let relayLock = try FileLock(net.relay.storageURL)
    #expect(throws: RelayError.self) { try net.relay.admit(sos.bytes) }
    relayLock.release()
    #expect(try net.relay.count() == 0 && net.pending(net.publicSecure) == 1)
    _ = try net.upload(net.publicUser)

    // Destination commits the SOS but cannot save its receipt mapping: no acceptance, custody retained.
    #expect(try net.responder.cacheCount() == 0)
    let cacheLock = try FileLock(net.responder.cacheURL)
    #expect(isFailed(try await net.flush()))
    cacheLock.release()
    #expect(try net.requests() == 1 && net.relay.count() == 1)

    // Reverse receipt cannot be admitted because the relay is full: original retained, not deleted.
    let filler = try net.inspect()
    for n in 1...63 {
        _ = try filler.enqueue(id: String(format: "%064x", n), flow: String(format: "%064x", n), priority: .ordinary,
                               expiry: net.clock.now + 600, hops: 2, payload: randomBytes(400), now: net.clock.now)
    }
    #expect(isFailed(try await net.flush()))
    #expect(try filler.lookup(id: sos.id)?.payload == sos.bytes && net.requests() == 1)
    for n in 1...63 { _ = try filler.remove(id: String(format: "%064x", n)) }

    // Reverse receipt admission fails even with free space (conflicting row under its ID): original still retained.
    let receiptID = try #require(try RelayAcceptance(bytes: net.responder.receive(sos.bytes)).returned.map { try RelayPacket(bytes: $0).id })
    _ = try filler.enqueue(id: receiptID, flow: receiptID, priority: .ordinary, expiry: net.clock.now + 600, hops: 2,
                           payload: randomBytes(400), now: net.clock.now)
    #expect(isFailed(try await net.flush()))
    #expect(try filler.lookup(id: sos.id)?.payload == sos.bytes)
    _ = try filler.remove(id: receiptID)
    guard case .delivered(sos.id, 4, _?) = try await net.flush() else { Issue.record("retry after failures not delivered"); return }
    #expect(net.requests() == 1 && net.pending(net.publicSecure) == 1)
    guard case .delivered(_, 1, nil) = try await net.flush() else { Issue.record("receipt not delivered"); return }
    #expect(net.pending(net.publicSecure) == 0)
}

@MainActor @Test func relayAdmissionRejectsUnpinnedExpiredAndReflectedPackets() throws {
    let net = try RelayNet()
    let stranger = SecureIdentity(role: .publicUser)
    let strangerPacket = try RelayPacket.make(kind: .event, priority: .urgent, expiry: net.clock.now + 600, correlation: Data(count: 32),
                                              sealed: try SecureEnvelope(identity: stranger, peer: net.responderSecure.card).seal(Data([1])),
                                              identity: stranger, recipient: net.responderSecure.card)
    #expect(throws: RelayProtocolError.unknownPeer) { try net.relay.admit(strangerPacket.bytes) }
    let publicIdentity = net.publicSecure.identity
    let selfAddressed = try RelayPacket.encode(kind: 0, urgency: 0, expiry: net.clock.now + 600, hops: 2, sender: publicIdentity.card.digest,
                                           recipient: publicIdentity.card.digest, correlation: Data(count: 32),
                                           sealed: try SecureEnvelope(identity: publicIdentity, peer: net.responderSecure.card).seal(Data([1])),
                                           signer: publicIdentity.signingKey)
    #expect(throws: (any Error).self) { try net.relay.admit(selfAddressed) }
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try #require(try net.publicUser.outgoing())
    net.clock.now = sos.expiry
    #expect(throws: RelayProtocolError.expired) { try net.relay.admit(sos.bytes) }
    #expect(throws: RelayProtocolError.malformed) { try net.relay.admit(Data("ORS1".utf8) + randomBytes(400)) }
    #expect(try net.relay.count() == 0)
    #expect(throws: RelayProtocolError.self) {
        try RelayService(storageURL: net.root.appendingPathComponent("x.sqlite"), publicCard: net.responderSecure.card,
                         responderCard: net.publicSecure.card, clock: { 0 })
    }
}

@MainActor private final class Gate { var continuation: CheckedContinuation<Void, Never>? }

@MainActor @Test func concurrentFlushIsRefusedWhileOneIsAwaitingItsDestination() async throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try net.upload(net.publicUser)
    let gate = Gate()
    let first = Task { @MainActor in
        try await net.relay.flush { bytes, _ in
            await withCheckedContinuation { gate.continuation = $0 }
            return try net.responder.receive(bytes)
        }
    }
    while gate.continuation == nil { await Task.yield() }
    await #expect(throws: RelayProtocolError.busy) { try await net.relay.flush { _, _ in Data() } }
    gate.continuation?.resume()
    guard case .delivered(sos.id, 1, _?) = try await first.value else { Issue.record("serialized flush failed"); return }
}

@MainActor @Test func flushRevalidatesCustodyAfterAwaitingResponse() async throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try net.upload(net.publicUser)
    let outcome = try await net.relay.flush { bytes, _ in
        _ = try net.inspect().remove(id: sos.id) // administrator removes custody during the contact
        return try net.responder.receive(bytes)
    }
    #expect(isFailed(outcome))
    #expect(try net.relay.count() == 0)
}

// MARK: Sockets

@MainActor @Test func relayTransportUsesDistinctServiceAndCarriesFullAcceptanceOverSockets() async throws {
    let plain = LocalExchangeTransport(), secure = LocalExchangeTransport(secure: true)
    let relay = LocalExchangeTransport(relayTimeout: .seconds(5))
    #expect(plain.discoveryType == "_rescue-demo._tcp" && secure.discoveryType == "_rescue-sec._tcp")
    #expect(relay.discoveryType == LocalExchangeTransport.relayServiceType && relay.discoveryType == "_rescue-relay._tcp")
    let peer = LocalExchangeTransport(relayTimeout: .seconds(5))
    let full = Data(repeating: 0x42, count: RelayAcceptance.maximumSize)
    peer.onIncoming = { request in
        #expect(request.count == RelayPacket.maximumSize)
        return full
    }
    try relay.start(name: "Relay sender", advertise: false, browse: false)
    try peer.start(name: "Relay peer", advertise: false, browse: false)
    defer { relay.stop(); peer.stop() }
    let deadline = ContinuousClock.now + .seconds(5)
    while peer.hostPort == nil {
        guard ContinuousClock.now < deadline else { Issue.record("Listener not ready"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
    let response = try await relay.exchange(Data(repeating: 1, count: RelayPacket.maximumSize), to: .hostPort(host: "127.0.0.1", port: try #require(peer.hostPort)))
    #expect(response == full)
}

@MainActor @Test func endpointsAndRelayExchangeOnlyThroughRelaySockets() async throws {
    let net = try RelayNet()
    let relayTransport = LocalExchangeTransport(relayTimeout: .seconds(5))
    let responderTransport = LocalExchangeTransport(relayTimeout: .seconds(5))
    let publicTransport = LocalExchangeTransport(relayTimeout: .seconds(5))
    relayTransport.onIncoming = { try net.relay.admit($0) }
    responderTransport.onIncoming = { try net.responder.receive($0) }
    defer { relayTransport.stop(); responderTransport.stop(); publicTransport.stop() }
    try relayTransport.start(name: "Relay", advertise: false, browse: false)
    try publicTransport.start(name: "Public", advertise: false, browse: false)
    let deadline = ContinuousClock.now + .seconds(5)
    while relayTransport.hostPort == nil || publicTransport.hostPort == nil {
        guard ContinuousClock.now < deadline else { Issue.record("Listener not ready"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try #require(try net.publicUser.outgoing())
    let custody = try await publicTransport.exchange(sos.bytes, to: .hostPort(host: "127.0.0.1", port: try #require(relayTransport.hostPort)))
    #expect(try RelayCustodyReceipt.id(from: custody) == sos.id && net.pending(net.publicSecure) == 1)
    publicTransport.stop() // public leaves before the responder arrives
    try responderTransport.start(name: "Responder", advertise: false, browse: false)
    while responderTransport.hostPort == nil {
        guard ContinuousClock.now < deadline + .seconds(5) else { Issue.record("Responder not ready"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
    let port = try #require(responderTransport.hostPort)
    let outcome = try await net.relay.flush { bytes, role in
        #expect(role == .responder)
        return try await relayTransport.exchange(bytes, to: .hostPort(host: "127.0.0.1", port: port))
    }
    guard case .delivered(sos.id, 1, _?) = outcome else { Issue.record("socket delivery failed: \(outcome)"); return }
    #expect(net.requests() == 1 && net.pending(net.publicSecure) == 1)
}

// MARK: Cache record binding, cache guard and relay metadata

/// Runs one SQL statement against a sample store, binding `blob` to the first parameter when given.
private func execute(_ url: URL, _ sql: String, blob: Data? = nil) throws {
    var db: OpaquePointer?
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK, sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw RelayError(code: .storage, message: "test SQL unavailable")
    }
    defer { sqlite3_finalize(statement) }
    if let blob {
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) == 1 else { throw RelayError(code: .storage, message: "test SQL failed: \(sql)") }
}

@MainActor @Test func legitimateCachedRecordTransplantedToAnotherMappingIsRejected() throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    _ = try net.responder.receive(try #require(try net.publicUser.outgoing()).bytes)
    let context = try net.responderSecure.relayContext()
    func mapping() throws -> String {
        RelayEndpointController.cacheID(kind: .event, own: context.identity.card, peer: context.peer,
                                        raw: try #require(try net.responderSecure.endpoint.nextPacket()), correlation: Data(count: 32))
    }
    #expect(try net.responderSecure.perform(.reply, value: "Team at door A"))
    let first = try #require(try net.responder.outgoing())
    let firstID = try mapping()
    let returned = try #require(try RelayAcceptance(bytes: net.publicUser.receive(first.bytes)).returned)
    _ = try net.responder.receive(returned) // C++ confirms the first reply
    #expect(try net.responderSecure.perform(.reply, value: "Team at door B"))
    let second = try #require(try net.responder.outgoing())
    let secondID = try mapping()
    #expect(second.bytes.count == first.bytes.count && second.expiry == first.expiry && firstID != secondID)
    // Typed-valid unsigned row metadata beside an intact record is not trusted either.
    let secondFlow = try #require(try RelayQueue(storageURL: net.responder.cacheURL).lookup(id: secondID)).flow
    for (change, revert) in [("attempts=1", "attempts=0"), ("flow='\(String(repeating: "0", count: 64))'", "flow='\(secondFlow)'")] {
        try execute(net.responder.cacheURL, "UPDATE relay_items SET \(change) WHERE id='\(secondID)'")
        #expect(throws: RelayProtocolError.cacheMismatch, "\(change)") { try net.responder.outgoing() }
        try execute(net.responder.cacheURL, "UPDATE relay_items SET \(revert) WHERE id='\(secondID)'")
    }
    #expect(try net.responder.outgoing() == second)
    // Copy the intact, legitimately written first record over the second mapping's payload.
    let cache = try RelayQueue(storageURL: net.responder.cacheURL)
    try execute(net.responder.cacheURL, "UPDATE relay_items SET payload=? WHERE id='\(secondID)'",
                blob: try #require(try cache.lookup(id: firstID)).payload)
    #expect(throws: RelayProtocolError.cacheMismatch) { try net.responder.outgoing() }
    #expect(net.pending(net.responderSecure) == 1)
}

@MainActor @Test func receiptMemoForAnotherCorrelationCannotBypassPendingHeadCheck() throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try #require(try net.publicUser.outgoing())
    let receipt = try RelayPacket(bytes: try #require(try RelayAcceptance(bytes: net.responder.receive(sos.bytes)).returned))
    _ = try net.publicUser.receive(receipt.bytes)
    #expect(net.pending(net.publicSecure) == 0)
    let context = try net.publicSecure.relayContext()
    let raw = try context.envelope.open(receipt.sealed)
    let memo = try #require(try RelayQueue(storageURL: net.publicUser.cacheURL).lookup(
        id: RelayEndpointController.receiptMemoID(own: context.identity.card, peer: context.peer, raw: raw, correlation: receipt.correlation)))
    #expect(memo.payload != receipt.bytes) // stored as a bound cache record, not the bare peer packet
    // A genuinely responder-signed copy carrying another correlation, plus a transplanted intact memo under its mapping.
    let responderIdentity = net.responderSecure.identity
    let forged = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: receipt.expiry, correlation: randomBytes(32),
                                      sealed: try SecureEnvelope(identity: responderIdentity, peer: net.publicSecure.card).seal(raw),
                                      identity: responderIdentity, recipient: net.publicSecure.card)
    let forgedID = RelayEndpointController.receiptMemoID(own: context.identity.card, peer: context.peer, raw: raw, correlation: forged.correlation)
    #expect(try RelayQueue(storageURL: net.publicUser.cacheURL).cacheAdmit(id: forgedID, flow: memo.flow, priority: .ordinary, expiry: memo.expiry,
                                                                        hops: 2, payload: memo.payload, now: net.clock.now) == .admitted)
    #expect(throws: RelayProtocolError.cacheMismatch) { try net.publicUser.receive(forged.bytes) }
    // A genuine reseal with the same raw receipt, correlation and expiry is not the packet the memo binds.
    let resealed = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: receipt.expiry, correlation: receipt.correlation,
                                        sealed: try SecureEnvelope(identity: responderIdentity, peer: net.publicSecure.card).seal(raw),
                                        identity: responderIdentity, recipient: net.publicSecure.card)
    #expect(throws: RelayProtocolError.cacheMismatch) { try net.publicUser.receive(resealed.bytes) }
    _ = try net.publicUser.receive(receipt.bytes)
    // A memo whose bound packet differs from the redelivered one is rejected too, not bypassed.
    let memoID = RelayEndpointController.receiptMemoID(own: context.identity.card, peer: context.peer, raw: raw, correlation: receipt.correlation)
    try execute(net.publicUser.cacheURL, "UPDATE relay_items SET expiry=expiry+1 WHERE id='\(memoID)'")
    #expect(throws: RelayProtocolError.cacheMismatch) { try net.publicUser.receive(receipt.bytes) }
}

@MainActor @Test func cacheGuardFailsClosedOnMissingOrMismatchedFilesWithoutRecreatingThem() throws {
    // Guard deleted while the cache remains.
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try #require(try net.publicUser.outgoing())
    let guardURL = net.publicUser.cacheGuardURL
    #expect(FileManager.default.fileExists(atPath: guardURL.path))
    let guardBytes = try Data(contentsOf: guardURL)
    #expect(guardBytes.count == 68 && guardBytes.prefix(4) == Data("ORG1".utf8))
    #expect(guardBytes.range(of: net.publicSecure.card.digest) != nil && guardBytes.range(of: net.responderSecure.card.digest) != nil)
    try FileManager.default.removeItem(at: guardURL)
    try net.restartPublic()
    #expect(throws: RelayProtocolError.cacheGuard) { try net.publicUser.outgoing() }
    #expect(!FileManager.default.fileExists(atPath: guardURL.path))

    // Guard naming another peer.
    try Data(repeating: 0, count: 4096).write(to: guardURL)
    #expect(throws: RelayProtocolError.cacheGuard) { try net.publicUser.outgoing() }
    var other = guardBytes
    other.replaceSubrange(36..<68, with: Data(repeating: 0xab, count: 32))
    try other.write(to: guardURL)
    #expect(throws: RelayProtocolError.cacheGuard) { try net.publicUser.outgoing() }
    try guardBytes.write(to: guardURL)
    #expect(try net.publicUser.outgoing() == sos)

    // Retained handle: a cache deleted underneath it is not silently recreated or written detached.
    try FileManager.default.removeItem(at: net.publicUser.cacheURL)
    #expect(throws: RelayProtocolError.cacheGuard) { try net.publicUser.outgoing() }
    #expect(throws: RelayProtocolError.cacheGuard) { try net.publicUser.receive(sos.bytes) }
    #expect(!FileManager.default.fileExists(atPath: net.publicUser.cacheURL.path))
    // Zero-length cache beside its guard.
    try Data().write(to: net.publicUser.cacheURL)
    try net.restartPublic()
    #expect(throws: RelayProtocolError.cacheGuard) { try net.publicUser.outgoing() }
    #expect(try Data(contentsOf: net.publicUser.cacheURL).isEmpty && net.pending(net.publicSecure) == 1)

    // Explicit new session rotates the epoch and starts a fresh guarded cache.
    net.publicSecure = try SecureEndpointController.newSession(rootURL: net.root.appendingPathComponent("public"), role: .publicUser,
                                                               recordStore: net.publicRecord)
    try net.responderSecure.resetSession()
    try net.publicSecure.pair(net.responderSecure.card.base64)
    try net.responderSecure.pair(net.publicSecure.card.base64)
    let clock = net.clock
    net.publicUser = RelayEndpointController(secure: net.publicSecure, clock: { clock.now })
    #expect(try net.publicUser.outgoing() == nil)
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    #expect(try net.publicUser.outgoing() != nil && net.publicUser.cacheGuardURL != guardURL)
}

@MainActor @Test func unpairedEndpointCreatesNoCacheOrGuard() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-unpaired-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let secure = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: RelayRecordStore())
    let endpoint = RelayEndpointController(secure: secure)
    #expect(throws: SecureExchangeError.notPaired) { try endpoint.outgoing() }
    #expect(throws: SecureExchangeError.notPaired) { try endpoint.cacheCount() }
    #expect(throws: SecureExchangeError.notPaired) { try endpoint.receive(Data(count: 400)) }
    #expect(!FileManager.default.fileExists(atPath: endpoint.cacheURL.path) && !FileManager.default.fileExists(atPath: endpoint.cacheGuardURL.path))
}

@MainActor @Test func flushRefusesRowsWhoseUnsignedMetadataDiffersFromThePacket() async throws {
    let net = try RelayNet()
    #expect(try net.publicSecure.perform(.sos, value: "Training Building A · Floor 1"))
    let sos = try net.upload(net.publicUser)
    let url = net.relay.storageURL
    // Each typed-valid change is reverted after the refused flush; none may reach the destination.
    let tampering = [("urgency=0", "urgency=1"), ("expiry=expiry+1", "expiry=expiry-1"), ("hops=1", "hops=2"),
                     ("flow='\(String(repeating: "0", count: 64))'", "flow='\(RelayService.flow(for: sos))'"),
                     ("id='\(String(repeating: "e", count: 64))'", "id='\(sos.id)'")]
    for (change, revert) in tampering {
        try execute(url, "UPDATE relay_items SET \(change) WHERE id='\(sos.id)'")
        #expect(isFailed(try await net.flush()), "\(change)")
        #expect(net.delivered.isEmpty, "\(change)")
        try execute(url, "UPDATE relay_items SET \(revert) WHERE id='\(change.hasPrefix("id=") ? String(repeating: "e", count: 64) : sos.id)'")
    }
    // Metadata changed while the destination answers: acceptance not used, original retained, no reverse receipt.
    let outcome = try await net.relay.flush { bytes, _ in
        try execute(url, "UPDATE relay_items SET urgency=0 WHERE id='\(sos.id)'")
        return try net.responder.receive(bytes)
    }
    #expect(isFailed(outcome))
    #expect(try net.relay.count() == 1 && net.inspect().lookup(id: sos.id)?.priority == .ordinary)
    try execute(url, "UPDATE relay_items SET urgency=1 WHERE id='\(sos.id)'")
    guard case .delivered(sos.id, 7, _?) = try await net.flush() else { Issue.record("genuine row not delivered"); return }
}
