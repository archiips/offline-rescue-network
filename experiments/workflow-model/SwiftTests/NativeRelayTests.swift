import Foundation
import Network
import Testing
@testable import RescueDemoState

private final class NativeRecord: SecureRecordStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ value: Data) throws { data = value }
}
@MainActor private final class NativePair {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-native-relay-\(UUID())")
    let aRecord = NativeRecord(), bRecord = NativeRecord()
    let a: DemoController, b: DemoController
    init() throws {
        a = DemoController(storageURL: root.appendingPathComponent("a/session.sqlite"))
        b = DemoController(storageURL: root.appendingPathComponent("b/session.sqlite"))
        a.useSecureRole(.publicUser, recordStore: aRecord, viaRelay: true)
        b.useSecureRole(.responder, recordStore: bRecord, viaRelay: true)
        #expect(a.pairSecurePeer(try #require(b.secureCard).base64))
        #expect(b.pairSecurePeer(try #require(a.secureCard).base64))
    }
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
private func address(_ port: UInt16) -> NWEndpoint { .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!) }

@Test @MainActor func nativeRelayRouteKeepsIdentityAndSavedWorkflow() throws {
    let pair = try NativePair(); defer { pair.stop() }
    pair.a.perform(.sos, value: "SYNTHETIC floor 1")
    let card = pair.a.secureCard
    pair.a.useRelayRoute(false)
    #expect(!pair.a.relayMode && pair.a.secureMode)
    #expect(pair.a.secureCard == card && pair.a.snapshot?.pendingTransfers == 1)
    #expect(pair.a.transport.discoveryType == "_rescue-sec._tcp")
    pair.a.useRelayRoute(true)
    #expect(pair.a.relayMode && pair.a.transport.discoveryType == "_rescue-relay._tcp")
    #expect(pair.a.snapshot?.publicState.reportedLocation == "SYNTHETIC floor 1")
    pair.a.retrySavedSession()
    #expect(pair.a.relayMode && !pair.a.transport.active && pair.a.secureCard == card)
    pair.a.reset()
    #expect(pair.a.relayMode && pair.a.secureCard != card && pair.a.pairedCard == nil)
    #expect(pair.a.snapshot?.pendingTransfers == 0)
    pair.a.startLocalExchange()
    #expect(!pair.a.transport.active && !pair.a.error.isEmpty)
    pair.a.useTraining()
    #expect(!pair.a.relayMode && !pair.a.secureMode)
}

@Test @MainActor func nativeRelayRejectsInvalidAddressesBeforeAnyUpload() async throws {
    let pair = try NativePair(); defer { pair.stop() }
    pair.a.perform(.sos, value: "SYNTHETIC")
    pair.a.startLocalExchange(); _ = try await ready(pair.a.transport)
    for (host, port) in [("", "3"), ("a b", "3"), ("a\n", "0"), (String(repeating: "x", count: 254), "3"),
                         ("127.0.0.1", "0"), ("localhost", "65536"), ("localhost", "+80"), ("localhost", "2.0")] {
        await pair.a.uploadViaRelay(host: host, port: port)
        #expect(!pair.a.error.isEmpty && !pair.a.exchangeBusy)
        #expect(pair.a.snapshot?.pendingTransfers == 1 && pair.a.snapshot?.publicState.originalDelivery == .waiting)
    }
}

@Test @MainActor func nativeRelayCustodyNeverConfirmsAndRetriesExactBytes() async throws {
    let pair = try NativePair(); defer { pair.stop() }
    let server = LocalExchangeTransport(relayTimeout: .seconds(2)); defer { server.stop() }
    var packets: [Data] = []
    var wrong = true
    server.onIncoming = { bytes in
        packets.append(bytes)
        return wrong ? Data("ORC1".utf8) + Data(count: 32) : RelayCustodyReceipt.make(try RelayPacket(bytes: bytes))
    }
    try server.start(name: "NativeCustodyTest", advertise: false, browse: false)
    let port = try await ready(server)
    pair.a.perform(.sos, value: "SYNTHETIC floor 1")
    pair.a.startLocalExchange(); _ = try await ready(pair.a.transport)
    await pair.a.uploadViaRelay(host: "127.0.0.1", port: String(port))
    #expect(!pair.a.error.isEmpty && pair.a.snapshot?.pendingTransfers == 1)
    wrong = false
    await pair.a.uploadViaRelay(host: " 127.0.0.1 ", port: String(port))
    #expect(pair.a.error.isEmpty && !pair.a.exchangeBusy)
    #expect(pair.a.snapshot?.pendingTransfers == 1 && pair.a.snapshot?.publicState.originalDelivery == .waiting)
    #expect(packets.count == 2 && packets[0] == packets[1])
    #expect(!pair.a.relayStatus.isEmpty)
    // A new action must not automatically upload through an old direct peer.
    pair.a.perform(.correction, value: "SYNTHETIC floor 2")
    try await Task.sleep(for: .milliseconds(40))
    #expect(packets.count == 2)
    await pair.a.transferQueued(to: address(port))
    #expect(packets.count == 2 && pair.a.snapshot?.pendingTransfers == 2)
    pair.a.stopLocalExchange()
    #expect(!pair.a.exchangeBusy && pair.a.relayStatus.isEmpty)
}

@Test @MainActor func nativeRelayRouteSwitchInvalidatesAwaitedCustody() async throws {
    let pair = try NativePair(); defer { pair.stop() }
    let server = LocalExchangeTransport(relayTimeout: .seconds(2)); defer { server.stop() }
    var incoming = 0
    server.onIncoming = { bytes in
        incoming += 1
        pair.a.useRelayRoute(false) // changes route while exchange awaits its response
        return RelayCustodyReceipt.make(try RelayPacket(bytes: bytes))
    }
    try server.start(name: "NativeRouteTest", advertise: false, browse: false)
    let port = try await ready(server)
    pair.a.perform(.sos, value: "SYNTHETIC")
    pair.a.startLocalExchange(); _ = try await ready(pair.a.transport)
    await pair.a.uploadViaRelay(host: "127.0.0.1", port: String(port))
    #expect(incoming == 1 && !pair.a.relayMode && !pair.a.transport.active && !pair.a.exchangeBusy)
    #expect(pair.a.error.isEmpty && pair.a.relayStatus.isEmpty && pair.a.snapshot?.pendingTransfers == 1)
}

@Test @MainActor func nativeRelayDelayedReceiptsAndHumanAcknowledgmentOverSockets() async throws {
    let pair = try NativePair(); defer { pair.stop() }
    let service = try RelayService(storageURL: pair.root.appendingPathComponent("relay.sqlite"),
        publicCard: #require(pair.a.secureCard), responderCard: #require(pair.b.secureCard))
    let server = LocalExchangeTransport(relayTimeout: .seconds(2)); defer { server.stop() }
    server.onIncoming = { try service.admit($0) }
    try server.start(name: "NativeRoundtripTest", advertise: false, browse: false)
    let port = try await ready(server)
    pair.a.startLocalExchange(); let aPort = try await ready(pair.a.transport)
    pair.a.perform(.sos, value: "SYNTHETIC floor 1")
    await pair.a.uploadViaRelay(host: "127.0.0.1", port: String(port))
    pair.a.stopLocalExchange()
    pair.b.startLocalExchange(); let bPort = try await ready(pair.b.transport)
    let first = try await service.flush { bytes, role in
        #expect(role == .responder)
        return try await server.exchange(bytes, to: address(bPort))
    }
    guard case .delivered = first else { Issue.record("SOS did not reach responder"); return }
    #expect(pair.b.snapshot?.responderState.hasRequest == true)
    #expect(pair.a.snapshot?.publicState.originalDelivery == .waiting && pair.a.snapshot?.pendingTransfers == 1)
    pair.b.stopLocalExchange()
    pair.a.startLocalExchange(port: aPort); _ = try await ready(pair.a.transport)
    _ = try await service.flush { bytes, _ in try await server.exchange(bytes, to: address(aPort)) }
    #expect(pair.a.snapshot?.pendingTransfers == 0 && pair.a.snapshot?.publicState.originalDelivery == .deviceReceived)
    pair.a.stopLocalExchange()
    pair.b.startLocalExchange(port: bPort); _ = try await ready(pair.b.transport)
    for action in [DemoAction.acknowledge, .reply] {
        pair.b.perform(action, value: action == .reply ? "SYNTHETIC team reviewing" : "")
        await pair.b.uploadViaRelay(host: "127.0.0.1", port: String(port))
        pair.b.stopLocalExchange()
        pair.a.startLocalExchange(port: aPort); _ = try await ready(pair.a.transport)
        _ = try await service.flush { bytes, _ in try await server.exchange(bytes, to: address(aPort)) }
        pair.a.stopLocalExchange()
        pair.b.startLocalExchange(port: bPort); _ = try await ready(pair.b.transport)
        _ = try await service.flush { bytes, _ in try await server.exchange(bytes, to: address(bPort)) }
    }
    #expect(pair.a.snapshot?.publicState.originalDelivery == .humanAcknowledged)
    #expect(pair.a.snapshot?.publicState.messages.contains { $0.kind == .reply && $0.text == "SYNTHETIC team reviewing" } == true)
    #expect(pair.b.snapshot?.pendingTransfers == 0)
    #expect(try service.count() == 0)
}

@Test @MainActor func nativeRelayLateCustodyDoesNotOverwriteDeviceReceipt() async throws {
    let pair = try NativePair(); defer { pair.stop() }
    let server = LocalExchangeTransport(relayTimeout: .seconds(2)); defer { server.stop() }
    let destination = try #require(pair.b.secureCard)
    let origin = try #require(pair.a.secureCard)
    server.onIncoming = { bytes in
        let event = try RelayPacket(bytes: bytes)
        let receiveB = try #require(pair.b.transport.onIncoming)
        let acceptance = try RelayAcceptance(bytes: receiveB(bytes))
        let reverse = try acceptance.verify(original: event, destination: destination, origin: origin,
                                            now: Int64(Date().timeIntervalSince1970))
        let receipt = try #require(reverse)
        let receiveA = try #require(pair.a.transport.onIncoming)
        _ = try receiveA(receipt.bytes)
        return RelayCustodyReceipt.make(event) // arrived after the actual receipt committed
    }
    try server.start(name: "NativeLateCustodyTest", advertise: false, browse: false)
    let port = try await ready(server)
    pair.a.perform(.sos, value: "SYNTHETIC")
    pair.a.startLocalExchange(); _ = try await ready(pair.a.transport)
    await pair.a.uploadViaRelay(host: "127.0.0.1", port: String(port))
    #expect(pair.a.snapshot?.pendingTransfers == 0 && pair.a.snapshot?.publicState.originalDelivery == .deviceReceived)
    #expect(pair.a.relayStatus.isEmpty)
}

@Test @MainActor func nativeRelayDelayedReceiptAfterDirectConfirmationDoesNotBlockReply() async throws {
    let pair = try NativePair(); defer { pair.stop() }
    let publicCard = try #require(pair.a.secureCard), responderCard = try #require(pair.b.secureCard)
    let service = try RelayService(storageURL: pair.root.appendingPathComponent("mixed-relay.sqlite"),
                                   publicCard: publicCard, responderCard: responderCard)
    let server = LocalExchangeTransport(relayTimeout: .seconds(2)); defer { server.stop() }
    server.onIncoming = { try service.admit($0) }
    try server.start(name: "NativeMixedRouteTest", advertise: false, browse: false)
    let port = try await ready(server)
    pair.a.perform(.sos, value: "SYNTHETIC mixed route")
    pair.a.startLocalExchange(); _ = try await ready(pair.a.transport)
    await pair.a.uploadViaRelay(host: "127.0.0.1", port: String(port))
    pair.a.useRelayRoute(false); pair.b.useRelayRoute(false)
    pair.a.startLocalExchange(); _ = try await ready(pair.a.transport)
    pair.b.startLocalExchange(); let directPort = try await ready(pair.b.transport)
    await pair.a.transferQueued(to: address(directPort))
    #expect(pair.a.snapshot?.pendingTransfers == 0)
    pair.a.perform(.followUp, value: "SYNTHETIC later pending message")
    pair.a.useRelayRoute(true); pair.b.useRelayRoute(true)
    pair.a.retrySavedSession() // confirmation must survive reopen, not just an in-memory exception
    pair.a.startLocalExchange(); let aPort = try await ready(pair.a.transport)
    pair.b.startLocalExchange(); let bPort = try await ready(pair.b.transport)
    let deliver: (Data, EndpointRole) async throws -> Data = { bytes, role in
        try await server.exchange(bytes, to: address(role == .publicUser ? aPort : bPort))
    }
    _ = try await service.flush { try await deliver($0, $1) }
    let delayed = try await service.flush { try await deliver($0, $1) }
    guard case .delivered = delayed else { Issue.record("Previously confirmed receipt blocked relay queue"); return }
    #expect(pair.a.snapshot?.pendingTransfers == 1) // late receipt must not confirm the newer head
    pair.b.perform(.acknowledge)
    await pair.b.uploadViaRelay(host: "127.0.0.1", port: String(port))
    _ = try await service.flush { try await deliver($0, $1) }
    _ = try await service.flush { try await deliver($0, $1) }
    #expect(pair.a.snapshot?.publicState.originalDelivery == .humanAcknowledged)
    #expect(pair.b.snapshot?.pendingTransfers == 0)
    #expect(try service.count() == 0)
}
