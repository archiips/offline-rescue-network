import SwiftUI
import RescueDemoState

/// A separate foreground workspace. Endpoint identity/history is not repurposed as relay custody.
struct PhoneRelayView: View {
    @EnvironmentObject private var demo: DemoController
    @EnvironmentObject private var relay: NativeRelayHostController
    var body: some View {
        PhoneRelayForm(relay: relay, transport: relay.transport)
            .navigationTitle("Host a relay")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { demo.stopLocalExchange() }
            .onDisappear { relay.stop() }
    }
}

private struct PhoneRelayForm: View {
    @ObservedObject var relay: NativeRelayHostController
    @ObservedObject var transport: LocalExchangeTransport
    @State private var publicText = ""
    @State private var responderText = ""
    @State private var checked = false
    @AppStorage("phoneRelayListenPort") private var listenPort = "47100"
    @AppStorage("phoneRelayPublicHost") private var publicHost = "127.0.0.1"
    @AppStorage("phoneRelayPublicPort") private var publicPort = ""
    @AppStorage("phoneRelayResponderHost") private var responderHost = "127.0.0.1"
    @AppStorage("phoneRelayResponderPort") private var responderPort = ""

    var body: some View {
        Form {
            Section {
                Text("Carry encrypted messages between two checked endpoints. This device cannot read their private message bodies.")
                Text("Keep this screen open. Listening and forwarding are manual; leaving it or backgrounding stops networking.")
                    .foregroundStyle(.secondary)
            } header: { Text("Controlled foreground relay") }
            Section {
                LabeledContent("Saved encrypted packets", value: "\(relay.custodyCount)")
                LabeledContent("Networking", value: transport.active ? "Starting / listening" : "Stopped")
                if let port = transport.hostPort { LabeledContent("Listening port", value: "\(port.rawValue)") }
                Text(transport.status).font(.caption).foregroundStyle(.secondary)
                if !relay.status.isEmpty { Text(relay.status).font(.subheadline) }
                if !relay.error.isEmpty { Text(relay.error).foregroundStyle(.red) }
                TextField("Listen port", text: $listenPort).keyboardType(.numberPad)
                    .disabled(transport.active || relay.flushBusy)
                if transport.active {
                    Button("Stop relay", role: .destructive) { relay.stop() }
                } else {
                    Button("Start relay listener") { relay.start(port: UInt16(listenPort)) }
                        .disabled(!relay.configured || relay.flushBusy || UInt16(listenPort) == nil || UInt16(listenPort) == 0)
                }
            } header: { Text("Custody and connection") } footer: {
                Text("Custody only means this device saved an encrypted copy. The sender waits for the destination’s signed receipt. This does not contact emergency services.")
            }
            Section {
                cardEntry("Public endpoint card", text: $publicText, expected: .publicUser)
                cardEntry("Responder endpoint card", text: $responderText, expected: .responder)
                Toggle("I checked both complete fingerprints", isOn: $checked)
                Button("Save relay profile") {
                    if relay.configure(publicCard: publicText.trimmingCharacters(in: .whitespacesAndNewlines), responderCard: responderText.trimmingCharacters(in: .whitespacesAndNewlines)) { checked = false }
                }.disabled(!checked || relay.flushBusy || transport.active)
            } header: { Text("Checked public cards") } footer: {
                Text("Copy each public card from its endpoint and compare the complete fingerprints there. Never enter private keys. Stop listening before changing pairs. Each pair selects a separate queue; older profile files are retained.")
            }
            .disabled(relay.flushBusy)
            .onChange(of: publicText) { _, value in
                if value.count > 256 { publicText = String(value.prefix(256)) }; checked = false
            }
            .onChange(of: responderText) { _, value in
                if value.count > 256 { responderText = String(value.prefix(256)) }; checked = false
            }
            if relay.configured {
                Section {
                    if let card = relay.publicCard { fingerprint("Saved public fingerprint", card.fingerprint) }
                    if let card = relay.responderCard { fingerprint("Saved responder fingerprint", card.fingerprint) }
                } header: { Text("Active saved profile") }
            }
            Section {
                TextField("Public host", text: $publicHost)
                TextField("Public port", text: $publicPort).keyboardType(.numberPad)
                TextField("Responder host", text: $responderHost)
                TextField("Responder port", text: $responderPort).keyboardType(.numberPad)
            } header: { Text("Destination contacts") } footer: {
                Text("Use each endpoint’s current listening host and port. 127.0.0.1 is only for simulators on this Mac. Reachability and physical range are unverified.")
            }
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .disabled(relay.flushBusy)
            Section {
                if relay.flushBusy { ProgressView("Forwarding one saved packet…") }
                Button("Forward one saved packet") {
                    Task { await relay.flushOne(publicHost: publicHost, publicPort: publicPort, responderHost: responderHost, responderPort: responderPort) }
                }.disabled(!relay.configured || !transport.active || relay.flushBusy)
            } footer: {
                Text("A tap attempts one eligible packet, including reverse receipts. No automatic retry or forwarding. Interrupted attempts retain custody but consume the bounded attempt budget.")
            }
        }
        .onAppear {
            publicText = relay.publicCard?.base64 ?? ""
            responderText = relay.responderCard?.base64 ?? ""
        }
    }

    private func cardEntry(_ title: String, text: Binding<String>, expected: EndpointRole) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(title, text: text, axis: .vertical)
                .lineLimit(2...4).font(.caption.monospaced())
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            if let card = try? SecurePairingCard(base64: text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                if card.role == expected { fingerprint("Compare complete fingerprint", card.fingerprint) }
                else { Text("This card has the wrong endpoint role.").foregroundStyle(.red) }
            }
        }
    }
    private func fingerprint(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
}
