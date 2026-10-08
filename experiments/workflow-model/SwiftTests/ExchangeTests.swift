import Foundation
import Testing
@preconcurrency import Network
@testable import RescueDemoState

// Synthetic local exchange checks. Real C++ endpoints, separate SQLite files, real loopback sockets.

private func temporaryStore(_ name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("rescue-exchange-\(UUID().uuidString)", isDirectory: true)
    return directory.appendingPathComponent(name + ".sqlite")
}

private func header(_ length: UInt32) -> Data {
    Data([UInt8(length >> 24 & 0xff), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)])
}

@MainActor private func waitFor(_ seconds: Double = 5, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .milliseconds(Int(seconds * 1000))
    while !condition() {
        guard ContinuousClock.now < deadline else { Issue.record("Condition not met in time"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor private func loopback(_ transport: LocalExchangeTransport) throws -> NWEndpoint {
    let port = try #require(transport.hostPort)
    return .hostPort(host: "127.0.0.1", port: port)
}

// MARK: Framing

@Test func frameRoundTripUsesBigEndianLength() throws {
    let payload = Data("ORX1 sample".utf8)
    let frame = try ExchangeFrameAccumulator.frame(payload)
    #expect(frame.prefix(4) == header(UInt32(payload.count)))
    #expect(frame.dropFirst(4) == payload)
    var accumulator = ExchangeFrameAccumulator()
    #expect(try accumulator.append(frame) == payload)
}

@Test func frameRejectsEmptyAndOversizedPayloads() {
    #expect(throws: ExchangeFrameError.self) { try ExchangeFrameAccumulator.frame(Data()) }
    #expect(throws: ExchangeFrameError.self) { try ExchangeFrameAccumulator.frame(Data(count: 4097)) }
    #expect((try? ExchangeFrameAccumulator.frame(Data(count: 4096)))?.count == 4100)
}

@Test func fragmentedFrameCompletesOnlyOnLastByte() throws {
    let payload = Data((0..<300).map { UInt8($0 & 0xff) })
    let frame = try ExchangeFrameAccumulator.frame(payload)
    var accumulator = ExchangeFrameAccumulator()
    for index in frame.indices.dropLast() {
        #expect(try accumulator.append(frame[index...index]) == nil)
    }
    #expect(try accumulator.append(frame.suffix(1)) == payload)
}

@Test func lengthOutsideBoundsIsRejectedFromHeaderAlone() throws {
    for length: UInt32 in [0, 4097, 70_000, .max] {
        var accumulator = ExchangeFrameAccumulator()
        #expect(throws: ExchangeFrameError.self) { _ = try accumulator.append(header(length)) }
        #expect(accumulator.bufferedCount == 0)
    }
    // Split header still rejected before any body growth.
    var split = ExchangeFrameAccumulator()
    #expect(try split.append(header(5000).prefix(2)) == nil)
    #expect(throws: ExchangeFrameError.self) { _ = try split.append(header(5000).suffix(2) + Data(count: 10)) }
}

@Test func extraBytesAndAppendAfterCompletionAreRejected() throws {
    let frame = try ExchangeFrameAccumulator.frame(Data([1, 2, 3]))
    var extra = ExchangeFrameAccumulator()
    #expect(throws: ExchangeFrameError.self) { _ = try extra.append(frame + Data([9])) }
    var complete = ExchangeFrameAccumulator()
    #expect(try complete.append(frame) == Data([1, 2, 3]))
    #expect(throws: ExchangeFrameError.self) { _ = try complete.append(Data([0])) }
    // A failed accumulator stays failed.
    #expect(throws: ExchangeFrameError.self) { _ = try extra.append(Data()) }
}

@Test func randomChunkingAndIncompleteFrames() throws {
    var generator = SystemRandomNumberGenerator()
    for _ in 0..<200 {
        let length = Int.random(in: 1...4096, using: &generator)
        let payload = Data((0..<length).map { _ in UInt8.random(in: 0...255, using: &generator) })
        let frame = try ExchangeFrameAccumulator.frame(payload)
        var accumulator = ExchangeFrameAccumulator()
        var offset = 0
        var result: Data?
        while offset < frame.count {
            let size = min(Int.random(in: 1...700, using: &generator), frame.count - offset)
            let chunk = frame.subdata(in: offset..<(offset + size))
            offset += size
            result = try accumulator.append(chunk)
            #expect(result == nil || offset == frame.count)
            #expect(accumulator.bufferedCount <= ExchangeFrameAccumulator.maximumFrame)
        }
        #expect(result == payload)
        // Truncated copy never yields a payload.
        var truncated = ExchangeFrameAccumulator()
        let cut = Int.random(in: 0..<frame.count, using: &generator)
        #expect(try truncated.append(frame.prefix(cut)) == nil)
        #expect(truncated.isPartial == (cut > 0))
    }
    // A declared length different from the bytes supplied cannot complete.
    var mismatch = ExchangeFrameAccumulator()
    #expect(try mismatch.append(header(10) + Data(count: 9)) == nil)
    #expect(throws: ExchangeFrameError.self) { _ = try mismatch.append(Data(count: 2)) }
}

// MARK: Endpoint controller over real C++ stores

@Test @MainActor func endpointRejectsInvalidStorageWithoutFallback() {
    let remote = EndpointController(storageURL: URL(string: "https://example.invalid/store.sqlite")!, role: .publicUser)
    #expect(remote.snapshot == nil)
    #expect(!remote.error.isEmpty)
    #expect(throws: (any Error).self) { _ = try remote.nextPacket() }
}

@Test @MainActor func endpointsExchangeWithDroppedReceiptAndRestart() throws {
    let publicURL = try temporaryStore("public")
    let responderURL = try temporaryStore("responder")
    let publicUser = EndpointController(storageURL: publicURL, role: .publicUser)
    let responder = EndpointController(storageURL: responderURL, role: .responder)
    #expect(publicUser.error.isEmpty, "\(publicUser.error)")
    #expect(responder.error.isEmpty, "\(responder.error)")
    #expect(publicUser.snapshot?.role == "public")
    #expect(responder.snapshot?.role == "command")
    #expect(try publicUser.nextPacket() == nil)

    var changes = 0
    publicUser.onChange = { changes += 1 }
    publicUser.perform(.sos)
    #expect(changes == 1)
    #expect(publicUser.snapshot?.pendingTransfers == 1)
    #expect(publicUser.snapshot?.state.originalDelivery == .waiting)
    let packet = try #require(try publicUser.nextPacket())

    // Receiver commits; response is dropped before the sender confirms.
    let receipt = try responder.accept(packet)
    #expect(responder.snapshot?.state.hasRequest == true)
    let responderMessages = responder.snapshot?.state.messages.count

    publicUser.reopen()
    #expect(publicUser.snapshot?.pendingTransfers == 1, "Unconfirmed transfer retained across restart")
    #expect(publicUser.snapshot?.state.originalDelivery == .waiting)
    let retry = try #require(try publicUser.nextPacket())
    #expect(retry == packet)
    let repeated = try responder.accept(retry)
    #expect(repeated == receipt, "Duplicate returns the same committed receipt")
    #expect(responder.snapshot?.state.messages.count == responderMessages)

    try publicUser.confirm(repeated)
    #expect(publicUser.snapshot?.pendingTransfers == 0)
    #expect(publicUser.snapshot?.state.originalDelivery == .deviceReceived, "Device receipt is not acknowledgment")
    #expect(try publicUser.nextPacket() == nil)

    // Explicit human acknowledgment travels back as its own event with its own receipt.
    responder.perform(.acknowledge)
    #expect(responder.error.isEmpty, "\(responder.error)")
    let acknowledgment = try #require(try responder.nextPacket())
    let ackReceipt = try publicUser.accept(acknowledgment)
    #expect(publicUser.snapshot?.state.originalDelivery == .humanAcknowledged)
    #expect(responder.snapshot?.pendingTransfers == 1)
    responder.reopen()
    try responder.confirm(ackReceipt)
    #expect(responder.snapshot?.pendingTransfers == 0)

    // Restart preserves both committed histories.
    publicUser.reopen()
    #expect(publicUser.snapshot?.state.originalDelivery == .humanAcknowledged)
    #expect(publicURL.path != responderURL.path)
}

@Test @MainActor func failedAcceptAndConfirmRefreshAndExposeErrors() throws {
    let publicUser = EndpointController(storageURL: try temporaryStore("public"), role: .publicUser)
    let responder = EndpointController(storageURL: try temporaryStore("responder"), role: .responder)
    publicUser.perform(.sos)
    let packet = try #require(try publicUser.nextPacket())

    var responderChanges = 0
    responder.onChange = { responderChanges += 1 }
    #expect(throws: (any Error).self) { _ = try responder.accept(Data([0x4f, 0x52, 0x58, 0x31, 0xff])) }
    #expect(responderChanges == 1)
    #expect(!responder.error.isEmpty)
    #expect(responder.snapshot?.state.hasRequest == false)

    // Wrong role: a public endpoint cannot accept its own public request as receiver.
    let otherPublic = EndpointController(storageURL: try temporaryStore("other"), role: .publicUser)
    #expect(throws: (any Error).self) { _ = try otherPublic.accept(packet) }

    var publicChanges = 0
    publicUser.onChange = { publicChanges += 1 }
    #expect(throws: (any Error).self) { try publicUser.confirm(Data([1, 2, 3])) }
    #expect(publicChanges == 1)
    #expect(!publicUser.error.isEmpty)
    #expect(publicUser.snapshot?.pendingTransfers == 1)

    let receipt = try responder.accept(packet)
    #expect(responder.error.isEmpty)
    try publicUser.confirm(receipt)
    #expect(publicUser.error.isEmpty)
    #expect(publicUser.snapshot?.pendingTransfers == 0)
}

@Test @MainActor func resetClearsOnlyTheSelectedEndpoint() throws {
    let publicUser = EndpointController(storageURL: try temporaryStore("public"), role: .publicUser)
    let responder = EndpointController(storageURL: try temporaryStore("responder"), role: .responder)
    publicUser.perform(.sos)
    _ = try responder.accept(try #require(try publicUser.nextPacket()))
    publicUser.reset()
    #expect(publicUser.snapshot?.state.hasRequest == false)
    #expect(publicUser.snapshot?.pendingTransfers == 0)
    #expect(responder.snapshot?.state.hasRequest == true)
}

// MARK: Actual loopback sockets

@MainActor private final class Flag { var value = false }

/// Plain test peer that holds or answers raw connections; never reports exchange success itself.
@MainActor private final class RawPeer {
    let listener: NWListener
    var connections: [NWConnection] = []
    var port: NWEndpoint.Port?
    init(_ onConnection: @escaping @MainActor (NWConnection) -> Void) throws {
        listener = try NWListener(using: .tcp)
        listener.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated { if case .ready = state { self?.port = self?.listener.port } }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                self?.connections.append(connection)
                connection.start(queue: .main)
                onConnection(connection)
            }
        }
        listener.start(queue: .main)
    }
    var endpoint: NWEndpoint { .hostPort(host: "127.0.0.1", port: port!) }
    func cancel() { listener.cancel(); connections.forEach { $0.cancel() } }
}

@Test @MainActor func loopbackExchangeBetweenTwoTransportsAndStores() async throws {
    let publicUser = EndpointController(storageURL: try temporaryStore("public"), role: .publicUser)
    let responder = EndpointController(storageURL: try temporaryStore("responder"), role: .responder)
    let publicTransport = LocalExchangeTransport()
    let responderTransport = LocalExchangeTransport()
    defer { publicTransport.stop(); responderTransport.stop() }
    publicTransport.onIncoming = { try publicUser.accept($0) }
    responderTransport.onIncoming = { try responder.accept($0) }
    try publicTransport.start(name: "Sample public", advertise: false, browse: false)
    try responderTransport.start(name: "Sample command", advertise: false, browse: false)
    #expect(publicTransport.active && responderTransport.active)
    try await waitFor { publicTransport.hostPort != nil && responderTransport.hostPort != nil }

    publicUser.perform(.sos)
    let sos = try #require(try publicUser.nextPacket())
    let receipt = try await publicTransport.exchange(sos, to: try loopback(responderTransport))
    #expect(responder.snapshot?.state.hasRequest == true)
    #expect(publicUser.snapshot?.pendingTransfers == 1, "Socket response alone does not confirm")
    try publicUser.confirm(receipt)
    #expect(publicUser.snapshot?.pendingTransfers == 0)
    #expect(publicUser.snapshot?.state.originalDelivery == .deviceReceived)

    responder.perform(.acknowledge)
    let acknowledgment = try #require(try responder.nextPacket())
    let ackReceipt = try await responderTransport.exchange(acknowledgment, to: try loopback(publicTransport))
    try responder.confirm(ackReceipt)
    #expect(responder.snapshot?.pendingTransfers == 0)
    #expect(publicUser.snapshot?.state.originalDelivery == .humanAcknowledged)

    // Restart: stale state cleared, new listener serves again.
    responderTransport.stop()
    #expect(responderTransport.hostPort == nil && !responderTransport.active)
    try responderTransport.start(name: "Sample command", advertise: false, browse: false)
    try await waitFor { responderTransport.hostPort != nil }
    publicUser.perform(.followUp, value: "Sample follow-up")
    #expect(publicUser.error.isEmpty, "\(publicUser.error)")
    let followUp = try #require(try publicUser.nextPacket())
    try publicUser.confirm(try await publicTransport.exchange(followUp, to: try loopback(responderTransport)))
    #expect(publicUser.snapshot?.pendingTransfers == 0)
}

@Test @MainActor func missingOrFailingHandlerClosesWithoutSuccess() async throws {
    let publicUser = EndpointController(storageURL: try temporaryStore("public"), role: .publicUser)
    let client = LocalExchangeTransport()
    let server = LocalExchangeTransport()
    defer { client.stop(); server.stop() }
    try client.start(name: "Client", advertise: false, browse: false)
    try server.start(name: "Server", advertise: false, browse: false)
    try await waitFor { server.hostPort != nil }
    publicUser.perform(.sos)
    let packet = try #require(try publicUser.nextPacket())

    await #expect(throws: (any Error).self) { _ = try await client.exchange(packet, to: try loopback(server)) }
    struct Rejected: Error {}
    server.onIncoming = { _ in throw Rejected() }
    await #expect(throws: (any Error).self) { _ = try await client.exchange(packet, to: try loopback(server)) }
    #expect(publicUser.snapshot?.pendingTransfers == 1)
}

@Test @MainActor func malformedResponseIsRejected() async throws {
    let peer = try RawPeer { connection in
        connection.send(content: header(5000) + Data(count: 16), contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in })
    }
    defer { peer.cancel() }
    let client = LocalExchangeTransport()
    defer { client.stop() }
    try client.start(name: "Client", advertise: false, browse: false)
    try await waitFor { peer.port != nil }
    await #expect(throws: (any Error).self) { _ = try await client.exchange(Data([1]), to: peer.endpoint) }
}

@Test @MainActor func truncatedRequestNeverReachesHandler() async throws {
    let server = LocalExchangeTransport()
    defer { server.stop() }
    var handled = 0
    server.onIncoming = { handled += 1; return $0 }
    try server.start(name: "Server", advertise: false, browse: false)
    try await waitFor { server.hostPort != nil }
    let raw = NWConnection(to: try loopback(server), using: .tcp)
    let closed = Flag()
    raw.stateUpdateHandler = { state in
        MainActor.assumeIsolated {
            if case .ready = state {
                raw.send(content: header(10) + Data(count: 3), contentContext: .finalMessage, isComplete: true,
                         completion: .contentProcessed { _ in })
                raw.receive(minimumIncompleteLength: 1, maximumLength: 16) { data, _, complete, error in
                    MainActor.assumeIsolated { if data == nil && (complete || error != nil) { closed.value = true } }
                }
            }
        }
    }
    raw.start(queue: .main)
    try await waitFor { closed.value }
    raw.cancel()
    #expect(handled == 0)
}

@Test @MainActor func stopFailsPendingExchangeExactlyOnce() async throws {
    let silent = try RawPeer { _ in }
    defer { silent.cancel() }
    let client = LocalExchangeTransport()
    try client.start(name: "Client", advertise: false, browse: false)
    try await waitFor { silent.port != nil }
    let pending = Task { @MainActor in try await client.exchange(Data([1, 2, 3]), to: silent.endpoint) }
    try await waitFor { client.pendingSessions == 1 && !silent.connections.isEmpty }
    client.stop()
    #expect(client.pendingSessions == 0)
    #expect(client.peers.isEmpty && client.hostPort == nil && !client.active)
    await #expect(throws: ExchangeTransportError.stopped) { _ = try await pending.value }
    // Exchanging while stopped fails immediately rather than queuing.
    await #expect(throws: ExchangeTransportError.notActive) { _ = try await client.exchange(Data([1]), to: silent.endpoint) }
}

@Test @MainActor func absoluteDeadlineFailsSilentPeer() async throws {
    let silent = try RawPeer { _ in }
    defer { silent.cancel() }
    let client = LocalExchangeTransport(timeout: .milliseconds(300))
    defer { client.stop() }
    try client.start(name: "Client", advertise: false, browse: false)
    try await waitFor { silent.port != nil }
    let started = ContinuousClock.now
    await #expect(throws: ExchangeTransportError.timedOut) { _ = try await client.exchange(Data([1]), to: silent.endpoint) }
    #expect(started.duration(to: .now) < .seconds(3))
    #expect(client.pendingSessions == 0)
}

@Test @MainActor func sessionCapRejectsNinthConcurrentExchange() async throws {
    let silent = try RawPeer { _ in }
    defer { silent.cancel() }
    let client = LocalExchangeTransport()
    try client.start(name: "Client", advertise: false, browse: false)
    try await waitFor { silent.port != nil }
    let tasks = (0..<8).map { _ in Task { @MainActor in try await client.exchange(Data([1]), to: silent.endpoint) } }
    try await waitFor { client.pendingSessions == 8 }
    await #expect(throws: ExchangeTransportError.sessionLimit) { _ = try await client.exchange(Data([1]), to: silent.endpoint) }
    client.stop()
    for task in tasks { await #expect(throws: ExchangeTransportError.stopped) { _ = try await task.value } }
}

@Test func peerFilteringExcludesOwnNameSortsAndCaps() {
    var endpoints: [NWEndpoint] = (0..<30).reversed().map {
        .service(name: String(format: "Peer %02d", $0), type: LocalExchangeTransport.serviceType, domain: "local.", interface: nil)
    }
    endpoints.append(.service(name: "Me", type: LocalExchangeTransport.serviceType, domain: "local.", interface: nil))
    endpoints.append(.service(name: "Me ", type: LocalExchangeTransport.serviceType, domain: "local.", interface: nil))
    let visible = LocalExchangeTransport.visible(endpoints, endpoint: { $0 }, excluding: "Me")
    #expect(visible.count == 20)
    #expect(!visible.contains(.service(name: "Me", type: LocalExchangeTransport.serviceType, domain: "local.", interface: nil)))
    let names = visible.map { String(describing: $0) }
    #expect(names == names.sorted())
}

@Test @MainActor func startRejectsUnusableNames() {
    let transport = LocalExchangeTransport()
    #expect(throws: ExchangeTransportError.self) { try transport.start(name: "", browse: false) }
    #expect(throws: ExchangeTransportError.self) { try transport.start(name: String(repeating: "x", count: 64), browse: false) }
    #expect(!transport.active)
}
