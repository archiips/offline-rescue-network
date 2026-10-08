import SwiftUI
import ProbeTransport

@main struct ProbeApp: App {
    @StateObject private var transport = ProbeTransport()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Connection test").font(.largeTitle.bold())
                        Text("Fixed synthetic messages only. Hosts are unverified. This tool cannot send an SOS.")
                        Text(transport.status).font(.headline).accessibilityIdentifier("probeStatus")
                        HStack {
                            Button("Find test host") { transport.browse() }
                                .buttonStyle(.borderedProminent)
                            Button("Stop") { transport.stop() }.buttonStyle(.bordered)
                        }
                        Button("Host on this device") {
                            do { try transport.startHosting() }
                            catch { setupError = String(describing: error) }
                        }.buttonStyle(.bordered)
                        if let setupError { Text(setupError).foregroundStyle(.red) }
                        if transport.peers.isEmpty { Text("No discovered hosts. Start the Mac host, then search. Allow Local Network access when asked.") }
                        ForEach(transport.peers, id: \.endpoint) { peer in
                            Button {
                                transport.send(to: peer.endpoint)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(String(describing: peer.endpoint))
                                    Text("Send synthetic test frame").font(.caption)
                                }
                            }.buttonStyle(.bordered).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Device receipts: \(transport.receiptCount)")
                        Text("A receipt proves this test exchange, not human acknowledgment or responder identity. Keep the app open; backgrounding it stops the test.")
                        Divider()
                        Text("Recent events").font(.title2)
                        ForEach(Array(transport.logs.suffix(12).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote).textSelection(.enabled)
                        }
                    }.padding()
                }.navigationTitle("Rescue Network Probe").navigationBarTitleDisplayMode(.inline)
            }
        }.onChange(of: scenePhase) { _, phase in
            if phase == .background { transport.stop() }
        }
    }
    @State private var setupError: String?
}
