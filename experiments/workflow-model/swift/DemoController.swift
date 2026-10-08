import Foundation
import Combine
import RescueDemoBridge
@preconcurrency import Network

private final class CoreHandle {
    let pointer: OpaquePointer?
    init(storageURL: URL?) {
        if let storageURL { pointer = rc_open(storageURL.path) }
        else { pointer = rc_create() }
    }
    deinit { rc_destroy(pointer) }
}
@MainActor public final class DemoController: ObservableObject {
    private let storageURL: URL?
    private var core: CoreHandle?
    private var endpoint: EndpointController?
    private var peer: NWEndpoint?
    private var exchangeGeneration = UUID()
    public let transport = LocalExchangeTransport()
    @Published public private(set) var localRole: EndpointRole?
    @Published public private(set) var exchangeBusy = false
    @Published public private(set) var snapshot: DemoSnapshot?
    @Published public private(set) var error = ""
    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        retrySavedSession()
    }
    public func useLocalRole(_ role: EndpointRole) {
        guard let storageURL else { error = "Local exchange needs a saved sample session."; return }
        stopLocalExchange()
        localRole = role
        endpoint = EndpointController(storageURL: storageURL.deletingLastPathComponent().appendingPathComponent("local-\(role.rawValue).sqlite"), role: role)
        endpoint?.onChange = { [weak self] in self?.refreshEndpoint() }
        transport.onIncoming = { [weak self] packet in
            guard let self, let endpoint = self.endpoint, self.localRole != nil else { throw EndpointError(message: "Sample endpoint stopped") }
            return try endpoint.accept(packet)
        }
        refreshEndpoint()
    }
    public func useTraining() {
        stopLocalExchange(); endpoint = nil; localRole = nil
        retrySavedSession()
    }
    public func startLocalExchange() {
        guard let role = localRole, endpoint?.snapshot != nil else { return }
        do { try transport.start(name: "RescueSample-\(role == .publicUser ? "Public" : "Responder")-\(UUID().uuidString.prefix(8))") }
        catch { self.error = "Could not start local exchange: \(error)" }
    }
    public func stopLocalExchange() {
        exchangeGeneration = UUID(); exchangeBusy = false; peer = nil; transport.stop()
    }
    public func transferQueued(to destination: NWEndpoint) async {
        guard localRole != nil, let endpoint, transport.active, !exchangeBusy else { return }
        peer = destination; exchangeBusy = true
        let run = exchangeGeneration
        defer { if run == exchangeGeneration { exchangeBusy = false } }
        do {
            for _ in 0..<64 {
                guard run == exchangeGeneration, let packet = try endpoint.nextPacket() else { break }
                let receipt = try await transport.exchange(packet, to: destination)
                guard run == exchangeGeneration else { return }
                try endpoint.confirm(receipt)
            }
        } catch { if run == exchangeGeneration { peer = nil; self.error = "Transfer stopped; unconfirmed messages stay saved. \(error)" } }
    }
    private func refreshEndpoint() {
        guard let endpoint else { return }
        error = endpoint.error
        guard let state = endpoint.snapshot else { snapshot = nil; return }
        snapshot = DemoSnapshot(persistent: true, connected: false, pendingTransfers: state.pendingTransfers, error: state.error,
            publicState: localRole == .publicUser ? state.state : .empty,
            responderState: localRole == .responder ? state.state : .empty)
    }
    public func retrySavedSession() {
        if localRole != nil { endpoint?.reopen(); refreshEndpoint(); return }
        if storageURL == nil, core?.pointer != nil { refresh(); return }
        core = nil
        do {
            if let storageURL {
                guard storageURL.isFileURL else { throw URLError(.badURL) }
                try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            core = CoreHandle(storageURL: storageURL)
            refresh()
        } catch {
            snapshot = nil
            self.error = "Could not access the saved sample session. Retry when storage is available."
        }
    }
    public func perform(_ action: DemoAction, value: String = "", reference: String = "") {
        if let endpoint, localRole != nil {
            endpoint.perform(action, value: value, reference: reference)
            if let peer, transport.active {
                let run = exchangeGeneration
                Task { guard run == self.exchangeGeneration else { return }; await self.transferQueued(to: peer) }
            }
            return
        }
        let result = rc_perform(core?.pointer, Int32(action.rawValue), value, reference)
        refresh()
        if result != 0 && result != 1 && error.isEmpty { error = "Action was not saved (\(result)). Check the current request state." }
    }
    public func setConnected(_ connected: Bool) {
        guard localRole == nil else { return }
        let result = rc_set_connected(core?.pointer, connected ? 1 : 0)
        refresh()
        if result != 0 && error.isEmpty { error = "Could not save the simulated connection change." }
    }
    public func reset() {
        if let endpoint, localRole != nil { stopLocalExchange(); endpoint.reset(); return }
        let result = rc_reset(core?.pointer)
        refresh()
        if result != 0 && error.isEmpty { error = "Could not reset the sample session. Previous data is retained." }
    }
    private func refresh() {
        guard let pointer = core?.pointer else {
            snapshot = nil
            error = storageURL == nil ? "Could not start the sample session." : "Could not open the saved sample session. The file has been preserved."
            return
        }
        guard let data = rc_snapshot(pointer) else { snapshot = nil; error = "Could not read demo state."; return }
        defer { rc_free(data) }
        do { snapshot = try JSONDecoder().decode(DemoSnapshot.self, from: Data(String(cString: data).utf8)); error = snapshot?.error ?? "" }
        catch { snapshot = nil; self.error = "Could not decode demo state." }
    }
}

private extension DeviceSnapshot {
    static var empty: DeviceSnapshot { DeviceSnapshot(hasRequest: false, reportedLocation: "", originalDelivery: .waiting, handling: .open,
        assignedTo: "", reason: "", withdrawalPending: false, withdrawalDisposition: "", lateUpdate: false, pendingPublicMessages: 0, messages: []) }
}
