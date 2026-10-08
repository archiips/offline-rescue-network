import Foundation
import Combine
@preconcurrency import Network

public enum ExchangeFrameError: Error, Equatable, Sendable {
    case invalidLength(UInt64), extraBytes, alreadyComplete, failed
}

/// One 4-byte big-endian length followed by 1...4096 payload bytes. Exactly one frame per stream.
public struct ExchangeFrameAccumulator: Sendable {
    public static let headerLength = 4
    public static let maximumPayload = 4096
    public static let maximumFrame = headerLength + maximumPayload
    private var buffer = Data()
    private var expected: Int?
    private var complete = false
    private var failed = false
    private let payloadLimit: Int
    public init(maximumPayload: Int = 4096) {
        precondition((1...4276).contains(maximumPayload))
        payloadLimit = maximumPayload
    }
    public var bufferedCount: Int { buffer.count }
    public var isPartial: Bool { !buffer.isEmpty && !complete && !failed }

    /// Returns the payload once the frame completes. Bounds are checked before the buffer grows.
    public mutating func append(_ chunk: Data) throws -> Data? {
        guard !failed else { throw ExchangeFrameError.failed }
        if complete {
            if chunk.isEmpty { return nil }
            failed = true
            throw ExchangeFrameError.alreadyComplete
        }
        do {
            var rest = Data(chunk)
            if expected == nil {
                let take = min(Self.headerLength - buffer.count, rest.count)
                buffer.append(rest.prefix(take))
                rest = Data(rest.dropFirst(take))
                guard buffer.count == Self.headerLength else { return nil }
                let length = buffer.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                guard (1...UInt64(payloadLimit)).contains(length) else { throw ExchangeFrameError.invalidLength(length) }
                expected = Self.headerLength + Int(length)
            }
            guard let expected else { return nil }
            guard rest.count <= expected - buffer.count else { throw ExchangeFrameError.extraBytes }
            buffer.append(rest)
            guard buffer.count == expected else { return nil }
            complete = true
            return Data(buffer.dropFirst(Self.headerLength))
        } catch {
            failed = true
            buffer.removeAll()
            throw error
        }
    }
    public static func frame(_ payload: Data, maximumPayload: Int = 4096) throws -> Data {
        precondition((1...4276).contains(maximumPayload))
        guard (1...maximumPayload).contains(payload.count) else {
            throw ExchangeFrameError.invalidLength(UInt64(payload.count))
        }
        let length = UInt32(payload.count)
        return Data([UInt8(length >> 24), UInt8(length >> 16 & 0xff), UInt8(length >> 8 & 0xff), UInt8(length & 0xff)]) + payload
    }
}

public enum ExchangeTransportError: Error, Equatable, Sendable {
    case notActive, stopped, cancelled, timedOut, sessionLimit, invalidName, invalidPort
    case noHandler, rejected, closedWithoutResponse
    case frame(ExchangeFrameError)
    case network(String)
}

/// Bounded local transport; authentication is supplied by its owner: one request frame and one receipt frame per
/// TCP connection. Foreground only; the owner calls stop() on background. All state is MainActor.
@MainActor public final class LocalExchangeTransport: ObservableObject {
    public nonisolated static let serviceType = "_rescue-demo._tcp"
    public nonisolated static let maximumSessions = 8
    public nonisolated static let maximumPeers = 20
    @Published public private(set) var peers: [NWBrowser.Result] = []
    @Published public private(set) var hostPort: NWEndpoint.Port?
    @Published public private(set) var status = "Stopped"
    @Published public private(set) var active = false
    /// Saves an incoming packet and returns its committed receipt. Nil or throwing closes without a response.
    public var onIncoming: ((Data) throws -> Data)?
    private let timeout: Duration
    private let payloadLimit: Int
    private let discoveryType: String
    private var generation = UUID()
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var advertisedName: String?
    private var sessions: [UUID: Session] = [:]
    private struct Session {
        let connection: NWConnection
        /// Present for outgoing exchanges; resumed exactly once by finish().
        var continuation: CheckedContinuation<Data, any Error>?
        var request: Data?
        var accumulator: ExchangeFrameAccumulator
        var deadline: Task<Void, Never>?
        var ready = false
        var responding = false
    }
    var pendingSessions: Int { sessions.count }

    public init(timeout: Duration = .seconds(8), secure: Bool = false) {
        self.timeout = timeout
        payloadLimit = secure ? 4276 : 4096
        discoveryType = secure ? "_rescue-sec._tcp" : Self.serviceType
    }

    private nonisolated static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        return parameters
    }
    /// Peer names are untrusted display text. Drops our own exact advertised name, sorts and caps.
    nonisolated static func visible<T>(_ items: [T], endpoint: (T) -> NWEndpoint, excluding name: String?) -> [T] {
        let others = items.filter {
            if let name, case .service(let peer, _, _, _) = endpoint($0) { return peer != name }
            return true
        }
        return Array(others.sorted { String(describing: endpoint($0)) < String(describing: endpoint($1)) }.prefix(maximumPeers))
    }

    public func start(name: String, advertise: Bool = true, browse: Bool = true, port: UInt16? = nil) throws {
        stop()
        guard !name.isEmpty, name.utf8.count <= 63,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            status = "Exchange name must be 1-63 bytes without control characters"
            throw ExchangeTransportError.invalidName
        }
        let listener: NWListener
        do {
            if let port {
                guard port != 0, let value = NWEndpoint.Port(rawValue: port) else { throw ExchangeTransportError.invalidPort }
                listener = try NWListener(using: Self.parameters(), on: value)
            } else {
                listener = try NWListener(using: Self.parameters())
            }
        } catch let error as ExchangeTransportError {
            status = "Invalid listening port"
            throw error
        } catch {
            status = "Listener unavailable: \(error)"
            throw ExchangeTransportError.network(String(describing: error))
        }
        let run = generation
        if advertise {
            listener.service = .init(name: name, type: discoveryType)
            advertisedName = name
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            MainActor.assumeIsolated {
                guard let self, self.generation == run else { return }
                switch state {
                case .ready:
                    self.hostPort = listener?.port
                    self.status = "Listening for sample exchange"
                case .waiting(let error): self.status = "Listener waiting: \(error)"
                case .failed(let error):
                    self.stop()
                    self.status = "Listener failed: \(error). Exchange stopped."
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated {
                guard let self, self.generation == run, self.listener != nil else { connection.cancel(); return }
                guard self.sessions.count < Self.maximumSessions else {
                    connection.cancel()
                    self.status = "Session limit reached; incoming connection closed"
                    return
                }
                let token = UUID()
                self.sessions[token] = Session(connection: connection, accumulator: ExchangeFrameAccumulator(maximumPayload: self.payloadLimit))
                self.begin(token)
            }
        }
        self.listener = listener
        active = true
        status = "Starting sample exchange"
        listener.start(queue: .main)
        if browse { startBrowsing(run) }
    }

    /// Invalidates every callback, fails pending exchanges once and closes all sessions. Stores are untouched.
    public func stop() {
        generation = UUID()
        browser?.cancel(); browser = nil
        listener?.cancel(); listener = nil
        advertisedName = nil
        peers = []; hostPort = nil; active = false
        for token in Array(sessions.keys) { finish(token, .failure(.stopped)) }
        status = "Stopped; no background exchange"
    }

    /// Sends one framed packet and returns the peer's receipt. The caller confirms it with its store;
    /// send completion alone is never success. No automatic retry.
    public func exchange(_ packet: Data, to endpoint: NWEndpoint) async throws -> Data {
        guard active else { throw ExchangeTransportError.notActive }
        let frame: Data
        do { frame = try ExchangeFrameAccumulator.frame(packet, maximumPayload: payloadLimit) } catch let error as ExchangeFrameError {
            throw ExchangeTransportError.frame(error)
        }
        guard sessions.count < Self.maximumSessions else { throw ExchangeTransportError.sessionLimit }
        try Task.checkCancellation()
        let token = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let connection = NWConnection(to: endpoint, using: Self.parameters())
                sessions[token] = Session(connection: connection, continuation: continuation, request: frame, accumulator: ExchangeFrameAccumulator(maximumPayload: payloadLimit))
                begin(token)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(token, .failure(.cancelled)) }
        }
    }

    private func startBrowsing(_ run: UUID) {
        let browser = NWBrowser(for: .bonjour(type: discoveryType, domain: nil), using: Self.parameters())
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.generation == run, self.browser != nil else { return }
                switch state {
                case .waiting(let error): self.status = "Discovery waiting: \(error). Check Local Network permission."
                case .failed(let error):
                    self.browser?.cancel(); self.browser = nil; self.peers = []
                    self.status = "Discovery failed: \(error)"
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == run, self.browser != nil else { return }
                self.peers = Self.visible(Array(results), endpoint: \.endpoint, excluding: self.advertisedName)
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    private func begin(_ token: UUID) {
        guard let session = sessions[token] else { return }
        let timeout = self.timeout
        // Absolute deadline from session start; progress does not extend it.
        sessions[token]?.deadline = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(token, .failure(.timedOut))
        }
        session.connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self, self.sessions[token] != nil else { return }
                switch state {
                case .ready: self.ready(token)
                case .waiting(let error), .failed(let error): self.finish(token, .failure(.network(String(describing: error))))
                case .cancelled: self.finish(token, .failure(.closedWithoutResponse))
                default: break
                }
            }
        }
        session.connection.start(queue: .main)
    }

    private func ready(_ token: UUID) {
        guard var session = sessions[token], !session.ready else { return }
        session.ready = true
        sessions[token] = session
        if let request = session.request {
            session.connection.send(content: request, completion: .contentProcessed { [weak self] error in
                guard let error else { return }
                MainActor.assumeIsolated { self?.finish(token, .failure(.network(String(describing: error)))) }
            })
        }
        receive(token)
    }

    private func receive(_ token: UUID) {
        guard let session = sessions[token] else { return }
        // Read up to the whole bound so extra bytes in the same chunk are rejected, never buffered past it.
        let capacity = max(1, 4 + payloadLimit - session.accumulator.bufferedCount)
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: capacity) { [weak self] data, _, complete, error in
            MainActor.assumeIsolated {
                guard let self, var current = self.sessions[token], !current.responding else { return }
                let payload: Data?
                do { payload = try current.accumulator.append(data ?? Data()) } catch {
                    self.finish(token, .failure(.frame(error as? ExchangeFrameError ?? .failed))); return
                }
                self.sessions[token] = current
                if let payload { self.deliver(token, payload) }
                else if let error { self.finish(token, .failure(.network(String(describing: error)))) }
                else if complete { self.finish(token, .failure(.closedWithoutResponse)) }
                else { self.receive(token) }
            }
        }
    }

    private func deliver(_ token: UUID, _ payload: Data) {
        guard let session = sessions[token] else { return }
        if session.continuation != nil { finish(token, .success(payload)); return }
        guard let handler = onIncoming else { finish(token, .failure(.noHandler)); return }
        let response: Data
        do { response = try ExchangeFrameAccumulator.frame(try handler(payload), maximumPayload: payloadLimit) } catch {
            finish(token, .failure(.rejected)); return
        }
        // The handler may have stopped the transport.
        guard sessions[token] != nil else { return }
        sessions[token]?.responding = true
        session.connection.send(content: response, contentContext: .finalMessage, isComplete: true,
                                completion: .contentProcessed { [weak self] error in
            MainActor.assumeIsolated {
                self?.finish(token, error.map { .failure(.network(String(describing: $0))) } ?? .success(Data()))
            }
        })
    }

    private func finish(_ token: UUID, _ result: Result<Data, ExchangeTransportError>) {
        guard let session = sessions.removeValue(forKey: token) else { return }
        session.deadline?.cancel()
        session.connection.cancel()
        let outgoing = session.continuation != nil
        switch result {
        case .success: status = outgoing ? "Peer response received" : "Saved incoming sample; receipt sent"
        case .failure(let error): status = (outgoing ? "Exchange failed: " : "Incoming exchange closed: ") + String(describing: error)
        }
        session.continuation?.resume(with: result)
    }
}
