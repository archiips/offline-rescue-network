import Foundation
import Testing
@preconcurrency import Network
@testable import ProbeTransport

@MainActor private final class ConnectionHolder { var connection: NWConnection?; var ready = false; var received = false; var attemptedReply = false }

@MainActor private func waitUntil(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<150 {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return predicate()
}

@Test @MainActor func localhostRoundTripAndRestart() async throws {
    let host = ProbeTransport(timeout: .seconds(2))
    let client = ProbeTransport(timeout: .seconds(2))
    defer { host.stop(); client.stop() }
    for expected in 1...2 {
        try host.startHosting(advertise: false)
        #expect(await waitUntil { host.hostPort != nil })
        let port = try #require(host.hostPort)
        client.send(to: .hostPort(host: "127.0.0.1", port: port))
        #expect(await waitUntil { client.receiptCount == expected })
        #expect(client.status.contains("no human acknowledgment"))
        host.stop(); client.stop()
    }
}

@Test @MainActor func stopBeforeConnectInvalidatesCallbacks() async throws {
    let host = ProbeTransport(timeout: .seconds(1))
    let client = ProbeTransport(timeout: .seconds(1))
    defer { host.stop(); client.stop() }
    try host.startHosting(advertise: false)
    #expect(await waitUntil { host.hostPort != nil })
    let port = try #require(host.hostPort)
    client.send(to: .hostPort(host: "127.0.0.1", port: port))
    client.stop()
    try await Task.sleep(for: .milliseconds(200))
    #expect(client.receiptCount == 0)
    #expect(client.status == "Stopped; no background exchange")
}

@Test @MainActor func truncatedFrameAndIdlePeerAreClosed() async throws {
    let host = ProbeTransport(timeout: .milliseconds(200))
    defer { host.stop() }
    try host.startHosting(advertise: false)
    #expect(await waitUntil { host.hostPort != nil })
    let port = try #require(host.hostPort)
    let raw = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    defer { raw.cancel() }
    raw.stateUpdateHandler = { state in
        if case .ready = state {
            raw.send(content: Data([79,82]), contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
        }
    }
    raw.start(queue: .main)
    #expect(await waitUntil { host.logs.contains("Rejected incomplete frame") }, "Host events: \(host.logs)")
    let idle = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    defer { idle.cancel() }
    idle.start(queue: .main)
    #expect(await waitUntil { host.logs.contains("Timed out; no receipt") })
    #expect(host.receiptCount == 0)
}

@Test @MainActor func fragmentedRequestAndWrongReceiptAreHandled() async throws {
    let host = ProbeTransport(timeout: .seconds(2))
    defer { host.stop() }
    try host.startHosting(advertise: false)
    #expect(await waitUntil { host.hostPort != nil })
    let port = try #require(host.hostPort)
    let raw = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
    defer { raw.cancel() }
    let request = try #require(Wire.encode(kind: 1, id: Array(repeating: 7, count: 16)))
    raw.stateUpdateHandler = { state in
        if case .ready = state {
            raw.send(content: request.prefix(3), completion: .contentProcessed { error in
                if error == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    raw.send(content: request.dropFirst(3), completion: .contentProcessed { _ in })
                } }
            })
        }
    }
    raw.start(queue: .main)
    #expect(await waitUntil { host.logs.contains("Synthetic receipt sent") })
    // Server sends a valid receipt with the wrong correlation ID.
    let params = NWParameters.tcp
    params.includePeerToPeer = true
    let impostor = try NWListener(using: params)
    let held = ConnectionHolder()
    impostor.stateUpdateHandler = { state in
        if case .ready = state { Task { @MainActor in held.ready = true } }
    }
    impostor.newConnectionHandler = { connection in
        Task { @MainActor in
            held.connection = connection
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    let wrong = Wire.encode(kind: 2, id: Array(repeating: 0, count: 16))!
                    connection.send(content: wrong, completion: .contentProcessed { _ in })
                }
            }
            connection.start(queue: .main)
        }
    }
    defer { held.connection?.cancel(); impostor.cancel() }
    impostor.start(queue: .main)
    #expect(await waitUntil { held.ready })
    let badPort = try #require(impostor.port)
    let client = ProbeTransport(timeout: .seconds(2))
    defer { client.stop() }
    client.send(to: .hostPort(host: "127.0.0.1", port: badPort))
    #expect(await waitUntil { client.logs.contains("Rejected mismatched receipt") }, "Client events: \(client.logs)")
    #expect(client.receiptCount == 0)
}


@Test @MainActor func stopAfterRequestIgnoresDelayedReply() async throws {
    let held = ConnectionHolder()
    let params = NWParameters.tcp
    params.includePeerToPeer = true
    let listener = try NWListener(using: params)
    listener.stateUpdateHandler = { state in
        if case .ready = state { Task { @MainActor in held.ready = true } }
    }
    listener.newConnectionHandler = { connection in
        Task { @MainActor in
            held.connection = connection
            connection.stateUpdateHandler = { state in
                if case .ready = state {
                    connection.receive(minimumIncompleteLength: 24, maximumLength: 24) { data, _, _, _ in
                        Task { @MainActor in
                            guard let data, let frame = Wire.decode(data), frame.kind == 1 else { return }
                            held.received = true
                            try? await Task.sleep(for: .milliseconds(200))
                            held.attemptedReply = true
                            connection.send(content: Wire.encode(kind: 2, id: frame.id), completion: .contentProcessed { _ in })
                        }
                    }
                }
            }
            connection.start(queue: .main)
        }
    }
    listener.start(queue: .main)
    let client = ProbeTransport(timeout: .seconds(2))
    defer { client.stop(); held.connection?.stateUpdateHandler = nil; held.connection?.cancel(); listener.cancel() }
    #expect(await waitUntil { held.ready })
    let port = try #require(listener.port)
    client.send(to: .hostPort(host: "127.0.0.1", port: port))
    #expect(await waitUntil { held.received })
    client.stop()
    #expect(await waitUntil { held.attemptedReply })
    try await Task.sleep(for: .milliseconds(100))
    #expect(client.receiptCount == 0)
    #expect(client.status == "Stopped; no background exchange")
}
