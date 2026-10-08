import Foundation
import ProbeTransport

@main struct Host {
    @MainActor static func main() async throws {
        let host = ProbeTransport()
        try host.startHosting()
        print("Synthetic test host: \(host.hostName)")
        print("Keep this running; allow Local Network if requested. No rescue data or identity verification.")
        // Event callback remains live after the bounded UI log rolls over.
        host.onEvent = { print($0) }
        while true { try await Task.sleep(for: .seconds(1)) }
    }
}
