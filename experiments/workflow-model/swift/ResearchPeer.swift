import Foundation
import Combine
import CryptoKit
@preconcurrency import Network

// Opt-in cooperative floor research between exactly two manually paired opposite-role participants.
// Ephemeral CryptoKit identity per controller, never the rescue identity or stores; nothing is persisted.
// One explicit pull at a time; no polling, forwarding, graph output or peer results are ever sent.
// Transport integrity cannot prove sensor truth or simultaneity.

public enum ResearchFloorSource: String, Codable, Sendable { case appleFloor, relativeAltitude, unavailable }

/// One local original sensor reading. `sampledAt` is this device's systemUptime; Unknown carries no level.
public struct ResearchFloorReading: Equatable, Sendable {
    public let level: Int?
    public let source: ResearchFloorSource
    public let sampledAt: Double
    public let id: UUID
    public init(level: Int?, source: ResearchFloorSource, sampledAt: Double, id: UUID = UUID()) {
        self.level = level; self.source = source; self.sampledAt = sampledAt; self.id = id
    }
}

/// A paired participant's original reading. Provenance is the pinned card fingerprint plus the original id.
/// `ageAtReceipt` is the sender's stated age plus the full measured round trip; later ages add only local elapsed time.
public struct ResearchPeerObservation: Equatable, Sendable {
    public let level: Int?
    public let source: ResearchFloorSource
    public let id: UUID
    public let fingerprint: String
    /// Receiver systemUptime when the response arrived.
    public let receivedAt: Double
    public let ageAtReceipt: Double

    public func age(at time: Double) -> Double { ageAtReceipt + (time - receivedAt) }
    /// False before receipt (clock misuse) or once the conservative age exceeds the limit.
    public func isFresh(at time: Double) -> Bool {
        time >= receivedAt && age(at: time) <= ResearchPeerController.maximumAge
    }
}

public enum ResearchPeerError: Error, Equatable, Sendable, CustomStringConvertible {
    case fingerprintNotChecked, invalidContext, running, notConfigured, notStarted, busy, stopped
    case malformed, wrongChallenge, wrongContext, noLocalReading, staleLocalReading, roundTripTooLong, tooOld

    public var description: String {
        switch self {
        case .fingerprintNotChecked: "Compare the full fingerprint on both devices before pairing"
        case .invalidContext: "Research context must be 1-64 bytes without control characters"
        case .running: "Stop research sharing before changing the pairing or context"
        case .notConfigured: "Pair with the opposite participant and set a context first"
        case .notStarted: "Start research sharing first"
        case .busy: "A pull is already in progress"
        case .stopped: "Research sharing stopped; result discarded"
        case .malformed: "Rejected research message: not a valid bounded message"
        case .wrongChallenge: "Rejected response: it does not answer this request"
        case .wrongContext: "Rejected: research context does not match"
        case .noLocalReading: "No local reading is being shared"
        case .staleLocalReading: "Local reading is too old or from the future to share"
        case .roundTripTooLong: "Rejected response: round trip exceeded 3 seconds"
        case .tooOld: "Rejected response: reading age plus round trip exceeded 10 seconds"
        }
    }
}

/// ORQF1 request / ORPF1 response plaintext inside a SecureEnvelope: canonical sorted-key JSON, at most 1024 bytes.
/// Decoding rejects anything that does not re-encode to the identical bytes (extra/duplicate keys, spacing, order).
enum ResearchWire {
    static let requestDomain = "ORQF1"
    static let responseDomain = "ORPF1"
    static let maximumPlaintext = 1024
    static let challengeSize = 32
    static let levels = -20...200

    struct Request: Codable, Equatable {
        var domain: String
        var challenge: Data
        var context: String
    }

    struct Response: Codable, Equatable {
        var domain: String
        var challenge: Data
        var context: String
        var id: UUID
        var level: Int?
        var source: ResearchFloorSource
        /// Sender's own elapsed seconds since sampling, measured on its own clock only.
        var age: Double
    }

    /// Trimmed, 1...64 UTF-8 bytes, no control characters; nil otherwise.
    static func context(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...64).contains(trimmed.utf8.count),
              !trimmed.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return trimmed
    }

    static func validReading(level: Int?, source: ResearchFloorSource) -> Bool {
        guard let level else { return source == .unavailable }
        return source != .unavailable && levels.contains(level)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Size-checked only; semantic checks belong to the decoders so tests can build hostile values.
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        guard let data = try? encoder().encode(value), (1...maximumPlaintext).contains(data.count) else {
            throw ResearchPeerError.malformed
        }
        return data
    }

    private static func strict<T: Codable>(_ type: T.Type, _ data: Data) throws -> T {
        guard (1...maximumPlaintext).contains(data.count),
              let value = try? JSONDecoder().decode(type, from: data),
              let canonical = try? encoder().encode(value), canonical == data else { throw ResearchPeerError.malformed }
        return value
    }

    static func decodeRequest(_ data: Data) throws -> Request {
        let request = try strict(Request.self, data)
        guard request.domain == requestDomain, request.challenge.count == challengeSize,
              context(request.context) == request.context else { throw ResearchPeerError.malformed }
        return request
    }

    static func decodeResponse(_ data: Data) throws -> Response {
        let response = try strict(Response.self, data)
        guard response.domain == responseDomain, response.challenge.count == challengeSize,
              context(response.context) == response.context,
              validReading(level: response.level, source: response.source),
              response.age.isFinite, (0...ResearchPeerController.maximumAge).contains(response.age) else {
            throw ResearchPeerError.malformed
        }
        return response
    }
}

/// Foreground-only research participant. The owner calls stop() on background or exit; stop, reset and
/// reconfiguration advance a generation so no earlier pull or incoming request can publish afterwards.
@MainActor public final class ResearchPeerController: ObservableObject {
    public nonisolated static let maximumRoundTrip = 3.0
    public nonisolated static let maximumAge = 10.0

    public let transport = LocalExchangeTransport(researchTimeout: .seconds(3))
    @Published public private(set) var card: SecurePairingCard
    @Published public private(set) var peerCard: SecurePairingCard?
    @Published public private(set) var status = "Research sharing off; not paired"
    @Published public private(set) var busy = false
    @Published public private(set) var observation: ResearchPeerObservation?

    private(set) var identity: SecureIdentity
    private(set) var context: String?
    private(set) var localReading: ResearchFloorReading?
    private var envelope: SecureEnvelope?
    private var generation = UUID()
    /// Local monotonic clock; injectable for tests. Never compared with a remote clock.
    var now: @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }

    public init(role: EndpointRole = .publicUser) {
        identity = SecureIdentity(role: role)
        card = identity.card
    }

    /// Stops, discards the pairing and every reading, and creates fresh ephemeral keys.
    public func reset(role: EndpointRole) {
        stop()
        identity = SecureIdentity(role: role)
        card = identity.card
        peerCard = nil; envelope = nil; context = nil
        status = "New research identity; not paired"
    }

    /// Pins the opposite participant's card for one manually matched context. Only while stopped; clears readings.
    /// A rejected draft leaves the current pairing unchanged.
    public func configure(peerBase64: String, context text: String, checkedFingerprint: Bool) throws {
        guard !transport.active else { throw ResearchPeerError.running }
        guard checkedFingerprint else { throw ResearchPeerError.fingerprintNotChecked }
        let peer = try SecurePairingCard(base64: peerBase64.trimmingCharacters(in: .whitespacesAndNewlines))
        let sealed = try SecureEnvelope(identity: identity, peer: peer)
        guard let context = ResearchWire.context(text) else { throw ResearchPeerError.invalidContext }
        generation = UUID()
        envelope = sealed; peerCard = peer; self.context = context
        localReading = nil; observation = nil; busy = false
        status = "Paired for research context; sharing off"
    }

    /// Shares only this device's own original sensor reading. Nil or inconsistent values clear sharing.
    public func updateLocalReading(_ reading: ResearchFloorReading?) {
        guard let reading else { localReading = nil; return }
        guard reading.sampledAt.isFinite, ResearchWire.validReading(level: reading.level, source: reading.source) else {
            localReading = nil
            status = "Local reading not shared: inconsistent level or source"
            return
        }
        localReading = reading
    }

    public var configuredContext: String? { context }

    public func start(port: UInt16? = nil) throws { try start(port: port, discovery: true) }

    /// `discovery: false` listens without Bonjour (loopback tests and manual addresses).
    func start(port: UInt16?, discovery: Bool) throws {
        guard let envelope, let context else { throw ResearchPeerError.notConfigured }
        generation = UUID()
        let run = generation
        transport.onIncoming = { [weak self] packet in
            guard let self, self.generation == run, self.transport.active else { throw ResearchPeerError.stopped }
            do { return try self.respond(to: packet, envelope: envelope, context: context) } catch {
                self.status = "Rejected incoming research request: \(error)"
                throw error
            }
        }
        do {
            // Role-only name: no identifiers broadcast, and opposite roles never collide or hide each other.
            let name = identity.role == .publicUser ? "Floor research public" : "Floor research responder"
            try transport.start(name: name, advertise: discovery, browse: discovery, port: port)
        } catch {
            transport.onIncoming = nil
            status = "Research sharing could not start: \(error)"
            throw error
        }
        status = "Research sharing on; answering explicit pulls from the paired participant"
    }

    /// Fences pending work, closes sockets and clears local and remote readings.
    public func stop() {
        generation = UUID()
        transport.onIncoming = nil
        transport.stop()
        localReading = nil; observation = nil; busy = false
        status = peerCard == nil ? "Research sharing off; not paired" : "Research sharing off; readings cleared"
    }

    public func requestObservation(to endpoint: NWEndpoint) async {
        let run = generation
        do { _ = try await pull(to: endpoint) } catch ResearchPeerError.busy {
            status = "A pull is already in progress"
        } catch {
            if run == generation { status = "Peer observation rejected or failed: \(error)" }
        }
    }

    /// One challenge-bound pull. Throws instead of publishing on any check failure or generation change.
    func pull(to endpoint: NWEndpoint) async throws -> ResearchPeerObservation {
        guard !busy else { throw ResearchPeerError.busy }
        guard let envelope, let context, let peerCard else { throw ResearchPeerError.notConfigured }
        guard transport.active else { throw ResearchPeerError.notStarted }
        let run = generation
        busy = true
        defer { if run == generation { busy = false } }
        let challenge = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let request = ResearchWire.Request(domain: ResearchWire.requestDomain, challenge: challenge, context: context)
        let packet = try envelope.seal(try ResearchWire.encode(request))
        status = "Requesting the paired participant's reading"
        let sentAt = now()
        let reply: Data
        do { reply = try await transport.exchange(packet, to: endpoint) } catch {
            guard run == generation else { throw ResearchPeerError.stopped }
            throw error
        }
        let receivedAt = now()
        guard run == generation, transport.active else { throw ResearchPeerError.stopped }
        let response = try ResearchWire.decodeResponse(try envelope.open(reply))
        guard response.challenge == challenge else { throw ResearchPeerError.wrongChallenge }
        guard response.context == context else { throw ResearchPeerError.wrongContext }
        let roundTrip = receivedAt - sentAt
        guard roundTrip.isFinite, (0...Self.maximumRoundTrip).contains(roundTrip) else { throw ResearchPeerError.roundTripTooLong }
        // Conservative: the whole round trip counts as reading age; the sender's clock is never compared with ours.
        let age = response.age + roundTrip
        guard age <= Self.maximumAge else { throw ResearchPeerError.tooOld }
        let result = ResearchPeerObservation(level: response.level, source: response.source, id: response.id,
                                             fingerprint: peerCard.fingerprint, receivedAt: receivedAt, ageAtReceipt: age)
        observation = result
        status = "Received the paired participant's own sensor reading"
        return result
    }

    private func respond(to packet: Data, envelope: SecureEnvelope, context: String) throws -> Data {
        let request = try ResearchWire.decodeRequest(try envelope.open(packet))
        guard request.context == context else { throw ResearchPeerError.wrongContext }
        guard let reading = localReading else { throw ResearchPeerError.noLocalReading }
        let age = now() - reading.sampledAt
        guard age.isFinite, (0...Self.maximumAge).contains(age) else { throw ResearchPeerError.staleLocalReading }
        let response = ResearchWire.Response(domain: ResearchWire.responseDomain, challenge: request.challenge, context: context,
                                             id: reading.id, level: reading.level, source: reading.source, age: age)
        let sealed = try envelope.seal(try ResearchWire.encode(response))
        status = "Shared this device's own reading with the paired participant"
        return sealed
    }
}
