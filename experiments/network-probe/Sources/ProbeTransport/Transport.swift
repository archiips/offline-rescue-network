import Foundation
import Combine
@preconcurrency import Network

/// Synthetic foreground diagnostic only. All mutable state is MainActor-isolated.
@MainActor public final class ProbeTransport: ObservableObject {
    public static let serviceType = "_rescue-probe._tcp"
    @Published public private(set) var peers: [NWBrowser.Result] = []
    @Published public private(set) var logs: [String] = []
    @Published public private(set) var receiptCount = 0
    @Published public private(set) var hostPort: NWEndpoint.Port?
    @Published public private(set) var status = "Stopped"
    public var onEvent: ((String) -> Void)?
    public let hostName = "RescueProbe-" + String(UUID().uuidString.prefix(8))
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var generation = UUID()
    private var sessions: [UUID: Session] = [:]
    private let timeout: Duration
    private struct Session {
        let connection: NWConnection
        let expectedID: [UInt8]?
        let started: ContinuousClock.Instant
        var buffer = Data()
        var sent = false
        var deadline: Task<Void, Never>?
    }
    public init(timeout: Duration = .seconds(8)) { self.timeout = timeout }
    private func parameters() -> NWParameters {
        let p = NWParameters.tcp
        p.includePeerToPeer = true
        return p
    }
    private func note(_ message: String) {
        logs.append(message)
        if logs.count > 100 { logs.removeFirst(logs.count - 100) }
        status = message
        onEvent?(message)
    }
    public func stop() {
        generation = UUID()
        browser?.cancel(); browser = nil; peers = []
        listener?.cancel(); listener = nil; hostPort = nil
        for session in sessions.values { session.deadline?.cancel(); session.connection.cancel() }
        sessions.removeAll()
        note("Stopped; no background exchange")
    }
    public func startHosting(advertise: Bool = true) throws {
        stop()
        let l = try NWListener(using: parameters())
        let run = generation
        if advertise { l.service = .init(name: hostName, type: Self.serviceType) }
        l.stateUpdateHandler = { [weak self, weak l] state in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                switch state {
                case .ready: self.hostPort = l?.port; self.note("Host ready: " + self.hostName)
                case .waiting(let error), .failed(let error): self.note("Host blocked: \(error)")
                default: break
                }
            }
        }
        l.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self, self.generation == run else { connection.cancel(); return }
                self.attach(connection, expectedID: nil)
            }
        }
        listener = l
        l.start(queue: .main)
    }
    public func browse() {
        stop()
        let run = generation
        let b = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: parameters())
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, self.generation == run else { return }
                switch state {
                case .ready: self.note("Looking for test hosts")
                case .waiting(let error), .failed(let error): self.note("Discovery blocked: \(error). Check Local Network permission.")
                default: break
                }
            }
        }
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self, self.generation == run, self.browser != nil else { return }
                self.peers = Array(results.sorted { String(describing: $0.endpoint) < String(describing: $1.endpoint) }.prefix(20))
            }
        }
        browser = b
        b.start(queue: .main)
    }
    public func send(to endpoint: NWEndpoint) {
        // Stop discovery before connecting; invalidate its queued callbacks.
        stop()
        note("Connecting; synthetic frame only")
        let id = (0..<16).map { _ in UInt8.random(in: 0...255) }
        attach(NWConnection(to: endpoint, using: parameters()), expectedID: id)
    }
    private func attach(_ connection: NWConnection, expectedID: [UInt8]?) {
        guard sessions.count < 8 else { connection.cancel(); note("Connection limit reached"); return }
        let token = UUID()
        sessions[token] = Session(connection: connection, expectedID: expectedID, started: .now)
        sessions[token]?.deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(token, "Timed out; no receipt")
        }
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, var s = self.sessions[token] else { return }
                switch state {
                case .ready:
                    guard !s.sent else { return }
                    s.sent = true; self.sessions[token] = s
                    if let path = s.connection.currentPath {
                        let candidates = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ", ")
                        let types: [NWInterface.InterfaceType] = [.wifi, .wiredEthernet, .loopback, .cellular, .other]
                        let used = types.filter { path.usesInterfaceType($0) }.map { String(describing: $0) }.joined(separator: ", ")
                        self.note("Path types: \(used); available interfaces: \(candidates). Not proof of a specific radio route.")
                    }
                    if let id = s.expectedID, let frame = Wire.encode(kind: 1, id: id) {
                        s.connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                            if let error { Task { @MainActor in self?.finish(token, "Send failed: \(error)") } }
                        })
                    }
                    self.receive(token)
                case .waiting(let error): self.note("Connection waiting: \(error)")
                case .failed(let error): self.finish(token, "Connection failed: \(error)")
                case .cancelled: self.finish(token, "Connection cancelled")
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }
    private func receive(_ token: UUID) {
        guard let s = sessions[token] else { return }
        s.connection.receive(minimumIncompleteLength: 1, maximumLength: 25 - s.buffer.count) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, var current = self.sessions[token] else { return }
                if let data { current.buffer.append(data) }
                self.sessions[token] = current
                if current.buffer.count >= 24 {
                    guard let frame = Wire.decode(current.buffer) else { self.finish(token, "Rejected malformed frame"); return }
                    if let expected = current.expectedID {
                        guard frame.kind == 2, frame.id == expected else { self.finish(token, "Rejected mismatched receipt"); return }
                        self.receiptCount += 1
                        let elapsed = current.started.duration(to: .now)
                        self.finish(token, "Synthetic device receipt in \(elapsed); no human acknowledgment")
                    } else {
                        guard frame.kind == 1, let reply = Wire.encode(kind: 2, id: frame.id) else {
                            self.finish(token, "Rejected unexpected frame kind"); return
                        }
                        current.connection.send(content: reply, completion: .contentProcessed { [weak self] error in
                            Task { @MainActor in
                                self?.finish(token, error == nil ? "Synthetic receipt sent" : "Receipt send failed: \(error!)")
                            }
                        })
                    }
                } else if let error { self.finish(token, "Receive failed: \(error)") }
                else if complete { self.finish(token, "Rejected incomplete frame") }
                else { self.receive(token) }
            }
        }
    }
    private func finish(_ token: UUID, _ message: String) {
        guard let s = sessions.removeValue(forKey: token) else { return }
        s.deadline?.cancel(); s.connection.cancel(); note(message)
    }
}
