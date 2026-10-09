import Foundation
import Network
import RescueDemoState
import Darwin

// Sample signed-relay processes on one Mac over explicit loopback ports, Bonjour disabled. Endpoints keep keys
// in the login Keychain; the relay receives only the two public cards. Every command ends with one STATE line.
// Synthetic presets only; sequential process contacts, not radio range, firewall isolation or a mesh.

func emit(_ line: String) {
    print(line)
    fflush(stdout)
}

func usage() -> Never {
    emit("USAGE: rescue-relay-host endpoint [--new-session] <0 public | 1 responder> <absolute-root> <listen-port> <relay-port>")
    emit("USAGE: rescue-relay-host relay <absolute-store-file> <listen-port> <public-card> <public-port> <responder-card> <responder-port>")
    exit(2)
}

func startupFailure(_ reason: Any) -> Never {
    emit("STARTUP ERROR: \(reason)")
    exit(1)
}

func port(_ text: String) -> UInt16? {
    guard let value = UInt16(text), value > 0 else { return nil }
    return value
}

func loopback(_ port: UInt16) -> NWEndpoint { .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!) }

/// Starts the listener and waits a bounded time for it to be ready.
@MainActor func listen(_ transport: LocalExchangeTransport, name: String, port: UInt16) async {
    do {
        try transport.start(name: name, advertise: false, browse: false, port: port)
        let deadline = ContinuousClock.now + .seconds(5)
        while transport.hostPort == nil {
            guard transport.active, ContinuousClock.now < deadline else { startupFailure(transport.status) }
            try await Task.sleep(for: .milliseconds(20))
        }
    } catch { startupFailure(error) }
}

/// Blocking stdin stays off MainActor so listener callbacks keep running between commands.
func readCommands(_ handle: @escaping @MainActor (String) async -> Void, onClose: @escaping @MainActor () -> Void) {
    Task.detached {
        while let line = readLine() { await handle(line) }
        await onClose()
    }
}

@MainActor func runEndpoint(_ arguments: [String]) async {
    let rotate = arguments.first == "--new-session"
    let args = rotate ? Array(arguments.dropFirst()) : arguments
    guard args.count == 4, let roleValue = Int(args[0]), let role = EndpointRole(rawValue: roleValue), args[1].hasPrefix("/"),
          let listenPort = port(args[2]), let relayPort = port(args[3]) else { usage() }
    let secure: SecureEndpointController
    do {
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        secure = try rotate ? SecureEndpointController.newSession(rootURL: root, role: role)
                            : SecureEndpointController(rootURL: root, role: role)
    }
    catch { startupFailure(error) }
    guard secure.endpoint.snapshot != nil else { startupFailure(secure.endpoint.error) }
    let relayEndpoint = RelayEndpointController(secure: secure)
    let transport = LocalExchangeTransport(relayTimeout: .seconds(8))
    transport.onIncoming = { bytes in
        do {
            let acceptance = try relayEndpoint.receive(bytes)
            let packet = try RelayPacket(bytes: bytes)
            emit("INBOUND kind=\(packet.kind) id=\(packet.id) result=accepted")
            return acceptance
        } catch {
            emit("INBOUND ERROR: \(error)")
            throw error
        }
    }
    let label = role == .publicUser ? "public" : "responder"
    await listen(transport, name: "RescueRelayEndpoint-\(label)", port: listenPort)
    emit("READY mode=endpoint role=\(roleValue) port=\(listenPort) relay=\(relayPort)")
    emit("CARD \(secure.card.base64)")
    emit("FINGERPRINT \(secure.card.fingerprint)")
    emit("Commands: card pair <card> sos ack reply correction upload state quit (no direct-send path)")

    func report() {
        guard let s = secure.endpoint.snapshot else { emit("STATE role=\(label) unavailable=true"); return }
        let requests = s.state.messages.filter { $0.kind == .request }.count
        emit("STATE role=\(label) request=\(s.state.hasRequest) requests=\(requests) delivery=\(s.state.originalDelivery) "
             + "pending=\(s.pendingTransfers) messages=\(s.state.messages.count) location=\(s.state.reportedLocation)")
    }
    func act(_ action: DemoAction, _ value: String = "") throws {
        guard try secure.perform(action, value: value) else { throw EndpointError(message: secure.endpoint.error) }
    }
    readCommands({ line in
        let words = line.split(separator: " ").map(String.init)
        do {
            switch words.first {
            case "sos": try act(.sos, "Training Building A · Floor 1")
            case "ack": try act(.acknowledge)
            case "reply": try act(.reply, "SYNTHETIC: your request is being reviewed")
            case "correction": try act(.correction, "Training Building A · Floor 4")
            case "card":
                emit("CARD \(secure.card.base64)")
                emit("FINGERPRINT \(secure.card.fingerprint)")
            case "pair":
                guard words.count == 2 else { throw RelayProtocolError.malformed }
                try secure.pair(words[1])
                emit("PAIRED \(secure.peerCard?.fingerprint ?? "")")
            case "upload":
                do {
                    guard let packet = try relayEndpoint.outgoing() else { emit("UPLOAD result=empty"); break }
                    let response = try await transport.exchange(packet.bytes, to: loopback(relayPort))
                    guard try RelayCustodyReceipt.id(from: response) == packet.id else { throw RelayProtocolError.wrongPacket }
                    // Relay custody only; the outbox clears on the destination's reverse receipt.
                    emit("UPLOADED id=\(packet.id) kind=\(packet.kind) bytes=\(packet.bytes.count)")
                } catch { emit("UPLOAD ERROR: \(error)") }
            case "state": break
            case "quit":
                transport.stop()
                exit(0)
            default: emit("COMMAND ERROR: unknown command; relay endpoints have no direct-send path")
            }
        } catch { emit("COMMAND ERROR: \(error)") }
        report()
    }, onClose: { transport.stop(); exit(0) })
}

@MainActor func runRelay(_ args: [String]) async {
    guard args.count == 6, args[0].hasPrefix("/"), let listenPort = port(args[1]), let publicPort = port(args[3]),
          let responderPort = port(args[5]) else { usage() }
    // Cards are parsed before any store is created.
    let service: RelayService
    do {
        let publicCard = try SecurePairingCard(base64: args[2]), responderCard = try SecurePairingCard(base64: args[4])
        service = try RelayService(storageURL: URL(fileURLWithPath: args[0]), publicCard: publicCard, responderCard: responderCard)
    } catch { startupFailure(error) }
    let transport = LocalExchangeTransport(relayTimeout: .seconds(8))
    transport.onIncoming = { bytes in
        do {
            let custody = try service.admit(bytes)
            let packet = try RelayPacket(bytes: bytes)
            emit("ADMITTED id=\(packet.id) kind=\(packet.kind) bytes=\(bytes.count)")
            return custody
        } catch {
            emit("ADMIT ERROR: \(error)")
            throw error
        }
    }
    await listen(transport, name: "RescueRelay", port: listenPort)
    emit("READY mode=relay port=\(listenPort) public=\(publicPort) responder=\(responderPort)")
    emit("Commands: state flush flush-drop (diagnostic: ignore destination response) quit")

    func report() {
        do { emit("STATE mode=relay count=\(try service.count())") }
        catch { emit("STATE mode=relay count=unavailable") }
    }
    readCommands({ line in
        switch line.split(separator: " ").first {
        case "flush", "flush-drop":
            do {
                let outcome = try await service.flush(dropResponse: line.hasPrefix("flush-drop")) { bytes, role in
                    try await transport.exchange(bytes, to: loopback(role == .publicUser ? publicPort : responderPort))
                }
                switch outcome {
                case .empty: emit("FLUSH result=empty")
                case .delivered(let id, let attempts, let returned):
                    emit("FLUSH result=delivered id=\(id) attempts=\(attempts) returned=\(returned ?? "none")")
                case .dropped(let id, let attempts):
                    emit("FLUSH result=dropped id=\(id) attempts=\(attempts) note=diagnostic-response-ignored")
                case .failed(let id, let attempts, let reason):
                    emit("FLUSH result=failed id=\(id) attempts=\(attempts) reason=\(reason)")
                }
            } catch { emit("COMMAND ERROR: \(error)") }
        case "state": break
        case "quit":
            transport.stop()
            exit(0)
        default: emit("COMMAND ERROR: unknown relay command")
        }
        report()
    }, onClose: { transport.stop(); exit(0) })
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "endpoint": await runEndpoint(Array(arguments.dropFirst()))
case "relay": await runRelay(Array(arguments.dropFirst()))
default: usage()
}
while true { try await Task.sleep(for: .seconds(60)) }
