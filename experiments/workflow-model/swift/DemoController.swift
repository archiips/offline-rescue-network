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
    private var secureEndpoint: SecureEndpointController?
    private var relayEndpoint: RelayEndpointController?
    @Published public private(set) var relayMode = false
    @Published public private(set) var relayStatus = ""
    private var secureRecordStore: (any SecureRecordStore)?
    @Published public private(set) var secureMode = false
    public var secureCard: SecurePairingCard? { secureEndpoint?.card }
    public var pairedCard: SecurePairingCard? { secureEndpoint?.peerCard }
    private var peer: NWEndpoint?
    private var exchangeGeneration = UUID()
    @Published public private(set) var transport = LocalExchangeTransport()
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
        secureEndpoint = nil; relayEndpoint = nil; relayMode = false; secureMode = false; transport = LocalExchangeTransport()
        localRole = role
        endpoint = EndpointController(storageURL: storageURL.deletingLastPathComponent().appendingPathComponent("local-\(role.rawValue).sqlite"), role: role)
        endpoint?.onChange = { [weak self] in self?.refreshEndpoint() }
        transport.onIncoming = { [weak self] packet in
            guard let self, let endpoint = self.endpoint, self.localRole != nil else { throw EndpointError(message: "Sample endpoint stopped") }
            return try endpoint.accept(packet)
        }
        refreshEndpoint()
    }
    public func useSecureRole(_ role: EndpointRole, recordStore: (any SecureRecordStore)? = nil, viaRelay: Bool = false) {
        guard let storageURL else { error = "Secure exchange needs a saved sample session."; return }
        stopLocalExchange()
        localRole = role; secureMode = true; relayMode = viaRelay; relayEndpoint = nil; secureRecordStore = recordStore; endpoint = nil; secureEndpoint = nil; snapshot = nil
        transport = viaRelay ? LocalExchangeTransport(relayTimeout: .seconds(8)) : LocalExchangeTransport(secure: true)
        do {
            let secure = try SecureEndpointController(rootURL: storageURL.deletingLastPathComponent(), role: role, recordStore: recordStore)
            secureEndpoint = secure; endpoint = secure.endpoint
            bindSecureEndpoint()
            refreshEndpoint()
        } catch { self.error = "Secure session unavailable: \(error)" }
    }
    @discardableResult public func pairSecurePeer(_ card: String) -> Bool {
        guard let secureEndpoint else { error = "Secure session unavailable"; return false }
        do { try secureEndpoint.pair(card); error = ""; objectWillChange.send(); return true }
        catch { self.error = "Pairing rejected: \(error)"; return false }
    }
    /// Changes only the connection route: identity, pairing and C++ history stay the same.
    public func useRelayRoute(_ enabled: Bool) {
        guard secureMode, relayMode != enabled else { return }
        stopLocalExchange()
        relayMode = enabled
        transport = enabled ? LocalExchangeTransport(relayTimeout: .seconds(8)) : LocalExchangeTransport(secure: true)
        bindSecureEndpoint()
        error = ""
    }
    private func bindSecureEndpoint() {
        relayEndpoint = relayMode ? secureEndpoint.map { RelayEndpointController(secure: $0) } : nil
        endpoint?.onChange = { [weak self] in self?.refreshEndpoint() }
        let run = exchangeGeneration
        let relay = relayEndpoint
        let secure = secureEndpoint
        transport.onIncoming = { [weak self] packet in
            guard let self, run == self.exchangeGeneration, let secure, self.secureMode else {
                throw EndpointError(message: "Secure endpoint stopped")
            }
            if let relay {
                let acceptance = try relay.receive(packet)
                self.relayStatus = "" // a custody hint must never outlive newer device facts
                self.refreshEndpoint()
                return acceptance
            }
            return try secure.accept(packet)
        }
    }
    /// Upload one saved head only. An unsigned custody response never confirms C++ delivery.
    public func uploadViaRelay(host: String, port: String) async {
        guard relayMode, let relayEndpoint, transport.active, !exchangeBusy else { return }
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !port.isEmpty, port.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = UInt16(port), number > 0, let value = NWEndpoint.Port(rawValue: number) else {
            error = "Enter a relay host and a port from 1 to 65535."; relayStatus = ""; return
        }
        let run = exchangeGeneration, channel = transport
        exchangeBusy = true; error = ""; relayStatus = ""
        defer { if run == exchangeGeneration { exchangeBusy = false } }
        do {
            guard let packet = try relayEndpoint.outgoing() else { relayStatus = "No queued message to upload."; return }
            let original = try endpoint?.nextPacket()
            let response = try await channel.exchange(packet.bytes, to: .hostPort(host: NWEndpoint.Host(host), port: value))
            guard run == exchangeGeneration else { return }
            guard try RelayCustodyReceipt.id(from: response) == packet.id else { throw RelayProtocolError.wrongPacket }
            if try endpoint?.nextPacket() == original {
                relayStatus = "Relay accepted a copy; waiting for device receipt."
            }
        } catch {
            guard run == exchangeGeneration else { return }
            self.error = "Relay upload stopped; unconfirmed messages stay saved. \(error)"
        }
    }
    public func useTraining() {
        stopLocalExchange(); endpoint = nil; secureEndpoint = nil; relayEndpoint = nil; relayMode = false; secureMode = false; localRole = nil; transport = LocalExchangeTransport()
        retrySavedSession()
    }
    public func startLocalExchange(port: UInt16? = nil) {
        guard let role = localRole, endpoint?.snapshot != nil else { return }
        guard !secureMode || pairedCard != nil else { error = "Pair with the opposite sample endpoint first."; return }
        // stop() invalidates callback generations; bind again for this explicit listener run.
        stopLocalExchange()
        if secureMode { bindSecureEndpoint() }
        error = ""
        do { try transport.start(name: "\(secureMode ? "RescueSecure" : "RescueSample")-\(role == .publicUser ? "Public" : "Responder")-\(UUID().uuidString.prefix(8))",
                                 advertise: !relayMode, browse: !relayMode, port: port) }
        catch { self.error = "Could not start local exchange: \(error)" }
    }
    public func stopLocalExchange() {
        exchangeGeneration = UUID(); exchangeBusy = false; peer = nil; relayStatus = ""; transport.stop()
    }
    public func transferQueued(to destination: NWEndpoint) async {
        guard !relayMode, localRole != nil, let endpoint, transport.active, !exchangeBusy else { return }
        let secure = secureEndpoint
        guard !secureMode || secure?.peerCard != nil else { error = "Pair before transferring saved messages."; return }
        let channel = transport
        peer = destination; exchangeBusy = true
        let run = exchangeGeneration
        defer { if run == exchangeGeneration { exchangeBusy = false } }
        do {
            for _ in 0..<64 {
                guard run == exchangeGeneration, let packet = try (secure != nil ? secure!.nextPacket() : endpoint.nextPacket()) else { break }
                let receipt = try await channel.exchange(packet, to: destination)
                guard run == exchangeGeneration else { return }
                if let secure { try secure.confirm(receipt) } else { try endpoint.confirm(receipt) }
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
        if let role = localRole {
            stopLocalExchange()
            if secureMode {
                if let secureEndpoint {
                    do { try secureEndpoint.reopen(); endpoint = secureEndpoint.endpoint; bindSecureEndpoint(); refreshEndpoint() }
                    catch { self.error = "Secure reopen failed: \(error)" }
                } else { useSecureRole(role, recordStore: secureRecordStore, viaRelay: relayMode) }
            } else { endpoint?.reopen(); refreshEndpoint() }
            return
        }
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
        if localRole != nil {
            guard let endpoint else { error = "Local endpoint unavailable; action was not saved."; return }
            do {
                if let secureEndpoint { try secureEndpoint.perform(action, value: value, reference: reference) }
                else { endpoint.perform(action, value: value, reference: reference) }
            } catch { self.error = "Action was not saved: \(error)"; return }
            if !relayMode, let peer, transport.active {
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
        if localRole != nil {
            stopLocalExchange()
            if secureMode {
                guard let secure = secureEndpoint else {
                    guard let role = localRole, let storageURL else { return }
                    do {
                        let fresh = try SecureEndpointController.newSession(rootURL: storageURL.deletingLastPathComponent(), role: role, recordStore: secureRecordStore)
                        secureEndpoint = fresh; endpoint = fresh.endpoint; bindSecureEndpoint(); refreshEndpoint()
                    } catch { self.error = "New secure session failed: \(error)" }
                    return
                }
                do { try secure.resetSession(); endpoint = secure.endpoint; bindSecureEndpoint(); refreshEndpoint() }
                catch { endpoint = secure.endpoint; bindSecureEndpoint(); refreshEndpoint(); self.error = "New secure session failed: \(error)" }
            } else { endpoint?.reset() }
            return
        }
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
