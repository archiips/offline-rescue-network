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
    private let responders: [Data]
    private let now: @MainActor () -> Int64
    private var bootstrap: EnrollmentBootstrap?
    private var destination: NWEndpoint?
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    @Published public private(set) var relayNetwork: RegisteredRelayEndpointNetwork?
    private var relayActive = true

    public init(secure: SecureEndpointController, credential: Data, trust: EnrollmentTrust,
                responders: [Data] = [],
                now: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970) }) throws {
        guard responders.count <= 4 else { throw EnrollmentError.malformed }
        _ = try EnrollmentBootstrap(secure: secure, credential: credential, trust: trust, now: now)
        self.secure = secure; self.credential = credential; self.trust = trust; self.now = now; self.responders = responders
        snapshot = secure.endpoint.snapshot
        secure.endpoint.onChange = { [weak self] in self?.snapshot = self?.secure.endpoint.snapshot }
    }
    deinit { worker?.cancel() }

    /// Explicit foreground start; every restart needs fresh proofs, even if keys/pins survived.
    public func start() throws {
        stop()
        let bootstrap = try EnrollmentBootstrap(secure: secure, credential: credential, trust: trust, now: now)
        self.bootstrap = bootstrap; relayActive = true
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
        if secure.role == .publicUser && !responders.isEmpty {
            let network = RegisteredRelayEndpointNetwork(card: secure.card,
                routingHint: RegisteredRelayRouting.hint(realm: trust.realm, issuer: trust.issuerBytes),
                validate: { [weak self] in
                    guard let self, self.relayActive, self.transport.active else { throw EnrollmentError.stopped }
                    _ = try self.secure.enrollmentIdentity()
                    _ = try self.trust.verify(self.credential, expectedRole: .publicUser, at: self.now())
                }, answerReadiness: { [weak self] query in
                    guard let self else { throw EnrollmentError.stopped }
                    return try RelayReadinessProbe.answer(query, identity: self.secure.enrollmentIdentity())
                }, receive: { [weak self] bytes in
                    guard let self else { throw EnrollmentError.stopped }
                    return try self.receiveRegisteredRelay(bytes)
                }, outgoing: { [weak self] in
                    guard let self else { throw EnrollmentError.stopped }
                    return try self.registeredRelayOutgoing().map { [$0] } ?? []
                })
            do { try network.start(); relayNetwork = network } catch { stop(); throw error }
        }
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
        relayNetwork?.stop(); relayNetwork = nil; relayActive = false
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
    public func registeredRelayOutgoing() throws -> RegisteredRelayPacket? {
        guard relayActive else { throw EnrollmentError.stopped }
        guard let peer = try selectedRelayResponder() else { return nil }
        return try relayEndpoint(peerCredential: peer).outgoing()
    }
    private func selectedRelayResponder() throws -> Data? {
        try responders.first { bytes in
            let card = try trust.verify(bytes, expectedRole: .responder, at: now()).card
            return secure.peerCard == nil || secure.peerCard == card
        }
    }
    public func receiveRegisteredRelay(_ bytes: Data) throws -> Data {
        guard relayActive else { throw EnrollmentError.stopped }
        let wrapper = try RegisteredRelayPacket(bytes: bytes)
        let cards = try wrapper.authenticate(trust: trust, now: now())
        guard let selected = try selectedRelayResponder(),
              try EnrollmentCredential.decode(selected).card == cards.sender,
              cards.recipient == secure.card, cards.sender.role == .responder else { throw EnrollmentError.wrongIdentity }
        return try relayEndpoint(peerCredential: wrapper.senderCredential).receive(bytes)
    }
    private func relayEndpoint(peerCredential: Data) throws -> RegisteredRelayEndpoint {
        let peer = try trust.verify(peerCredential, expectedRole: .responder, at: now()).card
        let original = secure.card
        let validate = { [weak self] in
            guard let self, self.secure.card == original else { throw EnrollmentError.stopped }
            guard try self.trust.verify(self.credential, expectedRole: .publicUser, at: self.now()).card == original,
                  self.secure.peerCard == nil || self.secure.peerCard == peer else { throw EnrollmentError.wrongIdentity }
            _ = try self.secure.enrollmentIdentity()
        }
        let adapter = RelayEndpointController(owner: secure, endpoint: secure.endpoint, peer: peer,
            validate: validate, acceptPlaintext: { [weak self] plain in
                guard let self else { throw EnrollmentError.stopped }
                return try self.secure.endpoint.accept(plain)
            }, onConfirmed: { [weak self] in
                guard let self else { throw EnrollmentError.stopped }
                try self.secure.pair(peer.base64)
            }, clock: now)
        return RegisteredRelayEndpoint(adapter: adapter, own: credential, peer: peerCredential, trust: trust,
            storageURL: secure.endpoint.storageURL, now: now, validate: validate)
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
        // An old Bonjour service instance can disappear after responder restart. Keeping it
        // ahead of live discoveries lets an idle public endpoint report success without
        // ever proving possession to the new listener, leaving responder replies queued.
        if let destination, !candidates.contains(destination) { self.destination = nil }
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
