import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

// Relay custody checks against the real C++ queue and CryptoKit envelopes. Runtime keys only; no Keychain.

private func relayRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("rescue-relay-\(UUID().uuidString)", isDirectory: true)
}

private func hexID(_ n: Int) -> String { String(format: "%064x", n) }

private func opaque(_ count: Int = 181, seed: UInt8 = 1) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: $0) &+ seed }) }

@MainActor private func queue(_ root: URL) throws -> RelayQueue {
    try RelayQueue(storageURL: root.appendingPathComponent("relay.sqlite"))
}

@MainActor @Test func relayQueueReturnsOwnedExactCopiesAcrossHandles() throws {
    let root = relayRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = opaque(4276, seed: 9)
    var relay: RelayQueue? = try queue(root)
    #expect(try relay!.enqueue(id: hexID(1), flow: hexID(2), priority: .urgent, expiry: 100, hops: 2, payload: bytes, now: 0) == .admitted)
    #expect(try relay!.enqueue(id: hexID(1), flow: hexID(2), priority: .urgent, expiry: 100, hops: 2, payload: bytes, now: 1) == .duplicate)
    let item = try #require(try relay!.select(now: 5))
    relay = nil
    // The copy must outlive the C++ handle and its freed allocation.
    #expect(item == RelayItem(id: hexID(1), flow: hexID(2), priority: .urgent, expiry: 100, remainingHops: 1, attempts: 1, payload: bytes))
    let reopened = try queue(root)
    #expect(try reopened.count() == 1)
    let retried = try #require(try reopened.select(now: 6))
    #expect(retried.attempts == 2 && retried.payload == bytes && retried.remainingHops == 1)
    #expect(try reopened.remove(id: hexID(1)))
    #expect(try reopened.remove(id: hexID(1)) == false)
    #expect(try reopened.select(now: 7) == nil)
}

@MainActor @Test func relayQueueReportsTypedErrors() throws {
    let root = relayRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let relay = try queue(root)
    func code(_ body: () throws -> Void) -> RelayError.Code? {
        do { try body(); return nil } catch let error as RelayError { return error.code } catch { return nil }
    }
    #expect(code { _ = try relay.enqueue(id: "ABC", flow: hexID(2), priority: .ordinary, expiry: 10, hops: 1, payload: opaque(), now: 0) } == .invalid)
    #expect(code { _ = try relay.enqueue(id: hexID(1), flow: hexID(2), priority: .ordinary, expiry: 10, hops: 1, payload: opaque(180), now: 0) } == .invalid)
    #expect(code { _ = try relay.enqueue(id: hexID(1), flow: hexID(2), priority: .ordinary, expiry: 10, hops: 3, payload: opaque(), now: 0) } == .invalid)
    #expect(code { _ = try relay.enqueue(id: hexID(1), flow: hexID(2), priority: .ordinary, expiry: 10, hops: 1, payload: opaque(), now: 10) } == .invalid)
    #expect(code { _ = try relay.remove(id: hexID(1) + "\0") } == .invalid)
    _ = try relay.enqueue(id: hexID(1), flow: hexID(2), priority: .ordinary, expiry: 10, hops: 1, payload: opaque(), now: 0)
    #expect(code { _ = try relay.enqueue(id: hexID(1), flow: hexID(2), priority: .ordinary, expiry: 10, hops: 1, payload: opaque(seed: 2), now: 0) } == .conflict)
    for n in 2...64 { _ = try relay.enqueue(id: hexID(n), flow: hexID(n), priority: .ordinary, expiry: 10, hops: 1, payload: opaque(), now: 0) }
    #expect(code { _ = try relay.enqueue(id: hexID(65), flow: hexID(65), priority: .urgent, expiry: 10, hops: 1, payload: opaque(), now: 0) } == .capacity)
    #expect(try relay.count() == 64)

    #expect(code { _ = try RelayQueue(storageURL: URL(string: "https://example.invalid/relay.sqlite")!) } == .invalid)
    #expect(code { _ = try RelayQueue(storageURL: root.appendingPathComponent("folder", isDirectory: true)) } == .invalid)
    let endpointURL = root.appendingPathComponent("endpoint.sqlite")
    let endpoint = EndpointController(storageURL: endpointURL, role: .publicUser)
    #expect(endpoint.snapshot != nil)
    let before = try Data(contentsOf: endpointURL)
    #expect(code { _ = try RelayQueue(storageURL: endpointURL) } == .storage)
    #expect(try Data(contentsOf: endpointURL) == before)
}

@MainActor @Test func relayLookupIsReadOnlyAndCacheAdmissionNeverPrunes() throws {
    let root = relayRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let bytes = opaque(4276, seed: 3)
    var cache: RelayQueue? = try queue(root)
    #expect(try cache!.cacheAdmit(id: hexID(1), flow: hexID(2), priority: .urgent, expiry: 100, hops: 2, payload: bytes, now: 0) == .admitted)
    #expect(try cache!.cacheAdmit(id: hexID(1), flow: hexID(2), priority: .urgent, expiry: 100, hops: 2, payload: bytes, now: 1) == .duplicate)
    cache = nil
    let reopened = try queue(root)
    let hit = try #require(try reopened.lookup(id: hexID(1)))
    #expect(hit == RelayItem(id: hexID(1), flow: hexID(2), priority: .urgent, expiry: 100, remainingHops: 1, attempts: 0, payload: bytes))
    #expect(try reopened.lookup(id: hexID(9)) == nil)
    #expect(throws: RelayError.self) { try reopened.lookup(id: "ABC") }
    #expect(throws: RelayError.self) { try reopened.lookup(id: hexID(1) + "\0") }
    // Past expiry the mapping stays; renewal conflicts instead of pruning and resealing.
    #expect(try reopened.cacheAdmit(id: hexID(3), flow: hexID(4), priority: .ordinary, expiry: 300, hops: 2, payload: opaque(), now: 200) == .admitted)
    #expect(throws: RelayError(code: .conflict, message: "Rejected: a different item already uses this relay ID")) {
        try reopened.cacheAdmit(id: hexID(1), flow: hexID(2), priority: .urgent, expiry: 300, hops: 2, payload: bytes, now: 200)
    }
    #expect(try reopened.count() == 2 && reopened.lookup(id: hexID(1))?.expiry == 100)
}

@MainActor private struct SealedPair {
    let root = relayRoot()
    let publicIdentity = SecureIdentity(role: .publicUser)
    let responderIdentity = SecureIdentity(role: .responder)
    let publicEnvelope: SecureEnvelope
    let responderEnvelope: SecureEnvelope
    let publicUser: EndpointController
    let responder: EndpointController
    let relay: RelayQueue
    init() throws {
        publicEnvelope = try SecureEnvelope(identity: publicIdentity, peer: responderIdentity.card)
        responderEnvelope = try SecureEnvelope(identity: responderIdentity, peer: publicIdentity.card)
        publicUser = EndpointController(storageURL: root.appendingPathComponent("public.sqlite"), role: .publicUser)
        responder = EndpointController(storageURL: root.appendingPathComponent("responder.sqlite"), role: .responder)
        relay = try RelayQueue(storageURL: root.appendingPathComponent("relay.sqlite"))
    }
    func queueSOS() throws -> Data {
        #expect(publicUser.perform(.sos, value: "Training Building A · Floor 1"))
        let sealed = try publicEnvelope.seal(try #require(try publicUser.nextPacket()))
        #expect(try relay.enqueue(id: RelayScenario.sampleID(sealed), flow: hexID(7), priority: .urgent, expiry: 100, hops: 2, payload: sealed, now: 0) == .admitted)
        return sealed
    }
}

@MainActor @Test func relayedLostReceiptRetryDeduplicatesExactCiphertext() throws {
    let pair = try SealedPair()
    defer { try? FileManager.default.removeItem(at: pair.root) }
    let sealed = try pair.queueSOS()
    let first = try #require(try pair.relay.select(now: 10))
    let receipt = try pair.responder.accept(try pair.responderEnvelope.open(first.payload))
    // First sealed receipt is dropped before reaching the relay.
    let retry = try #require(try pair.relay.select(now: 11))
    #expect(retry.payload == sealed && retry.attempts == 2)
    #expect(try pair.responder.accept(try pair.responderEnvelope.open(retry.payload)) == receipt)
    #expect(pair.responder.snapshot?.state.messages.filter { $0.kind == .request }.count == 1)
    #expect(pair.publicUser.snapshot?.pendingTransfers == 1 && pair.publicUser.snapshot?.state.originalDelivery == .waiting)
    // The same ciphertext re-offered under its digest ID stays one custody item.
    #expect(try pair.relay.enqueue(id: RelayScenario.sampleID(sealed), flow: hexID(7), priority: .urgent, expiry: 100, hops: 2, payload: sealed, now: 12) == .duplicate)
    #expect(try pair.relay.count() == 1)
}

@MainActor @Test func relayModifiedCiphertextIsRejectedWithoutMutation() throws {
    let pair = try SealedPair()
    defer { try? FileManager.default.removeItem(at: pair.root) }
    let sealed = try pair.queueSOS()
    let item = try #require(try pair.relay.select(now: 1))
    var tampered = item.payload
    tampered[tampered.startIndex + 150] ^= 0x01
    #expect(throws: SecureExchangeError.badSignature) { try pair.responderEnvelope.open(tampered) }
    #expect(pair.responder.snapshot?.state.hasRequest == false)
    do {
        _ = try pair.relay.enqueue(id: RelayScenario.sampleID(sealed), flow: hexID(7), priority: .urgent, expiry: 100, hops: 2, payload: tampered, now: 2)
        Issue.record("Changed ciphertext under an existing ID must conflict")
    } catch let error as RelayError { #expect(error.code == .conflict) }
    #expect(try pair.relay.select(now: 3)?.payload == sealed)
}

@MainActor @Test func encryptedRelayScenarioSeparatesCustodyDeliveryAndAcknowledgment() throws {
    let root = relayRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let facts = try RelayScenario.run(root: root)
    #expect(facts.map(\.name) == RelayScenario.factNames)
    let files = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    #expect(files == ["public.sqlite", "relay.sqlite", "responder.sqlite"])
    // Reusing a non-empty root would mix stale stores into a supposedly fresh run.
    #expect(throws: RelayScenarioError.self) { try RelayScenario.run(root: root) }
}
