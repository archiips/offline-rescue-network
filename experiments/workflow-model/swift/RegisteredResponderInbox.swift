import Foundation
import Combine
@preconcurrency import Network

public struct RegisteredInboxRow: Identifiable, Sendable {
    public let id: String
    public let snapshot: EndpointSnapshot
}

/// Bounded synthetic inbox; each authenticated public card owns an independent C++ history.
@MainActor public final class RegisteredResponderInbox: ObservableObject {
    public let transport = LocalExchangeTransport(registrationTimeout: .seconds(3))
    @Published public private(set) var rows: [RegisteredInboxRow] = []
    @Published public private(set) var status = "Prepared inbox; exchange stopped"
    private let secure: SecureEndpointController
    private let credential: Data
    private let trust: EnrollmentTrust
    private let now: @MainActor () -> Int64
    private let registryStore: any SecureRecordStore
    private let folder: URL
    private var registry: Registry
    private var savedRegistry: Data
    private var sessions: [String: Session] = [:]
    private var active = true
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    @Published public private(set) var relayNetwork: RegisteredRelayEndpointNetwork?
    private var candidateOffsets: [String: Int] = [:]
    var elapsed: @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    private struct Registry: Codable {
        var format = 1
        var responder: Data
        var admitted: [Data] = []
        // Admission journal survives C++ commit / registry-finalization interruption.
        var journal: [Data] = []
        var relayCredentials: [String: Data]?
    }
    private struct Session {
        let context: Conversation
        let bootstrap: EnrollmentBootstrap
        let began: Double
    }
    @MainActor private final class Conversation: EnrollmentConversationContext {
        let owner: SecureEndpointController
        let peer: SecurePairingCard
        let url: URL
        var admitted: Bool
        var provisionalPin = false
        var endpoint: EndpointController?
        var commit: ((Conversation, Data) throws -> Data)?
        var changed: (() -> Void)?
        var role: EndpointRole { .responder }
        var card: SecurePairingCard { owner.card }
        var peerCard: SecurePairingCard? { admitted || provisionalPin ? peer : nil }
        init(owner: SecureEndpointController, peer: SecurePairingCard, url: URL, admitted: Bool) throws {
            self.owner = owner; self.peer = peer; self.url = url; self.admitted = admitted
            if FileManager.default.fileExists(atPath: url.path) { try open() }
        }
        func enrollmentIdentity() throws -> SecureIdentity { try owner.enrollmentIdentity() }
        func pair(_ base64: String) throws {
            guard try SecurePairingCard(base64: base64) == peer else { throw EnrollmentError.wrongIdentity }
            provisionalPin = true
        }
        func open() throws {
            if admitted && !FileManager.default.fileExists(atPath: url.path) { throw SecureExchangeError.historyMissing }
            if endpoint == nil {
                let e = EndpointController(storageURL: url, role: .responder, storageBinding: owner.card.fingerprint + ":" + peer.fingerprint)
                guard e.snapshot != nil else { throw SecureExchangeError.historyMissing }
                endpoint = e
                e.onChange = { [weak self] in self?.changed?() }
            }
            if admitted && endpoint?.snapshot?.state.hasRequest != true { throw SecureExchangeError.historyMissing }
        }
        func nextPlaintextPacket() throws -> Data? {
            guard admitted else { return nil }
            try open(); return try endpoint?.nextPacket()
        }
        func accept(_ packet: Data) throws -> Data {
            let envelope = try SecureEnvelope(identity: enrollmentIdentity(), peer: peer)
            let plaintext = try envelope.open(packet)
            guard let commit else { throw EnrollmentError.stopped }
            return try envelope.seal(commit(self, plaintext))
        }
        func confirm(_ packet: Data) throws {
            guard admitted else { throw EnrollmentError.wrongIdentity }
            let plaintext = try SecureEnvelope(identity: enrollmentIdentity(), peer: peer).open(packet)
            try open(); try endpoint?.confirm(plaintext)
        }
    }
    public init(secure: SecureEndpointController, credential: Data, trust: EnrollmentTrust,
                registryStore: (any SecureRecordStore)? = nil,
                now: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970) }) throws {
        guard secure.role == .responder,
              try trust.verify(credential, expectedRole: .responder, at: now()).card == secure.card else { throw EnrollmentError.wrongIdentity }
        _ = try secure.enrollmentIdentity()
        self.secure = secure; self.credential = credential; self.trust = trust; self.now = now
        let folder = secure.rootURL.appendingPathComponent("registered-inbox", isDirectory: true)
            .appendingPathComponent(secure.card.fingerprint, isDirectory: true)
        self.folder = folder
        let store = registryStore ?? DefaultKeychainStore(rootURL: secure.rootURL, role: .responder,
            namespace: "registered-inbox-v1-" + secure.card.fingerprint)
        self.registryStore = store
        let stored = try store.read()
        let files: [String]
        if FileManager.default.fileExists(atPath: folder.path) { files = try FileManager.default.contentsOfDirectory(atPath: folder.path) }
        else { files = [] }
        let record: Registry
        if let stored {
            guard stored.count <= 65536, let decoded = try? JSONDecoder().decode(Registry.self, from: stored),
                  decoded.format == 1, decoded.responder == secure.card.bytes,
                  decoded.admitted.count + decoded.journal.count <= 16 else { throw SecureExchangeError.recordInvalid }
            record = decoded
        } else {
            guard files.isEmpty else { throw SecureExchangeError.recordMissing }
            record = Registry(responder: secure.card.bytes)
        }
        var ids = Set<String>()
        for bytes in record.admitted + record.journal {
            let peer = try SecurePairingCard(bytes: bytes)
            guard peer.role == .publicUser, ids.insert(peer.fingerprint).inserted else { throw SecureExchangeError.recordInvalid }
            if record.admitted.contains(bytes), !FileManager.default.fileExists(atPath: folder.appendingPathComponent(peer.fingerprint + ".sqlite").path) {
                throw SecureExchangeError.historyMissing
            }
        }
        for (id, bytes) in record.relayCredentials ?? [:] {
            guard ids.contains(id), try EnrollmentCredential.decode(bytes).card.fingerprint == id else { throw SecureExchangeError.recordInvalid }
        }
        let knownFiles = Set(ids.flatMap { id in
            [".sqlite", ".sqlite-journal", ".sqlite-wal", ".sqlite-shm", ".relay-cache.sqlite", ".relay-cache.sqlite-journal", ".relay-cache.sqlite-wal", ".relay-cache.sqlite-shm", ".relay-cache.guard", ".registered-relay.sqlite", ".registered-relay.sqlite-journal", ".registered-relay.sqlite-wal", ".registered-relay.sqlite-shm", ".registered-relay.sqlite.guard"].map { id + $0 }
        })
        for file in files {
            guard file == ".DS_Store" || knownFiles.contains(file) else { throw SecureExchangeError.recordInvalid }
        }
        registry = record
        let encoded = try JSONEncoder().encode(record)
        if stored == nil { try store.write(encoded) }
        savedRegistry = stored ?? encoded
        for bytes in record.admitted {
            let peer = try SecurePairingCard(bytes: bytes)
            _ = try makeSession(peer, admitted: true)
        }
        refresh()
    }
    deinit { worker?.cancel() }
    private func validate(requireActive: Bool = true) throws {
        guard !requireActive || active else { throw EnrollmentError.stopped }
        guard try registryStore.read() == savedRegistry else { throw SecureExchangeError.staleSession }
        guard try trust.verify(credential, expectedRole: .responder, at: now()).card == secure.card else { throw EnrollmentError.wrongIdentity }
        _ = try secure.enrollmentIdentity()
    }
    private func save(_ next: Registry) throws {
        let data = try JSONEncoder().encode(next)
        guard data.count <= 65536 else { throw SecureExchangeError.recordInvalid }
        try registryStore.write(data)
        registry = next; savedRegistry = data
    }
    private func makeSession(_ peer: SecurePairingCard, admitted: Bool) throws -> Session {
        let context = try Conversation(owner: secure, peer: peer,
            url: folder.appendingPathComponent(peer.fingerprint + ".sqlite"), admitted: admitted)
        context.commit = { [weak self] context, plaintext in
            guard let self else { throw EnrollmentError.stopped }
            return try self.commit(context, plaintext)
        }
        context.changed = { [weak self] in self?.refresh() }
        let session = Session(context: context, bootstrap: try EnrollmentBootstrap(context: context, credential: credential, trust: trust, now: now), began: elapsed())
        sessions[peer.fingerprint] = session
        return session
    }
    private func refresh() {
        rows = sessions.values.compactMap { session in
            guard session.context.admitted, let snapshot = session.context.endpoint?.snapshot else { return nil }
            return RegisteredInboxRow(id: session.context.peer.fingerprint, snapshot: snapshot)
        }.sorted { $0.id < $1.id }
    }
    private func prune() {
        let clock = elapsed()
        for (id, session) in sessions where !session.context.admitted {
            if !clock.isFinite || clock < session.began || clock - session.began >= 10 {
                session.bootstrap.stop(); sessions.removeValue(forKey: id)
            }
        }
    }
    private func commit(_ context: Conversation, _ plaintext: Data) throws -> Data {
        try validate()
        if !context.admitted {
            if !registry.journal.contains(context.peer.bytes) {
                guard registry.admitted.count + registry.journal.count < 16 else { throw EnrollmentError.busy }
                // C++ validates a first application before allocating durable inbox history.
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-inbox-preflight-\(UUID())")
                defer { try? FileManager.default.removeItem(at: temporary) }
                let probe = EndpointController(storageURL: temporary.appendingPathComponent("probe.sqlite"), role: .responder)
                _ = try probe.accept(plaintext)
                var journaled = registry; journaled.journal.append(context.peer.bytes)
                try save(journaled)
            }
            try context.open()
            guard let endpoint = context.endpoint else { throw SecureExchangeError.historyMissing }
            let receipt = try endpoint.accept(plaintext)
            var next = registry
            next.journal.removeAll { $0 == context.peer.bytes }
            next.admitted.append(context.peer.bytes)
            try save(next)
            context.admitted = true
            refresh()
            return receipt
        }
        try context.open()
        guard let endpoint = context.endpoint else { throw SecureExchangeError.historyMissing }
        return try endpoint.accept(plaintext)
    }
    /// Delayed first contact uses issuer authorization, never an extended direct handshake lease.
    public func receiveRegisteredRelay(_ bytes: Data) throws -> Data {
        try validate(); prune()
        let wrapper = try RegisteredRelayPacket(bytes: bytes)
        let cards = try wrapper.authenticate(trust: trust, now: now())
        guard cards.sender.role == .publicUser, cards.recipient == secure.card else { throw EnrollmentError.wrongIdentity }
        let context: Conversation
        if let existing = sessions[cards.sender.fingerprint] { context = existing.context }
        else {
            guard wrapper.packet.kind == .event, sessions.values.filter({ !$0.context.admitted }).count < 4, registry.admitted.count + registry.journal.count < 16 else { throw EnrollmentError.busy }
            context = try makeSession(cards.sender, admitted: false).context
        }
        if !context.admitted {
            guard wrapper.packet.kind == .event else { throw EnrollmentError.wrongIdentity }
            let plain = try SecureEnvelope(identity: secure.enrollmentIdentity(), peer: cards.sender).open(wrapper.packet.sealed)
            _ = try commit(context, plain) // Finalize admission before creating a durable relay cache or returning receipt.
        }
        var next = registry
        var credentials = next.relayCredentials ?? [:]
        credentials[cards.sender.fingerprint] = wrapper.senderCredential
        next.relayCredentials = credentials
        try save(next)
        return try relayEndpoint(context, peerCredential: wrapper.senderCredential).receive(bytes)
    }
    public func registeredRelayOutgoing(conversationID: String) throws -> RegisteredRelayPacket? {
        try validate()
        guard let context = sessions[conversationID]?.context, context.admitted,
              let peer = registry.relayCredentials?[conversationID] else { return nil }
        return try relayEndpoint(context, peerCredential: peer).outgoing()
    }
    func registeredRelayBatch() throws -> [RegisteredRelayPacket] {
        try validate()
        var packets: [RegisteredRelayPacket] = []
        for row in rows {
            do { if let packet = try registeredRelayOutgoing(conversationID: row.id) { packets.append(packet) } }
            catch { status = "One relay conversation is unavailable; its work stays saved. \(error)" }
        }
        return packets
    }
    private func relayEndpoint(_ context: Conversation, peerCredential: Data) throws -> RegisteredRelayEndpoint {
        try context.open()
        guard let endpoint = context.endpoint else { throw SecureExchangeError.historyMissing }
        let validate = { [weak self] in
            guard let self else { throw EnrollmentError.stopped }
            try self.validate()
            guard self.registry.admitted.contains(context.peer.bytes) else { throw EnrollmentError.wrongIdentity }
        }
        let adapter = RelayEndpointController(owner: secure, endpoint: endpoint, peer: context.peer,
            validate: validate, acceptPlaintext: { [weak self] plain in
                guard let self else { throw EnrollmentError.stopped }
                return try self.commit(context, plain)
            }, onConfirmed: {}, clock: now)
        return RegisteredRelayEndpoint(adapter: adapter, own: credential, peer: peerCredential, trust: trust,
            storageURL: context.url, now: now, validate: validate)
    }
    public func receive(_ packet: Data) throws -> Data {
        try validate(); prune()
        if packet.starts(with: Data("ORS1".utf8)) {
            guard packet.count >= SecureEnvelope.minimumPayload else { throw SecureExchangeError.packetSize }
            let id = packet[4..<36].map { String(format: "%02x", $0) }.joined()
            guard let session = sessions[id] else { throw EnrollmentError.wrongTranscript }
            return try session.bootstrap.acceptApplication(packet)
        }
        let proof = try EnrollmentWire.decode(EnrollmentBootstrap.Proof.self, packet)
        let peer = try trust.verify(proof.credential, expectedRole: .publicUser, at: now()).card
        guard peer.signingKey.isValidSignature(proof.signature, for: try EnrollmentWire.encode(proof.claims)) else { throw EnrollmentError.invalidSignature }
        switch proof.domain {
        case "OREH1":
            let session: Session
            if let existing = sessions[peer.fingerprint] { session = existing }
            else {
                guard sessions.values.filter({ !$0.context.admitted }).count < 4 else { throw EnrollmentError.busy }
                if !registry.journal.contains(peer.bytes), registry.admitted.count + registry.journal.count >= 16 { throw EnrollmentError.busy }
                session = try makeSession(peer, admitted: registry.admitted.contains(peer.bytes))
            }
            return try session.bootstrap.answerHello(packet)
        case "OREF1":
            guard let session = sessions[peer.fingerprint] else { throw EnrollmentError.wrongTranscript }
            return try session.bootstrap.answerFinish(packet)
        default: throw EnrollmentError.malformed
        }
    }
    public func perform(conversationID: String, action: DemoAction, value: String = "", reference: String = "") throws {
        try validate(requireActive: false)
        guard let context = sessions[conversationID]?.context, context.admitted else { throw EnrollmentError.wrongIdentity }
        try context.open()
        guard context.endpoint?.perform(action, value: value, reference: reference) == true else {
            throw EndpointError(message: context.endpoint?.error ?? "Conversation unavailable")
        }
        refresh()
    }
    public func start() throws {
        stop(); sessions = [:]; active = true
        try validate()
        // Restore visible histories, never proof leases or discovered destinations.
        for bytes in registry.admitted { _ = try makeSession(SecurePairingCard(bytes: bytes), admitted: true) }
        refresh()
        let run = generation
        transport.onIncoming = { [weak self] packet in
            guard let self, self.generation == run, self.transport.active else { throw EnrollmentError.stopped }
            return try self.receive(packet)
        }
        do { try transport.start(name: "RescueRegistered-responder-\(secure.card.fingerprint.prefix(16))-\(UUID().uuidString.prefix(8))") }
        catch { stop(); throw error }
        let network = RegisteredRelayEndpointNetwork(card: secure.card,
            routingHint: RegisteredRelayRouting.hint(realm: trust.realm, issuer: trust.issuerBytes),
            validate: { [weak self] in
                guard let self else { throw EnrollmentError.stopped }
                try self.validate()
            }, answerReadiness: { [weak self] query in
                guard let self else { throw EnrollmentError.stopped }
                return try RelayReadinessProbe.answer(query, identity: self.secure.enrollmentIdentity())
            }, receive: { [weak self] bytes in
                guard let self else { throw EnrollmentError.stopped }
                return try self.receiveRegisteredRelay(bytes)
            }, outgoing: { [weak self] in
                guard let self else { throw EnrollmentError.stopped }
                try self.validate()
                return try self.registeredRelayBatch()
            })
        do { try network.start(); relayNetwork = network } catch { stop(); throw error }
        status = "Looking for enrolled public devices; messages stay saved"
        worker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(run)
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
    }
    public func stop() {
        generation = UUID(); worker?.cancel(); worker = nil
        relayNetwork?.stop(); relayNetwork = nil
        for session in sessions.values { session.bootstrap.stop() }
        sessions = sessions.filter { $0.value.context.admitted }
        candidateOffsets = [:]
        transport.stop(); active = false
        status = "Stopped; no background exchange"
    }
    private func tick(_ run: UUID) async {
        guard generation == run, transport.active else { return }
        prune()
        for id in sessions.keys.sorted() {
            guard generation == run, !Task.isCancelled, let session = sessions[id], session.context.admitted else { continue }
            do {
                try validate()
                try session.bootstrap.validateSession()
                guard let packet = try session.bootstrap.nextPacket() else { continue }
                let hint = "-" + session.context.peer.fingerprint.prefix(16) + "-"
                let candidates = transport.peers.filter {
                    if case .service(let name, _, _, _) = $0.endpoint { return name.contains(hint) }
                    return false
                }
                guard !candidates.isEmpty else { continue }
                let offset = candidateOffsets[id, default: 0] % candidates.count
                candidateOffsets[id] = offset + 1
                for candidate in [candidates[offset]] {
                    do {
                        let receipt = try await transport.exchange(packet, to: candidate.endpoint)
                        guard generation == run else { return }
                        try validate()
                        try session.bootstrap.validateSession()
                        try session.bootstrap.confirm(receipt)
                        status = "Verified enrolled public devices; foreground exchange on"
                        break
                    } catch { status = "Unconfirmed messages stay saved" }
                }
            } catch { /* Fresh possession proof is required independently for each peer. */ }
        }
    }
}
