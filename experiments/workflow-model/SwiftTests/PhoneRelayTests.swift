import Foundation
import Combine
import Network
import SQLite3
import Testing
@testable import RescueDemoState

private final class PhoneRecord: SecureRecordStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ value: Data) throws { data = value }
}
/// Two paired relay-route endpoints plus a separate host root; endpoints and host share no files.
@MainActor private final class PhoneNet {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-phone-relay-\(UUID())")
    var hostRoot: URL { root.appendingPathComponent("host", isDirectory: true) }
    let aRecord = PhoneRecord(), bRecord = PhoneRecord()
    let a: DemoController, b: DemoController
    init() throws {
        a = DemoController(storageURL: root.appendingPathComponent("a/session.sqlite"))
        b = DemoController(storageURL: root.appendingPathComponent("b/session.sqlite"))
        a.useSecureRole(.publicUser, recordStore: aRecord, viaRelay: true)
        b.useSecureRole(.responder, recordStore: bRecord, viaRelay: true)
        #expect(a.pairSecurePeer(try #require(b.secureCard).base64))
        #expect(b.pairSecurePeer(try #require(a.secureCard).base64))
    }
    var publicCard: String { a.secureCard?.base64 ?? "" }
    var responderCard: String { b.secureCard?.base64 ?? "" }
    func stop() { a.stopLocalExchange(); b.stopLocalExchange() }
    deinit { try? FileManager.default.removeItem(at: root) }
}
@MainActor private func ready(_ transport: LocalExchangeTransport) async throws -> UInt16 {
    let deadline = ContinuousClock.now + .seconds(5)
    while transport.hostPort == nil {
        guard transport.active, ContinuousClock.now < deadline else { throw EndpointError(message: "listener not ready: \(transport.status)") }
        try await Task.sleep(for: .milliseconds(10))
    }
    return try #require(transport.hostPort).rawValue
}
private func files(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
}
/// Configures and starts a host, then uploads one SOS from the public endpoint into its custody.
@MainActor private func hostWithSOS(_ net: PhoneNet) async throws -> (NativeRelayHostController, UInt16) {
    let host = NativeRelayHostController(rootURL: net.hostRoot)
    #expect(host.configure(publicCard: net.publicCard, responderCard: net.responderCard))
    host.start()
    let port = try await ready(host.transport)
    net.a.perform(.sos, value: "SYNTHETIC floor 1")
    net.a.startLocalExchange(); _ = try await ready(net.a.transport)
    await net.a.uploadViaRelay(host: "127.0.0.1", port: String(port))
    #expect(net.a.error.isEmpty && host.custodyCount == 1)
    return (host, port)
}
@MainActor private func onlyItem(_ host: NativeRelayHostController) throws -> RelayItem {
    let id = NativeRelayHostController.profileID(publicCard: try #require(host.publicCard), responderCard: try #require(host.responderCard))
    let url = host.rootURL.appendingPathComponent("\(id).sqlite")
    // Read the single row ID without select(), which would commit an attempt.
    var db: OpaquePointer?, statement: OpaquePointer?
    defer { sqlite3_finalize(statement); sqlite3_close(db) }
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
          sqlite3_prepare_v2(db, "SELECT id FROM relay_items", -1, &statement, nil) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
        throw RelayError(code: .storage, message: "test SQL unavailable")
    }
    let rowID = String(cString: text)
    #expect(sqlite3_step(statement) == SQLITE_DONE)
    return try #require(try RelayQueue(storageURL: url).lookup(id: rowID))
}

@Test @MainActor func phoneRelayRejectsInvalidCardsWithoutWrites() throws {
    let net = try PhoneNet(); defer { net.stop() }
    let host = NativeRelayHostController(rootURL: net.hostRoot)
    #expect(!host.configured && !FileManager.default.fileExists(atPath: net.hostRoot.path))
    let other = SecureIdentity(role: .publicUser).card.base64
    for (p, r) in [("", ""), ("not a card", net.responderCard), (net.responderCard, net.publicCard),
                   (net.publicCard, other), (net.publicCard, net.publicCard), (net.responderCard, net.responderCard)] {
        #expect(!host.configure(publicCard: p, responderCard: r))
        #expect(!host.error.isEmpty && !host.configured && host.publicCard == nil)
    }
    #expect(!FileManager.default.fileExists(atPath: net.hostRoot.path))
    host.start()
    #expect(!host.transport.active)
    // A rejected draft keeps the existing pair and changes no file.
    #expect(host.configure(publicCard: net.publicCard, responderCard: net.responderCard))
    let saved = files(net.hostRoot)
    #expect(!host.configure(publicCard: net.responderCard, responderCard: net.publicCard))
    #expect(host.configured && host.publicCard == net.a.secureCard && !host.error.isEmpty && files(net.hostRoot) == saved)
}

@Test @MainActor func phoneRelayReopensStoppedWithCustodyRetained() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let (host, _) = try await hostWithSOS(net)
    let held = try onlyItem(host)
    host.stop()
    #expect(!host.transport.active && host.custodyCount == 1 && host.configured)
    let reopened = NativeRelayHostController(rootURL: net.hostRoot)
    #expect(reopened.configured && reopened.error.isEmpty && !reopened.transport.active)
    #expect(reopened.publicCard == net.a.secureCard && reopened.responderCard == net.b.secureCard)
    let reopenedItem = try onlyItem(reopened)
    #expect(reopened.custodyCount == 1 && reopenedItem == held)
    let text = try String(contentsOf: net.hostRoot.appendingPathComponent("active.json"), encoding: .utf8)
        + files(net.hostRoot).filter { $0.hasSuffix(".json") }.map { (try? String(contentsOf: net.hostRoot.appendingPathComponent($0), encoding: .utf8)) ?? "" }.joined()
    #expect(!text.contains("SYNTHETIC") && !text.lowercased().contains("private"))
}

@Test @MainActor func phoneRelayProfileChangePreservesEarlierCustody() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let (host, _) = try await hostWithSOS(net)
    let otherPublic = SecureIdentity(role: .publicUser).card, otherResponder = SecureIdentity(role: .responder).card
    #expect(host.configure(publicCard: otherPublic.base64, responderCard: otherResponder.base64))
    #expect(!host.transport.active && host.custodyCount == 0 && host.publicCard == otherPublic)
    #expect(files(net.hostRoot).filter { $0.hasSuffix(".sqlite") }.count == 2)
    #expect(NativeRelayHostController(rootURL: net.hostRoot).publicCard == otherPublic)
    #expect(host.configure(publicCard: net.publicCard, responderCard: net.responderCard))
    #expect(host.custodyCount == 1 && host.publicCard == net.a.secureCard)
    let reopened = NativeRelayHostController(rootURL: net.hostRoot)
    #expect(reopened.custodyCount == 1 && reopened.publicCard == net.a.secureCard)
}

@Test @MainActor func phoneRelayMissingOrCorruptProfileFailsClosed() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let (host, _) = try await hostWithSOS(net)
    host.stop()
    let id = NativeRelayHostController.profileID(publicCard: try #require(net.a.secureCard), responderCard: try #require(net.b.secureCard))
    let profile = net.hostRoot.appendingPathComponent("\(id).json"), queue = net.hostRoot.appendingPathComponent("\(id).sqlite")
    let pointer = net.hostRoot.appendingPathComponent("active.json")
    let savedProfile = try Data(contentsOf: profile), savedPointer = try Data(contentsOf: pointer)
    func failsClosed(_ note: Comment) {
        let reopened = NativeRelayHostController(rootURL: net.hostRoot)
        #expect(!reopened.configured && !reopened.error.isEmpty && reopened.publicCard == nil, note)
        reopened.start()
        #expect(!reopened.transport.active, note)
    }
    // Corrupt profile and a profile whose cards do not hash to its name.
    try Data("{".utf8).write(to: profile)
    failsClosed("corrupt profile")
    #expect(!host.configure(publicCard: net.publicCard, responderCard: net.responderCard) && !host.configured)
    let other = try JSONSerialization.data(withJSONObject: ["version": 1, "publicCard": SecureIdentity(role: .publicUser).card.base64,
                                                            "responderCard": net.responderCard])
    try other.write(to: profile)
    failsClosed("mismatched profile")
    // A symlinked profile is not trusted even when its target is valid.
    try FileManager.default.removeItem(at: profile)
    let elsewhere = net.root.appendingPathComponent("copy.json")
    try savedProfile.write(to: elsewhere)
    try FileManager.default.createSymbolicLink(at: profile, withDestinationURL: elsewhere)
    failsClosed("symlinked profile")
    try FileManager.default.removeItem(at: profile)
    // An orphan queue without its profile is never adopted.
    failsClosed("missing profile")
    #expect(!host.configure(publicCard: net.publicCard, responderCard: net.responderCard) && !host.configured)
    #expect(!FileManager.default.fileExists(atPath: profile.path) && FileManager.default.fileExists(atPath: queue.path))
    try savedProfile.write(to: profile)
    // Missing pointer while profiles exist: fail on open; explicit configure recovers the valid profile.
    try FileManager.default.removeItem(at: pointer)
    failsClosed("missing pointer")
    let recovered = NativeRelayHostController(rootURL: net.hostRoot)
    #expect(recovered.configure(publicCard: net.publicCard, responderCard: net.responderCard) && recovered.custodyCount == 1)
    #expect(try Data(contentsOf: pointer) == savedPointer)
    try Data("garbage".utf8).write(to: pointer)
    failsClosed("corrupt pointer")
    try savedPointer.write(to: pointer)
    // Missing queue is never recreated, on open or on configure.
    let moved = net.root.appendingPathComponent("moved.sqlite")
    try FileManager.default.moveItem(at: queue, to: moved)
    failsClosed("missing queue")
    #expect(!host.configure(publicCard: net.publicCard, responderCard: net.responderCard) && !host.configured)
    #expect(!FileManager.default.fileExists(atPath: queue.path))
    try FileManager.default.moveItem(at: moved, to: queue)
    #expect(NativeRelayHostController(rootURL: net.hostRoot).custodyCount == 1)
}

@Test @MainActor func phoneRelayStrictAddressesDoNotConsumeAttempt() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let (host, _) = try await hostWithSOS(net)
    defer { host.stop() }
    for (host1, port1, host2, port2) in [("", "3", "127.0.0.1", "3"), ("a b", "3", "127.0.0.1", "3"),
                                         ("127.0.0.1", "3", "127.0.0.1", "0"), ("127.0.0.1", "65536", "127.0.0.1", "3"),
                                         ("127.0.0.1", "+80", "127.0.0.1", "3"), ("127.0.0.1", "3", "x\ty", "3"),
                                         (String(repeating: "x", count: 254), "3", "127.0.0.1", "3"), ("127.0.0.1", "3", "127.0.0.1", "2.0")] {
        await host.flushOne(publicHost: host1, publicPort: port1, responderHost: host2, responderPort: port2)
        #expect(!host.error.isEmpty && !host.flushBusy)
    }
    host.stop()
    await host.flushOne(publicHost: "127.0.0.1", publicPort: "3", responderHost: "127.0.0.1", responderPort: "4")
    #expect(!host.error.isEmpty)
    #expect(try onlyItem(host).attempts == 0 && host.custodyCount == 1)
}

@Test @MainActor func phoneRelayCarriesSOSReceiptAcknowledgmentAndReplyOverSockets() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let (host, port) = try await hostWithSOS(net)
    defer { host.stop() }
    net.b.startLocalExchange()
    let aPort = String(try await ready(net.a.transport)), bPort = String(try await ready(net.b.transport))
    func forward() async { await host.flushOne(publicHost: "127.0.0.1", publicPort: aPort, responderHost: "127.0.0.1", responderPort: bPort) }
    await forward()
    #expect(host.error.isEmpty && host.custodyCount == 1 && !host.status.isEmpty)
    #expect(net.b.snapshot?.responderState.hasRequest == true)
    #expect(net.a.snapshot?.publicState.originalDelivery == .waiting)
    await forward()
    #expect(host.error.isEmpty && host.custodyCount == 0)
    #expect(net.a.snapshot?.publicState.originalDelivery == .deviceReceived && net.a.snapshot?.pendingTransfers == 0)
    for action in [DemoAction.acknowledge, .reply] {
        net.b.perform(action, value: action == .reply ? "SYNTHETIC team reviewing" : "")
        await net.b.uploadViaRelay(host: "127.0.0.1", port: String(port))
        #expect(net.b.error.isEmpty && host.custodyCount == 1)
        await forward(); await forward()
        #expect(host.error.isEmpty && host.custodyCount == 0)
    }
    await forward()
    #expect(host.error.isEmpty && host.custodyCount == 0)
    #expect(net.a.snapshot?.publicState.originalDelivery == .humanAcknowledged)
    #expect(net.a.snapshot?.publicState.messages.contains { $0.kind == .reply && $0.text == "SYNTHETIC team reviewing" } == true)
    #expect(net.b.snapshot?.pendingTransfers == 0)
}

@Test @MainActor func phoneRelayWrongDestinationKeepsCustody() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let (host, _) = try await hostWithSOS(net)
    defer { host.stop() }
    let held = try onlyItem(host)
    net.b.startLocalExchange()
    let aPort = String(try await ready(net.a.transport)), bPort = String(try await ready(net.b.transport))
    // Swapped contacts: the public endpoint rejects a packet addressed to the responder.
    await host.flushOne(publicHost: "127.0.0.1", publicPort: bPort, responderHost: "127.0.0.1", responderPort: aPort)
    #expect(!host.error.isEmpty && host.custodyCount == 1 && !host.flushBusy)
    #expect(net.b.snapshot?.responderState.hasRequest == false)
    let after = try onlyItem(host)
    #expect(after.payload == held.payload && after.attempts == 1)
    await host.flushOne(publicHost: "127.0.0.1", publicPort: aPort, responderHost: "127.0.0.1", responderPort: bPort)
    #expect(host.error.isEmpty && net.b.snapshot?.responderState.hasRequest == true)
}

@Test @MainActor func phoneRelayStopDuringForwardKeepsExactBytesAndRetryRecovers() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let (host, _) = try await hostWithSOS(net)
    defer { host.stop() }
    let held = try onlyItem(host)
    net.b.startLocalExchange()
    let aPort = String(try await ready(net.a.transport)), bPort = String(try await ready(net.b.transport))
    var armed = true, busyDuringStop = false, configureDuringStop = true
    // Stops exactly when the destination's acceptance has arrived, before the awaiting forward resumes.
    let watch = host.transport.$status.sink { value in
        MainActor.assumeIsolated {
            guard armed, value == "Peer response received" else { return }
            armed = false
            host.stop()
            busyDuringStop = host.flushBusy
            configureDuringStop = host.configure(publicCard: net.publicCard, responderCard: net.responderCard)
        }
    }
    defer { watch.cancel() }
    await host.flushOne(publicHost: "127.0.0.1", publicPort: aPort, responderHost: "127.0.0.1", responderPort: bPort)
    #expect(!armed && busyDuringStop && !configureDuringStop)
    #expect(net.b.snapshot?.responderState.hasRequest == true) // the device committed; the relay never saw it
    #expect(!host.transport.active && !host.flushBusy && host.custodyCount == 1)
    #expect(!host.status.lowercased().contains("accepted") && !host.status.lowercased().contains("delivered"))
    let after = try onlyItem(host)
    #expect(after.id == held.id && after.payload == held.payload)
    // The next explicit retry gets the destination's idempotent acceptance and its reverse receipt.
    host.start(); _ = try await ready(host.transport)
    await host.flushOne(publicHost: "127.0.0.1", publicPort: aPort, responderHost: "127.0.0.1", responderPort: bPort)
    #expect(host.error.isEmpty && host.custodyCount == 1)
    let receiptItem = try onlyItem(host)
    #expect(receiptItem.id != held.id)
    await host.flushOne(publicHost: "127.0.0.1", publicPort: aPort, responderHost: "127.0.0.1", responderPort: bPort)
    #expect(host.custodyCount == 0 && net.a.snapshot?.publicState.originalDelivery == .deviceReceived)
}

@Test @MainActor func phoneRelayNonFileRootIsExplicitlyRejected() {
    let root = URL(string: "https://example.invalid/no-local-relay-\(UUID())")!
    let host = NativeRelayHostController(rootURL: root)
    #expect(!host.configured && !host.transport.active && !host.error.isEmpty)
    #expect(!host.configure(publicCard: SecureIdentity(role: .publicUser).card.base64,
                            responderCard: SecureIdentity(role: .responder).card.base64))
    #expect(!host.configured)
}

@Test @MainActor func phoneRelayFailedListenerNeverClaimsListening() async throws {
    let net = try PhoneNet(); defer { net.stop() }
    let occupied = LocalExchangeTransport(relayTimeout: .seconds(2)); defer { occupied.stop() }
    try occupied.start(name: "OccupiedRelayPort", advertise: false, browse: false)
    let port = try await ready(occupied)
    let host = NativeRelayHostController(rootURL: net.hostRoot)
    defer { host.stop() }
    #expect(host.configure(publicCard: net.publicCard, responderCard: net.responderCard))
    host.start(port: port)
    let deadline = ContinuousClock.now + .seconds(5)
    while host.transport.active {
        guard ContinuousClock.now < deadline else { Issue.record("Occupied listener did not fail"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(!host.status.lowercased().contains("listening"))
    #expect(host.transport.status.contains("failed"))
}
