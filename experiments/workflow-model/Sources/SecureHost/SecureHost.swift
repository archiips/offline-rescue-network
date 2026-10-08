import Foundation
import Network
import RescueDemoState
import Darwin

@main struct SecureHost {
    @MainActor static func main() async {
        do { try await run() }
        catch { print("SECURE HOST ERROR: \(error)"); exit(2) }
    }
    @MainActor static func run() async throws {
        var args=Array(CommandLine.arguments.dropFirst())
        let newSession = args.first == "--new-session"
        if newSession { args.removeFirst() }
        guard args.count == 3, let roleValue=Int(args[0]), let role=EndpointRole(rawValue:roleValue),
              args[1].hasPrefix("/"), let port=UInt16(args[2]), port>0 else {
            print("Usage: rescue-secure-host [--new-session] <0 public | 1 responder> <absolute sample-root> <port>")
            exit(2)
        }
        let root = URL(fileURLWithPath:args[1],isDirectory:true)
        let secure = try newSession ? SecureEndpointController.newSession(rootURL:root,role:role) : SecureEndpointController(rootURL:root,role:role)
        let endpoint=secure.endpoint
        guard endpoint.snapshot != nil else { print("STORE ERROR: \(endpoint.error)");exit(2) }
        let transport=LocalExchangeTransport(secure:true)
        transport.onIncoming={ packet in
            let receipt=try secure.accept(packet)
            report(endpoint,"INBOUND SAVED")
            return receipt
        }
        let name="RescueSecure-\(role == .publicUser ? "Public" : "Responder")-\(UUID().uuidString.prefix(8))"
        try transport.start(name:name,port:port)
        while transport.hostPort == nil {
            try await Task.sleep(for:.milliseconds(30))
            guard transport.active else { throw NSError(domain:"Host did not start",code:1) }
        }
        print("READY role=\(roleValue) port=\(port) name=\(name)");fflush(stdout)
        print("CARD \(secure.card.base64)")
        print("FINGERPRINT \(secure.card.fingerprint)")
        print("Commands: card pair <public-card> sos ack reply correction assign resolve withdrawal disposition reopen state peers send <peer-port> send-peer <Bonjour-name> quit");fflush(stdout)
        // Blocking stdin stays off MainActor so listener callbacks can keep committing messages.
        Task.detached {
            while let line=readLine() { await command(line,secure:secure,transport:transport) }
            await MainActor.run { transport.stop();exit(0) }
        }
        while true { try await Task.sleep(for:.seconds(60)) }
    }
    @MainActor static func report(_ endpoint:EndpointController,_ label:String) {
        if let s=endpoint.snapshot {
            print("\(label) role=\(s.role) request=\(s.state.hasRequest) delivery=\(s.state.originalDelivery.rawValue) pending=\(s.pendingTransfers) location=\(s.state.reportedLocation) messages=\(s.state.messages.count)")
        } else { print("STATE UNAVAILABLE") }
        if !endpoint.error.isEmpty { print("ERROR: \(endpoint.error)") }
        fflush(stdout)
    }
    @MainActor static func command(_ line:String,secure:SecureEndpointController,transport:LocalExchangeTransport) async {
        let endpoint=secure.endpoint
        let words=line.split(separator:" ")
        do {
        switch words.first {
        case "sos":try secure.perform(.sos,value:"Training Building A · Floor 1")
        case "ack":try secure.perform(.acknowledge)
        case "reply":try secure.perform(.reply,value:"SYNTHETIC: your request is being reviewed")
        case "correction":try secure.perform(.correction,value:"Training Building A · Floor 4")
        case "assign":try secure.perform(.assign,value:"Training Team A")
        case "resolve":try secure.perform(.resolve,value:"SYNTHETIC: training assistance completed")
        case "withdrawal":try secure.perform(.withdrawal,value:"SYNTHETIC withdrawal request")
        case "disposition":try secure.perform(.disposition,value:"SYNTHETIC: withdrawal reviewed; handling unchanged")
        case "reopen":try secure.perform(.reopen,value:"SYNTHETIC: review late information")
        case "card":print("CARD \(secure.card.base64)");print("FINGERPRINT \(secure.card.fingerprint)")
        case "pair":
            guard words.count == 2 else { print("PAIR ERROR: expected public card");fflush(stdout);return }
            do { try secure.pair(String(words[1]));print("PAIRED \(secure.peerCard!.fingerprint)") }
            catch { print("PAIR ERROR: \(error)") }
        case "state":break
        case "peers":for peer in transport.peers { print("PEER \(peer.endpoint)") }
        case "quit":transport.stop();exit(0)
        case "send", "send-peer":
            guard words.count==2 else { print("Specify sample peer");fflush(stdout);return }
            let destination: NWEndpoint
            if words[0] == "send", let port=UInt16(words[1]),port>0 {
                destination = .hostPort(host:"127.0.0.1",port:NWEndpoint.Port(rawValue:port)!)
            } else if words[0] == "send-peer", let peer=transport.peers.first(where: {
                if case .service(let name, _, _, _) = $0.endpoint { return name == String(words[1]) };return false
            }) { destination=peer.endpoint }
            else { print("Sample peer unavailable; use peers");fflush(stdout);return }
            do {
                for _ in 0..<64 {
                    guard let packet=try secure.nextPacket() else { break }
                    let receipt=try await transport.exchange(packet,to:destination)
                    try secure.confirm(receipt)
                }
            } catch { print("TRANSFER ERROR: \(error)") }
        default:print("Unknown sample command")
        }
        } catch { print("ERROR: Secure action was not saved: \(error)") }
        report(endpoint,"STATE")
    }
}
