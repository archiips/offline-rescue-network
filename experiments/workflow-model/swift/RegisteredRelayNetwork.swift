import Foundation
import Combine
import CryptoKit
@preconcurrency import Network

/// Public prepared-policy routing hint only; never a credential or discovery trust anchor.
public enum RegisteredRelayRouting {
    public static func hint(realm: UUID, issuer: Data) -> String {
        RelayEndpointController.hex(Data(SHA256.hash(data: Data("offline-rescue/registered-relay/discovery/v1".utf8)
            + Data(realm.uuidString.lowercased().utf8) + issuer))).prefix(16).description
    }
    static func valid(_ hint: String) -> Bool {
        hint.utf8.count == 16 && hint.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// Foreground-only opaque registered relay. Prepared trust belongs to its service, never Bonjour.
@MainActor public final class RegisteredRelayHostNetwork: ObservableObject {
    public let transport = LocalExchangeTransport(registeredRelayTimeout: .seconds(3))
    public let service: RegisteredRelayService
    @Published public private(set) var status = "Registered relay stopped"
    @Published public private(set) var custodyCount = 0
    private let routingHint: String
    private let validate: () throws -> Void
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var cardOffset = 0
    private var candidateOffsets: [Data: Int] = [:]
    private var lastVerified: [Data: NWEndpoint] = [:]
    public init(service: RegisteredRelayService, routingHint: String, validate: @escaping () throws -> Void = {}) {
        self.service = service; self.routingHint = routingHint; self.validate = validate
        custodyCount = (try? service.count()) ?? 0
    }
    deinit { worker?.cancel() }
    public func start(port: UInt16? = nil) throws {
        stop()
        guard RegisteredRelayRouting.valid(routingHint) else { throw EnrollmentError.malformed }
        try validate(); custodyCount = try service.count()
        let run = generation
        transport.onIncoming = { [weak self] bytes in
            guard let self, run == self.generation, self.transport.active else { throw EnrollmentError.stopped }
            try self.validate()
            let result = try self.service.admit(bytes)
            self.custodyCount = try self.service.count()
            self.status = "Holding \(self.custodyCount); waiting for verified destinations"
            return result
        }
        transport.discoveryNameContains = "RescueRegRelayEndpoint-"
        do { try transport.start(name: "RescueRegRelayHost-\(routingHint)-\(UUID().uuidString.prefix(8))", port: port) }
        catch { stop(); throw error }
        status = "Registered relay foreground discovery on"
        worker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(run)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    public func stop() {
        generation = UUID(); worker?.cancel(); worker = nil
        transport.onIncoming = nil; transport.stop()
        cardOffset = 0; candidateOffsets = [:]; lastVerified = [:]
        status = "Registered relay stopped; custody stays saved"
    }
    private func current(_ run: UUID) throws {
        guard run == generation, transport.active, !Task.isCancelled else { throw EnrollmentError.stopped }
        try validate()
    }
    private func tick(_ run: UUID) async {
        do {
            try current(run)
            let cards = service.destinations
            guard !cards.isEmpty else { return }
            var contacts: [Data: NWEndpoint] = [:]
            let selected = (0..<min(4, cards.count)).map { cards[(cardOffset + $0) % cards.count] }
            cardOffset = (cardOffset + selected.count) % cards.count
            for card in selected {
                try current(run)
                let prefix = "RescueRegRelayEndpoint-\(card.fingerprint.prefix(16))-"
                let found = transport.peers.compactMap { result -> NWEndpoint? in
                    if case .service(let name, _, _, _) = result.endpoint, name.hasPrefix(prefix) { return result.endpoint }
                    return nil
                }
                guard !found.isEmpty else { lastVerified[card.digest] = nil; continue }
                var candidates: [NWEndpoint] = []
                if let old = lastVerified[card.digest], found.contains(old) { candidates.append(old) }
                var offset = (candidateOffsets[card.digest] ?? 0) % found.count
                for _ in 0..<found.count {
                    let candidate = found[offset]; offset = (offset + 1) % found.count
                    if !candidates.contains(candidate) { candidates.append(candidate) }
                    if candidates.count == 2 { break }
                }
                candidateOffsets[card.digest] = offset; lastVerified[card.digest] = nil
                for candidate in candidates {
                    do {
                        try current(run)
                        let probe = RelayReadinessProbe(target: card)
                        let answer = try await transport.exchange(probe.bytes, to: candidate)
                        try current(run)
                        try probe.verify(response: answer, card: card)
                        contacts[card.digest] = candidate; lastVerified[card.digest] = candidate
                        break
                    } catch {
                        try current(run)
                    }
                }
            }
            try current(run)
            let outcome = try await service.flush(eligibleDestinations: Set(contacts.keys)) { [weak self] bytes, card in
                guard let self else { throw EnrollmentError.stopped }
                try self.current(run)
                guard let contact = contacts[card.digest] else { throw EnrollmentError.stopped }
                let response = try await self.transport.exchange(bytes, to: contact)
                try self.current(run) // Stop after response must preserve custody.
                return response
            }
            try current(run)
            custodyCount = try service.count()
            switch outcome {
            case .delivered: status = "Verified destination accepted a held packet; custody \(custodyCount)"
            case .empty: status = "Holding \(custodyCount); waiting for verified destinations"
            case .failed(_, _, let reason): status = "Packet remains held: \(reason)"
            case .dropped: status = "Packet remains held"
            }
        } catch {
            guard run == generation else { return }
            status = "Registered relay unavailable; custody stays saved. \(error)"
        }
    }
}

/// Injected registered application operations own enrollment and C++ facts. Upload custody never confirms.
@MainActor public final class RegisteredRelayEndpointNetwork: ObservableObject {
    public let transport = LocalExchangeTransport(registeredRelayTimeout: .seconds(3))
    @Published public private(set) var status = "Registered relay endpoint stopped"
    public let card: SecurePairingCard
    private let routingHint: String
    private let validate: () throws -> Void
    private let answerReadiness: (Data) throws -> Data
    private let receive: (Data) throws -> Data
    private let outgoing: () throws -> [RegisteredRelayPacket]
    private var generation = UUID()
    private var worker: Task<Void, Never>?
    private var hostOffset = 0
    private var packetOffset = 0
    public init(card: SecurePairingCard, routingHint: String, validate: @escaping () throws -> Void = {},
                answerReadiness: @escaping (Data) throws -> Data, receive: @escaping (Data) throws -> Data,
                outgoing: @escaping () throws -> [RegisteredRelayPacket]) {
        self.card = card; self.routingHint = routingHint; self.validate = validate
        self.answerReadiness = answerReadiness; self.receive = receive; self.outgoing = outgoing
    }
    deinit { worker?.cancel() }
    public func start(port: UInt16? = nil) throws {
        stop()
        guard RegisteredRelayRouting.valid(routingHint) else { throw EnrollmentError.malformed }
        try validate()
        let run = generation
        transport.onIncoming = { [weak self] bytes in
            guard let self else { throw EnrollmentError.stopped }
            try self.current(run)
            let response = try bytes.starts(with: Data("ORRQ1".utf8)) ? self.answerReadiness(bytes) : self.receive(bytes)
            try self.current(run)
            return response
        }
        transport.discoveryNameContains = "RescueRegRelayHost-\(routingHint)-"
        do { try transport.start(name: "RescueRegRelayEndpoint-\(card.fingerprint.prefix(16))-\(UUID().uuidString.prefix(8))", port: port) }
        catch { stop(); throw error }
        status = "Looking for prepared registered relays"
        worker = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick(run)
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    public func stop() {
        generation = UUID(); worker?.cancel(); worker = nil
        transport.onIncoming = nil; transport.stop(); hostOffset = 0; packetOffset = 0
        status = "Stopped; unconfirmed messages stay saved"
    }
    private func current(_ run: UUID) throws {
        guard run == generation, transport.active, !Task.isCancelled else { throw EnrollmentError.stopped }
        try validate()
    }
    private func tick(_ run: UUID) async {
        do {
            try current(run)
            let pending = try outgoing()
            guard pending.count <= 16 else { throw EnrollmentError.busy }
            var flows = Set<String>()
            let packets = pending.filter { flows.insert(RelayService.flow(for: $0.packet)).inserted }
            guard !packets.isEmpty else { return }
            let prefix = "RescueRegRelayHost-\(routingHint)-"
            let hosts = transport.peers.compactMap { result -> NWEndpoint? in
                if case .service(let name, _, _, _) = result.endpoint, name.hasPrefix(prefix) { return result.endpoint }
                return nil
            }
            guard !hosts.isEmpty else { return }
            let selected = (0..<min(4, packets.count)).map { packets[(packetOffset + $0) % packets.count] }
            packetOffset = (packetOffset + selected.count) % packets.count
            for wrapper in selected {
                try current(run)
                guard wrapper.packet.sender == card.digest else { throw EnrollmentError.wrongIdentity }
                for _ in 0..<min(2, hosts.count) {
                    let host = hosts[hostOffset % hosts.count]; hostOffset = (hostOffset + 1) % hosts.count
                    do {
                        try current(run)
                        let response = try await transport.exchange(wrapper.bytes, to: host)
                        try current(run)
                        guard try RelayCustodyReceipt.id(from: response) == wrapper.packet.id else { throw RelayProtocolError.wrongPacket }
                        status = "Relay accepted a copy; waiting for signed destination receipt"
                        break
                    } catch {
                        try current(run)
                        status = "No verified receipt yet; messages stay saved. \(error)"
                    }
                }
            }
        } catch {
            guard run == generation else { return }
            status = "Registered relay exchange unavailable; messages stay saved. \(error)"
        }
    }
}
