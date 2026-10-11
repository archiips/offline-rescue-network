import Foundation
@preconcurrency import Network

/// Explicitly opened synthetic organizer LAN service. No advertising or discovery, no deployment.
/// The caller is responsible for obtaining local-network authorization before starting it.
@MainActor public final class OrganizerPreparationHost {
    public let transport = LocalExchangeTransport(preparationTimeout: .seconds(3))
    private let service: OrganizerPreparationService
    private let elapsed: () -> Double
    private var recent: [Double] = []
    private var lastTime: Double?
    private var stopped = false
    public init(service: OrganizerPreparationService, elapsed: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.service = service; self.elapsed = elapsed
        transport.onIncoming = { [weak self] input in
            guard let self else { throw EnrollmentError.stopped }
            return try self.receive(input)
        }
    }
    /// Listens on local interfaces; does NOT imply loopback-only binding.
    public func start(port: UInt16? = nil) throws {
        guard !stopped else { throw EnrollmentError.stopped }
        guard !transport.active else { throw EnrollmentError.busy }
        try transport.start(name: "Synthetic organizer preparation", advertise: false, browse: false, port: port)
    }
    private func receive(_ input: Data) throws -> Data {
        guard !stopped, transport.active else { throw EnrollmentError.stopped }
        let time = elapsed()
        guard time.isFinite, lastTime.map({ time >= $0 }) ?? true else { throw EnrollmentError.expired }
        lastTime = time
        recent.removeAll { time - $0 >= 60 }
        guard recent.count < 64 else { throw EnrollmentError.busy }
        recent.append(time)
        if let hello = try? EnrollmentWire.decode(OrganizerPreparationHello.self, input), hello.domain == "OREQ1" {
            return try service.challenge(input)
        }
        return try service.issue(input)
    }
    public func stop() { stopped = true; transport.stop(); service.stop(); recent = [] }
}

/// Two bounded local socket exchanges during preparation. Returns staged-profile bytes only;
/// independent issuer approval remains in the native preparation flow.
@MainActor public final class OrganizerPreparationNetworkClient {
    private let transport = LocalExchangeTransport(preparationTimeout: .seconds(3))
    private var generation = UUID()
    private var active = false
    private var current: OrganizerPreparationClient?
    var pendingSessions: Int { transport.pendingSessions }
    public init() {}
    public func stop() {
        generation = UUID(); active = false; transport.stop(); current?.stop(); current = nil
    }
    public func request(host: String, port: UInt16, client: OrganizerPreparationClient) async throws -> Data {
        guard !active else { throw EnrollmentError.busy }
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.isWhitespace }),
              port > 0, let port = NWEndpoint.Port(rawValue: port) else { throw EnrollmentError.malformed }
        try Task.checkCancellation()
        active = true; current = client
        let run = generation
        defer { if run == generation { stop() } }
        try transport.start(name: "Synthetic preparation client", advertise: false, browse: false)
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: port)
        let challenge = try await transport.exchange(client.hello(), to: endpoint)
        guard active, run == generation else { throw EnrollmentError.stopped }
        try Task.checkCancellation()
        let result = try await transport.exchange(client.prove(challenge), to: endpoint)
        guard active, run == generation else { throw EnrollmentError.stopped }
        try Task.checkCancellation()
        return try client.profile(result)
    }
}
