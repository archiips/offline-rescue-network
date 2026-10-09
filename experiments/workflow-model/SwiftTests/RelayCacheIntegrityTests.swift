import Foundation
import SQLite3
import Testing
@testable import RescueDemoState

private final class CacheProbeRecord: SecureRecordStore {
    var bytes: Data?
    func read() throws -> Data? { bytes }
    func write(_ data: Data) throws { bytes = data }
}

@MainActor private func cacheProbe(_ root: URL) throws -> (SecureEndpointController, RelayEndpointController) {
    let sender = try SecureEndpointController(rootURL: root.appendingPathComponent("public"), role: .publicUser, recordStore: CacheProbeRecord())
    let recipient = SecureIdentity(role: .responder)
    try sender.pair(recipient.card.base64)
    _ = try sender.perform(.sos, value: "Training Building A · Floor 1")
    return (sender, RelayEndpointController(secure: sender, clock: { 1000 }))
}

// Parent review probes: equal-length, correctly signed substitution must not pass merely because the
// wrapper has the expected size and the SQLite row still carries the original raw-message hash.
@MainActor @Test func relayCacheRejectsEqualLengthSignedMessageSubstitution() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-cache-probe-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let (secure, endpoint) = try cacheProbe(root)
    let original = try #require(try endpoint.outgoing())
    var raw = try #require(try secure.endpoint.nextPacket())
    let location = try #require(raw.range(of: Data("Training Building A · Floor 1".utf8)))
    raw[location.upperBound - 1] = Character("9").asciiValue!
    let context = try secure.relayContext()
    let substituted = try RelayPacket.make(kind: .event, priority: original.priority, expiry: original.expiry,
                                           correlation: original.correlation, sealed: try context.envelope.seal(raw),
                                           identity: context.identity, recipient: context.peer)
    #expect(substituted.bytes.count == original.bytes.count)
    var db: OpaquePointer?
    #expect(sqlite3_open(endpoint.cacheURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    var statement: OpaquePointer?
    #expect(sqlite3_prepare_v2(db, "UPDATE relay_items SET payload=?", -1, &statement, nil) == SQLITE_OK)
    defer { sqlite3_finalize(statement) }
    let result = substituted.bytes.withUnsafeBytes { buffer -> Int32 in
        sqlite3_bind_blob(statement, 1, buffer.baseAddress, Int32(buffer.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    #expect(result == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE)
    #expect(throws: (any Error).self) { try endpoint.outgoing() }
    #expect(secure.endpoint.snapshot?.pendingTransfers == 1)
}

@MainActor @Test func relayCacheLossFailsClosedInsteadOfResealingPendingMessage() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-cache-loss-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let (secure, first) = try cacheProbe(root)
    _ = try #require(try first.outgoing())
    // A fresh controller models restart; the Keychain/history still exist but the retry cache is lost.
    try FileManager.default.removeItem(at: first.cacheURL)
    let restarted = RelayEndpointController(secure: secure, clock: { 1000 })
    #expect(throws: (any Error).self) { try restarted.outgoing() }
    #expect(secure.endpoint.snapshot?.pendingTransfers == 1)
}
