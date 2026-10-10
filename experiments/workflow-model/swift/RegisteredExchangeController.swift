import Foundation
import Combine
@preconcurrency import Network

/// Synthetic prepared-registration drill; one opposite-role conversation, foreground-only.
/// No issuer private key, online account service, emergency-time public pairing or manual Transfer.
@MainActor public final class RegisteredExchangeController: ObservableObject {
    public let transport = LocalExchangeTransport(registrationTimeout: .seconds(3))
    public let secure: SecureEndpointController
    @Published public private(set) var status = "Prepared drill; exchange stopped"
    @Published public private(set) var busy = false
    @Published public private(set) var snapshot: EndpointSnapshot?
    private let credential: Data
    private let trust: EnrollmentTrust
    private let now: @MainActor () -> Int64
    private var bootstrap: EnrollmentBootstrap?
    private var destination: NWEndpoint?
    private var generation = UUID()
    private var worker: Task<Void, Never>?

    public init(secure: SecureEndpointController, credential: Data, trust: EnrollmentTrust,
                now: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970) }) throws {
        _ = try EnrollmentBootstrap(secure: secure, credential: credential, trust: trust, now: now)
        self.secure = secure; self.credential = credential; self.trust = trust; self.now = now
        snapshot = secure.endpoint.snapshot
        secure.endpoint.onChange = { [weak self] in self?.snapshot = self?.secure.endpoint.snapshot }
    }
    deinit { worker?.cancel() }

    /// Explicit foreground start; every restart needs fresh proofs, even if keys/pins survived.
    public func start() throws {
        stop()
        let bootstrap = try EnrollmentBootstrap(secure: secure, credential: credential, trust: trust, now: now)
        self.bootstrap = bootstrap
        let run = generation
        transport.onIncoming = { [weak self] packet in
            guard let self, run == self.generation, self.transport.active else { throw EnrollmentError.stopped }
            if packet.starts(with: Data("ORS1".utf8)) {
                return try bootstrap.acceptApplication(packet)
            }
            let proof = try EnrollmentWire.decode(EnrollmentBootstrap.Proof.self, packet)
            switch proof.domain {
            case "OREH1": return try bootstrap.answerHello(packet)
            case "OREF1":
                let ready = try bootstrap.answerFinish(packet)
                self.status = "Authenticated public candidate; awaiting encrypted request"
                return ready
            default: throw EnrollmentError.malformed
            }
        }
        transport.discoveryNameContains = secure.peerCard.map { "-" + $0.fingerprint.prefix(16) + "-" }
        do {
            try transport.start(name: "RescueRegistered-\(secure.role.rawValue)-\(secure.card.fingerprint.prefix(16))-\(UUID().uuidString.prefix(8))")
        } catch { stop(); throw error }
        status = "Looking for enrolled drill peer; messages stay saved"
        worker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(run)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    public func stop() {
        generation = UUID(); worker?.cancel(); worker = nil
        bootstrap?.stop(); bootstrap = nil; destination = nil
        transport.stop(); busy = false; status = "Stopped; no background exchange"
    }
    /// Saving a request does not require a reachable peer. Expired local preparation is rejected.
    public func perform(_ action: DemoAction, value: String = "", reference: String = "") throws {
        guard try trust.verify(credential, expectedRole: secure.role, at: now()).card == secure.card else { throw EnrollmentError.wrongIdentity }
        let saved = try secure.perform(action, value: value, reference: reference)
        snapshot = secure.endpoint.snapshot
        guard saved else { throw EndpointError(message: snapshot?.error ?? "Action was not saved") }
    }
    private func tick(_ run: UUID) async {
        guard run == generation, transport.active, !busy, let bootstrap else { return }
        if secure.role == .publicUser && secure.peerCard == nil && (snapshot?.pendingTransfers ?? 0) == 0 { return }
        busy = true
        defer { if run == generation { busy = false } }
        var candidates = transport.peers.map(\.endpoint)
        if let pinned = secure.peerCard {
            // Untrusted fingerprint hint only narrows routing; proofs still verify the entire key.
            let hint = "-" + pinned.fingerprint.prefix(16) + "-"
            candidates = candidates.filter {
                if case .service(let name, _, _, _) = $0 { return name.contains(hint) }
                return false
            }
        }
        if let destination, !candidates.contains(destination) { candidates.insert(destination, at: 0) }
        for candidate in candidates {
            guard run == generation, !Task.isCancelled else { return }
            do {
                // Public initiates possession proofs; responder never grants trust from a name.
                if secure.role == .publicUser && (destination != candidate || bootstrap.peerCredential == nil) {
                    let hello = try bootstrap.hello()
                    let challenge = try await transport.exchange(hello, to: candidate)
                    guard run == generation else { return }
                    let finish = try bootstrap.answerChallenge(challenge)
                    let ready = try await transport.exchange(finish, to: candidate)
                    guard run == generation else { return }
                    try bootstrap.acceptReady(ready)
                    destination = candidate
                }
                try bootstrap.validateSession()
                if secure.role == .responder && (snapshot?.pendingTransfers ?? 0) == 0 { return }
                for _ in 0..<64 {
                    try bootstrap.validateSession()
                    guard run == generation, !Task.isCancelled, let packet = try bootstrap.nextPacket() else { break }
                    let receipt = try await transport.exchange(packet, to: candidate)
                    guard run == generation else { return }
                    try bootstrap.validateSession()
                    try bootstrap.confirm(receipt)
                }
                status = "Verified enrolled drill peer; foreground exchange on"
                if (snapshot?.pendingTransfers ?? 0) == 0 { return }
            } catch {
                guard run == generation else { return }
                if secure.role == .publicUser && secure.peerCard == nil { destination = nil }
                status = "No verified exchange yet; unconfirmed messages stay saved. \(error)"
            }
        }
    }
}
