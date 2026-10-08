import SwiftUI
import Foundation
import RescueDemoState

@main struct RescueDemoApp: App {
    @StateObject private var demo = DemoController(storageURL: URL.applicationSupportDirectory.appendingPathComponent("RescueDemo", isDirectory: true).appendingPathComponent("session.sqlite"))
    var body: some Scene { WindowGroup { DemoShell().environmentObject(demo) } }
}
struct DemoShell: View {
    @EnvironmentObject private var demo: DemoController
    @State private var confirmingReset = false
    @State private var responder = false
    @State private var showingPairing = false
    @AppStorage("sampleConnectionMode") private var preferredMode = 0
    @AppStorage("sampleEndpointRole") private var preferredRole = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Rescue demo · sample data", systemImage: "shield.lefthalf.filled").font(.headline)
                HStack {
                    Button("Training mode") { preferredMode = 0; demo.useTraining() }
                        .accessibilityAddTraits(demo.localRole == nil ? .isSelected : [])
                    Button("Secure exchange") {
                        preferredMode = 1; demo.useSecureRole(EndpointRole(rawValue: preferredRole) ?? .publicUser)
                    }.accessibilityAddTraits(demo.localRole != nil ? .isSelected : [])
                }.buttonStyle(.bordered)
                if let role = demo.localRole {
                    HStack {
                        Button("Public endpoint") { preferredRole = 0; demo.useSecureRole(.publicUser) }
                            .accessibilityAddTraits(role == .publicUser ? .isSelected : [])
                        Button("Responder endpoint") { preferredRole = 1; demo.useSecureRole(.responder) }
                            .accessibilityAddTraits(role == .responder ? .isSelected : [])
                    }.buttonStyle(.bordered)
                    HStack {
                        Button(demo.pairedCard == nil ? "Pair endpoints" : "View pairing") { showingPairing = true }
                        Text(demo.pairedCard == nil ? "Not paired" : "Paired sample peer").font(.caption).foregroundStyle(.secondary)
                    }
                    LocalConnectionControls(transport: demo.transport)
                } else {
                Toggle("Simulated connection", isOn: Binding(get: { demo.snapshot?.connected ?? false }, set: { demo.setConnected($0) }))
                    .disabled(demo.snapshot == nil)
                }
                if let state = demo.snapshot {
                    Text("\(state.pendingTransfers) transfers queued · \(state.persistent ? "saved on this device" : "sample memory session")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !demo.error.isEmpty {
                    Text(demo.error).font(.callout).foregroundStyle(.red)
                    if demo.snapshot?.persistent == true { Button("Reopen saved session") { demo.retrySavedSession() } }
                }
                if let state = demo.snapshot, demo.localRole == nil && state.connected && state.pendingTransfers > 0 {
                    Button("Retry queued transfers") { demo.setConnected(true) }
                }
            }.padding().background(.thinMaterial)
            if demo.snapshot == nil {
                ContentUnavailableView("Saved session unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your sample data has not been replaced. Retry opening it when storage is available."))
                Button("Retry saved session") { demo.retrySavedSession() }.buttonStyle(.borderedProminent).padding()
                if demo.secureMode { Button("New secure sample session") { confirmingReset = true }.buttonStyle(.bordered).padding(.bottom) }
            } else {
            if demo.localRole == nil {
            HStack {
                Button { responder = false } label: { Label("Public view", systemImage: "person.fill").frame(maxWidth: .infinity) }
                    .accessibilityAddTraits(responder ? [] : .isSelected)
                Button { responder = true } label: { Label("Responder view", systemImage: "cross.case.fill").frame(maxWidth: .infinity) }
                    .accessibilityAddTraits(responder ? .isSelected : [])
            }.buttonStyle(.bordered).padding(.horizontal).padding(.vertical, 8)
            }
            if demo.localRole == .responder || (demo.localRole == nil && responder) {
                NavigationStack { ResponderView().toolbar { resetButton } }
            } else {
                NavigationStack { PublicView().toolbar { resetButton } }
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .onAppear { if preferredMode == 1 && demo.localRole == nil { demo.useSecureRole(EndpointRole(rawValue: preferredRole) ?? .publicUser) } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { demo.stopLocalExchange() } }
        .sheet(isPresented: $showingPairing) { SecurePairingSheet().environmentObject(demo) }
        .confirmationDialog(demo.localRole == nil ? "Clear this training session?" : "Start a new secure sample session? Keys and pairing will change. Reset and re-pair both endpoints. Previous sample files remain on disk.", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset session", role: .destructive) { demo.reset() }
        }
    }
    private var resetButton: some View { Button("Reset") { confirmingReset = true }.disabled(demo.snapshot == nil) }
}
func deliveryText(_ value: DemoDelivery, publicSide: Bool) -> String {
    switch value {
    case .deviceReceived: return publicSide ? "Received by responder device" : "Received by public device"
    case .humanAcknowledged: return publicSide ? "Acknowledged by responder" : "Responder acknowledgment recorded"
    case .waiting: return "Waiting for delivery"
    }
}
func handlingText(_ value: DemoHandling) -> String { switch value { case .resolved: "Resolved"; case .assigned: "Assigned"; case .open: "Open" } }
struct Conversation: View {
    let state: DeviceSnapshot
    let publicSide: Bool
    let acknowledge: ((String) -> Void)?
    var body: some View {
        Section("Messages & updates") {
            ForEach(state.messages) { message in
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.outgoing ? "You sent" : "Received locally").font(.caption).foregroundStyle(.secondary)
                    Text(message.text)
                    if !message.location.isEmpty { Label(message.location, systemImage: "mappin.and.ellipse") }
                    if message.outgoing { Text(deliveryText(message.delivery, publicSide: publicSide)).font(.caption).foregroundStyle(.secondary) }
                    if let acknowledge, !message.outgoing, message.kind.isPublicUpdate, message.kind != .request,
                       !state.messages.contains(where: { $0.kind == .acknowledgment && $0.reference == message.id }) {
                        Button("Acknowledge update") { acknowledge(message.id) }
                    }
                }.padding(.vertical, 6)
            }
        }
    }
}

struct LocalConnectionControls: View {
    @EnvironmentObject private var demo: DemoController
    @ObservedObject var transport: LocalExchangeTransport
    var body: some View {
        HStack {
            Button(transport.active ? "Stop exchange" : "Start local exchange") {
                if transport.active { demo.stopLocalExchange() } else { demo.startLocalExchange() }
            }.disabled(demo.snapshot == nil || (demo.secureMode && demo.pairedCard == nil))
            if demo.exchangeBusy { ProgressView().accessibilityLabel("Transferring saved messages") }
        }
        Text(transport.status).font(.caption).foregroundStyle(.secondary)
        DisclosureGroup("Nearby sample peers (\(transport.peers.count))") {
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(Array(transport.peers.enumerated()), id: \.offset) { _, peer in
                        Button("Transfer to \(peer.endpoint)") { Task { await demo.transferQueued(to: peer.endpoint) } }
                            .disabled(demo.exchangeBusy || !transport.active)
                    }
                    if transport.peers.isEmpty { Text("Start exchange on both apps. Peer names are unverified. Only your paired endpoint can exchange messages.").font(.caption) }
                }
            }.frame(maxHeight: 120)
        }
    }
}

struct SecurePairingSheet: View {
    @EnvironmentObject private var demo: DemoController
    @Environment(\.dismiss) private var dismiss
    @State private var peerInput = ""
    @State private var checkedFingerprint = false
    private var candidate: SecurePairingCard? { try? SecurePairingCard(base64: peerInput.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Attended sample pairing") {
                    Text("Exchange public cards directly with the other endpoint. Compare its full fingerprint on that device before trusting it. This does not verify a firefighter organization.")
                }
                if let card = demo.secureCard {
                    Section("Your public card") {
                        Text(card.role == .publicUser ? "Public endpoint" : "Responder endpoint")
                        Text(card.base64).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .accessibilityLabel("Your pairing card: \(card.base64)")
                        Button("Copy public card") { UIPasteboard.general.string = card.base64 }
                        Text("Your fingerprint").font(.caption).foregroundStyle(.secondary)
                        Text(formattedFingerprint(card.fingerprint)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                if let peer = demo.pairedCard {
                    Section("Trusted sample peer") {
                        Text(peer.role == .publicUser ? "Public endpoint" : "Responder endpoint")
                        Text(formattedFingerprint(peer.fingerprint)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text("Start a new session on both endpoints to change pairing.").font(.caption)
                    }
                } else {
                    Section("Check the other endpoint") {
                        TextField("Paste peer public card", text: $peerInput, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: peerInput) { _, _ in checkedFingerprint = false; if peerInput.count > 256 { peerInput = String(peerInput.prefix(256)) } }
                        if let peer = candidate {
                            Text(peer.role == .publicUser ? "Public endpoint" : "Responder endpoint")
                            Text(formattedFingerprint(peer.fingerprint)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Toggle("I compared the full fingerprint on the other device", isOn: $checkedFingerprint)
                            Button("Trust checked peer") {
                                if demo.pairSecurePeer(peerInput.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
                            }.disabled(!checkedFingerprint || peer.role == demo.localRole)
                            if peer.role == demo.localRole { Text("Choose the opposite role on the other endpoint.").foregroundStyle(.red) }
                        } else if !peerInput.isEmpty { Text("Enter a valid sample public card.").foregroundStyle(.red) }
                    }
                }
                if !demo.error.isEmpty { Section { Text(demo.error).foregroundStyle(.red) } }
                Section { Text("Sample bodies are encrypted in transit. Saved sample messages remain unencrypted on this device.").font(.caption) }
            }
            .navigationTitle("Pair sample endpoints")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private func formattedFingerprint(_ fingerprint: String) -> String {
    let characters = Array(fingerprint)
    return stride(from: 0, to: characters.count, by: 8).map { offset in
        String(characters[offset..<min(offset + 8, characters.count)])
    }.joined(separator: " ")
}
