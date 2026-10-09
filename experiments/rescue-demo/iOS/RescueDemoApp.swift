import SwiftUI
import Foundation
import RescueDemoState

@main struct RescueDemoApp: App {
    @StateObject private var demo = DemoController(storageURL: URL.applicationSupportDirectory.appendingPathComponent("RescueDemo", isDirectory: true).appendingPathComponent("session.sqlite"))
    var body: some Scene { WindowGroup { DemoShell().environmentObject(demo) } }
}

// MARK: - Visual language

enum Theme {
    static let navy = Color(red: 0.07, green: 0.13, blue: 0.24)
    static let navyDeep = Color(red: 0.03, green: 0.18, blue: 0.24)
    static let teal = Color(red: 0.0, green: 0.52, blue: 0.55)
    static let amber = Color(red: 0.80, green: 0.40, blue: 0.0)
    static let cornerRadius: CGFloat = 18
}

/// Rounded grouped surface used for every content block.
struct Card<Content: View>: View {
    let title: String?
    let systemImage: String?
    let content: Content
    init(_ title: String? = nil, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.systemImage = systemImage; self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Group {
                    if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Eyebrow + title introducing the public or responder surface.
struct AudienceHeading: View {
    let eyebrow: String
    let title: String
    let systemImage: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(eyebrow.uppercased(), systemImage: systemImage)
                .font(.caption.weight(.bold)).foregroundStyle(Theme.teal)
            Text(title).font(.title2.bold())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    var attention = false
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(attention ? Color(red: 1, green: 0.78, blue: 0.45) : .white)
            .background(.white.opacity(attention ? 0.10 : 0.14), in: Capsule())
    }
}

/// One fact among device receipt, human acknowledgment and handling; never merged.
struct FactTile: View {
    let title: String
    let value: String
    let systemImage: String
    let reached: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage).font(.title3)
                .foregroundStyle(reached ? Theme.teal : Color.secondary)
                .accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Lays facts side by side, stacking them at accessibility text sizes.
struct FactRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout { content() }
    }
}

/// Wrapping row for status pills so long labels never truncate at large text sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + size.width > maxWidth { y += row + spacing; x = 0; row = 0 }
            x += size.width + spacing; row = max(row, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX { y += row + spacing; x = bounds.minX; row = 0 }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing; row = max(row, size.height)
        }
    }
}

// MARK: - Shell

struct DemoShell: View {
    @EnvironmentObject private var demo: DemoController
    @State private var confirmingReset = false
    @State private var responder = false
    @State private var publicFloor = "Floor 1"
    @State private var reviewingSOS = false
    @State private var showingSetup = false
    @AppStorage("sampleConnectionMode") private var preferredMode = 0
    @AppStorage("sampleRelayRoute") private var preferredRelay = false
    @AppStorage("sampleEndpointRole") private var preferredRole = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatusHeader(transport: demo.transport) { showingSetup = true }
                RecoveryBanner()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Offline Rescue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSetup = true } label: { Label("Setup", systemImage: "slider.horizontal.3") }
                        .labelStyle(.titleAndIcon)
                        .accessibilityHint("Mode, role, pairing, route, connection and session reset")
                }
            }
        }
        .fontDesign(.rounded)
        .tint(Theme.teal)
        .onAppear { if preferredMode == 1 && demo.localRole == nil { demo.useSecureRole(EndpointRole(rawValue: preferredRole) ?? .publicUser, viaRelay: preferredRelay) } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { demo.stopLocalExchange() } }
        .sheet(isPresented: $showingSetup) { SetupSheet().environmentObject(demo) }
        .confirmationDialog(resetPrompt(training: demo.localRole == nil), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset session", role: .destructive) { demo.reset() }
        }
    }
    @ViewBuilder private var content: some View {
        if demo.snapshot == nil {
            ScrollView {
                VStack(spacing: 12) {
                    ContentUnavailableView("Saved session unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your sample data has not been replaced. Retry opening it when storage is available."))
                    Button("Retry saved session") { demo.retrySavedSession() }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    if demo.secureMode { Button("New secure sample session") { confirmingReset = true }.buttonStyle(.bordered) }
                }.padding()
            }
        } else if demo.localRole == nil {
            if sizeClass == .regular {
                // Training on a wide screen: both audiences side by side, each first-class.
                HStack(alignment: .top, spacing: 0) {
                    PublicView(floor: $publicFloor, reviewing: $reviewingSOS)
                    Divider()
                    ResponderView()
                }
            } else {
                VStack(spacing: 0) {
                    Picker("Training view", selection: $responder) {
                        Label("Public", systemImage: "person.fill").tag(false)
                        Label("Responder", systemImage: "cross.case.fill").tag(true)
                    }
                    .pickerStyle(.segmented).padding(.horizontal).padding(.top, 12).padding(.bottom, 4)
                    if responder { ResponderView() } else { PublicView(floor: $publicFloor, reviewing: $reviewingSOS) }
                }
            }
        } else if demo.localRole == .responder {
            ResponderView()
        } else {
            PublicView(floor: $publicFloor, reviewing: $reviewingSOS)
        }
    }
}

func resetPrompt(training: Bool) -> String {
    training ? "Clear this training session?" : "Start a new secure sample session? Keys and pairing will change. Reset and re-pair both endpoints. Previous sample files remain on disk."
}

/// Editorial navy header: what this device is, the synthetic disclosure and live connection facts.
struct StatusHeader: View {
    @EnvironmentObject private var demo: DemoController
    @ObservedObject var transport: LocalExchangeTransport
    let openSetup: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var modeTitle: String {
        guard let role = demo.localRole else { return "Training · simulated link" }
        let side = role == .responder ? "Responder endpoint" : "Public endpoint"
        guard demo.secureMode else { return "\(side) · plain diagnostic" }
        return "\(side) · \(demo.relayMode ? "via relay" : "direct exchange")"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(modeTitle).font(.title3.weight(.bold)).foregroundStyle(.white)
                Text("Synthetic sample data · does not contact emergency services")
                    .font(.footnote).foregroundStyle(.white.opacity(0.75))
            }
            .accessibilityElement(children: .combine)
            FlowLayout {
                Button(action: openSetup) { connectionPill }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Setup")
                if demo.localRole != nil {
                    if demo.pairedCard == nil { StatusPill(text: "Not paired", systemImage: "person.2.slash", attention: true) }
                    else { StatusPill(text: "Paired sample peer", systemImage: "person.2.fill") }
                }
                if let state = demo.snapshot {
                    if state.pendingTransfers == 0 {
                        StatusPill(text: "Nothing queued", systemImage: "tray")
                    } else {
                        StatusPill(text: "\(state.pendingTransfers) queued · no device receipt yet", systemImage: "tray.full.fill", attention: true)
                    }
                    StatusPill(text: state.persistent ? "Saved on this device" : "Sample memory session", systemImage: state.persistent ? "internaldrive" : "memorychip")
                }
            }
            if demo.localRole != nil {
                if let listening = transport.hostPort, demo.relayMode {
                    Text("Listening on port \(listening.rawValue) · keep this app open")
                        .font(.caption).foregroundStyle(.white.opacity(0.8)).textSelection(.enabled)
                } else {
                    Text(transport.status).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                if transport.active && !demo.relayStatus.isEmpty {
                    Text(demo.relayStatus).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }
            if demo.exchangeBusy {
                ProgressView(demo.relayMode ? "Uploading saved message" : "Transferring saved messages")
                    .font(.caption).tint(.white).foregroundStyle(.white)
            }
        }
        .padding(.horizontal).padding(.top, 8).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Theme.navy, Theme.navyDeep], startPoint: .top, endPoint: .bottom))
        .animation(reduceMotion ? nil : .smooth, value: demo.snapshot?.pendingTransfers)
        .animation(reduceMotion ? nil : .smooth, value: demo.exchangeBusy)
    }
    @ViewBuilder private var connectionPill: some View {
        if demo.localRole == nil {
            let connected = demo.snapshot?.connected ?? false
            StatusPill(text: connected ? "Simulated link on" : "Simulated link off", systemImage: connected ? "link" : "link.badge.plus", attention: !connected)
        } else if transport.active {
            StatusPill(text: demo.relayMode ? "Relay exchange on" : "Local exchange on", systemImage: "antenna.radiowaves.left.and.right")
        } else {
            StatusPill(text: "Exchange stopped", systemImage: "antenna.radiowaves.left.and.right.slash", attention: true)
        }
    }
}

/// Errors and their recovery actions stay on the main surface.
struct RecoveryBanner: View {
    @EnvironmentObject private var demo: DemoController
    private var canRetryTraining: Bool {
        guard let state = demo.snapshot else { return false }
        return demo.localRole == nil && state.connected && state.pendingTransfers > 0
    }
    var body: some View {
        if !demo.error.isEmpty || canRetryTraining {
            VStack(alignment: .leading, spacing: 8) {
                if !demo.error.isEmpty {
                    Label(demo.error, systemImage: "exclamationmark.octagon.fill")
                        .font(.callout).foregroundStyle(.red)
                }
                HStack {
                    if !demo.error.isEmpty && demo.snapshot?.persistent == true {
                        Button("Reopen saved session") { demo.retrySavedSession() }
                    }
                    if canRetryTraining { Button("Retry queued transfers") { demo.setConnected(true) } }
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

// MARK: - Shared semantics

func deliveryText(_ value: DemoDelivery, publicSide: Bool) -> String {
    switch value {
    case .deviceReceived: return publicSide ? "Received by responder device · not yet acknowledged by a person" : "Received by public device"
    case .humanAcknowledged: return publicSide ? "Acknowledged by responder" : "Responder acknowledgment recorded"
    case .waiting: return "Queued on this device · no device receipt yet"
    }
}
func handlingText(_ value: DemoHandling) -> String { switch value { case .resolved: "Resolved"; case .assigned: "Assigned"; case .open: "Open" } }
func handlingIcon(_ value: DemoHandling) -> String { switch value { case .resolved: "checkmark.seal.fill"; case .assigned: "person.2.fill"; case .open: "circle.dashed" } }

private func kindLabel(_ kind: DemoMessageKind) -> (String, String) {
    switch kind {
    case .request: ("Assistance request", "sos")
    case .followUp: ("Follow-up", "text.bubble")
    case .correction: ("Location correction", "mappin.and.ellipse")
    case .withdrawal: ("Withdrawal request", "arrow.uturn.backward.circle")
    case .receipt: ("Device receipt", "checkmark.circle")
    case .acknowledgment: ("Human acknowledgment", "hand.raised.fill")
    case .reply: ("Reply", "bubble.left.fill")
    case .assignment: ("Assignment", "person.2.fill")
    case .resolution: ("Resolution", "checkmark.seal.fill")
    case .reopen: ("Reopened", "arrow.clockwise.circle")
    case .withdrawalDisposition: ("Withdrawal decision", "doc.text")
    }
}

struct Conversation: View {
    let state: DeviceSnapshot
    let publicSide: Bool
    let acknowledge: ((String) -> Void)?
    var body: some View {
        Card("Messages & updates", systemImage: "text.bubble") {
            if state.messages.isEmpty {
                Text("No messages yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(state.messages.enumerated()), id: \.element.id) { index, message in
                if index > 0 { Divider() }
                messageRow(message)
            }
        }
    }
    private func messageRow(_ message: MessageSnapshot) -> some View {
        let (title, icon) = kindLabel(message.kind)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(message.outgoing ? Theme.teal : Theme.navy)
                .frame(minWidth: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(title) · \(message.outgoing ? "You sent" : "Received locally")")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(message.text)
                if !message.location.isEmpty {
                    Label(message.location, systemImage: "mappin.and.ellipse").font(.subheadline)
                }
                if message.outgoing {
                    Text(deliveryText(message.delivery, publicSide: publicSide)).font(.caption).foregroundStyle(.secondary)
                }
                if let acknowledge, !message.outgoing, message.kind.isPublicUpdate, message.kind != .request,
                   !state.messages.contains(where: { $0.kind == .acknowledgment && $0.reference == message.id }) {
                    Button("Acknowledge update") { acknowledge(message.id) }
                        .buttonStyle(.bordered).controlSize(.small).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Setup

/// All mode, role, pairing, route, connection and reset controls. Pairing is pushed, not stacked as another sheet.
struct SetupSheet: View {
    @EnvironmentObject private var demo: DemoController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingReset = false
    @AppStorage("sampleConnectionMode") private var preferredMode = 0
    @AppStorage("sampleRelayRoute") private var preferredRelay = false
    @AppStorage("sampleEndpointRole") private var preferredRole = 0
    private var training: Bool { demo.localRole == nil }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Mode", selection: Binding(get: { training ? 0 : 1 }, set: { value in
                        if value == 0 { preferredMode = 0; demo.useTraining() }
                        else { preferredMode = 1; demo.useSecureRole(EndpointRole(rawValue: preferredRole) ?? .publicUser, viaRelay: preferredRelay) }
                    })) {
                        Text("Training").tag(0)
                        Text("Secure exchange").tag(1)
                    }.pickerStyle(.segmented)
                } header: { Text("Mode") } footer: {
                    Text(training ? "Both sample devices run inside this app over a simulated link." : "This device is one endpoint exchanging signed, encrypted sample messages with a separate paired endpoint.")
                }
                if training { trainingSections } else { secureSections }
                sessionSection
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog(resetPrompt(training: training), isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Reset session", role: .destructive) { demo.reset() }
            }
        }
        .fontDesign(.rounded)
        .tint(Theme.teal)
    }
    @ViewBuilder private var trainingSections: some View {
        Section {
            Toggle("Simulated connection", isOn: Binding(get: { demo.snapshot?.connected ?? false }, set: { demo.setConnected($0) }))
                .disabled(demo.snapshot == nil)
            if let state = demo.snapshot, state.connected && state.pendingTransfers > 0 {
                Button("Retry queued transfers") { demo.setConnected(true) }
            }
        } header: { Text("Simulated link") } footer: {
            Text("Turn the link off to queue messages; turn it on to transfer them between the two sample views.")
        }
    }
    @ViewBuilder private var secureSections: some View {
        Section {
            Picker("This device", selection: Binding(get: { demo.localRole == .responder ? 1 : 0 }, set: { value in
                preferredRole = value; demo.useSecureRole(value == 1 ? .responder : .publicUser, viaRelay: preferredRelay)
            })) {
                Text("Public").tag(0)
                Text("Responder").tag(1)
            }.pickerStyle(.segmented)
        } header: { Text("Endpoint role") } footer: { Text("Choose the opposite role on the other endpoint.") }
        Section("Pairing") {
            NavigationLink { SecurePairingView() } label: {
                LabeledContent(demo.pairedCard == nil ? "Pair endpoints" : "View pairing", value: demo.pairedCard == nil ? "Not paired" : "Paired sample peer")
            }
        }
        Section {
            Picker("Connection route", selection: Binding(get: { demo.relayMode }, set: {
                preferredRelay = $0; demo.useRelayRoute($0)
            })) {
                Text("Direct").tag(false)
                Text("Via relay").tag(true)
            }.pickerStyle(.segmented)
        } header: { Text("Route") } footer: { Text("Changing route keeps identity, pairing and history. Networking starts only when you tap Start.") }
        if demo.relayMode { RelayConnectionSections(transport: demo.transport) }
        else { LocalConnectionSections(transport: demo.transport) }
    }
    private var sessionSection: some View {
        Section("Session") {
            if let state = demo.snapshot {
                LabeledContent("Storage", value: state.persistent ? "Saved on this device" : "Sample memory session")
                LabeledContent("Queued on this device", value: "\(state.pendingTransfers)")
            }
            if !demo.error.isEmpty && !(demo.localRole != nil && demo.relayMode) {
                Text(demo.error).foregroundStyle(.red)
            }
            if !demo.error.isEmpty && demo.snapshot?.persistent == true {
                Button("Reopen saved session") { demo.retrySavedSession() }
            }
            if demo.snapshot == nil { Button("Retry saved session") { demo.retrySavedSession() } }
            Button(training ? "Clear training session" : "New secure sample session", role: .destructive) { confirmingReset = true }
                .disabled(demo.snapshot == nil && !demo.secureMode)
        }
    }
}

struct LocalConnectionSections: View {
    @EnvironmentObject private var demo: DemoController
    @ObservedObject var transport: LocalExchangeTransport
    var body: some View {
        Section {
            Button(transport.active ? "Stop exchange" : "Start local exchange") {
                if transport.active { demo.stopLocalExchange() } else { demo.startLocalExchange() }
            }.disabled(demo.snapshot == nil || (demo.secureMode && demo.pairedCard == nil))
            LabeledContent("Status", value: transport.status)
            if demo.exchangeBusy { ProgressView("Transferring saved messages") }
        } header: { Text("Direct local exchange") } footer: {
            Text("Exchange stops when the app moves to the background and stays stopped until you start it again.")
        }
        Section("Nearby sample peers (\(transport.peers.count))") {
            ForEach(Array(transport.peers.enumerated()), id: \.offset) { _, peer in
                Button("Transfer to \(peer.endpoint)") { Task { await demo.transferQueued(to: peer.endpoint) } }
                    .disabled(demo.exchangeBusy || !transport.active)
            }
            if transport.peers.isEmpty {
                Text("Start exchange on both apps. Peer names are unverified. Only your paired endpoint can exchange messages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Same explicit relay controls for both audiences; custody is never presented as delivery.
struct RelayConnectionSections: View {
    @EnvironmentObject private var demo: DemoController
    @ObservedObject var transport: LocalExchangeTransport
    @AppStorage("sampleRelayHost") private var host = "127.0.0.1"
    @AppStorage("sampleRelayPort") private var port = ""
    var body: some View {
        Section {
            Text(demo.localRole == .responder ? "Responder endpoint" : "Public endpoint")
            Button(transport.active ? "Stop relay exchange" : "Start relay exchange") {
                if transport.active { demo.stopLocalExchange() } else { demo.startLocalExchange() }
            }.disabled(demo.snapshot == nil || demo.pairedCard == nil)
            if let listening = transport.hostPort {
                LabeledContent("Listening port", value: "\(listening.rawValue)").textSelection(.enabled)
            }
            LabeledContent("Status", value: transport.status)
        } header: { Text("Relay exchange") } footer: {
            Text("Configure the Mac relay with both public pairing cards and each endpoint's listening port. Restarting the listener may change its port.")
        }
        Section {
            TextField("Relay host", text: $host)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: host) { _, _ in if host.count > 253 { host = String(host.prefix(253)) } }
            TextField("Relay port", text: $port).keyboardType(.numberPad)
                .onChange(of: port) { _, _ in if port.count > 5 { port = String(port.prefix(5)) } }
        } header: { Text("Manual relay address") } footer: {
            Text("Use the relay Mac's address. 127.0.0.1 is for Simulator on the same Mac.")
        }
        Section {
            LabeledContent("Queued on this device", value: "\(demo.snapshot?.pendingTransfers ?? 0)")
            Button("Upload oldest queued message") { Task { await demo.uploadViaRelay(host: host, port: port) } }
                .disabled(!transport.active || transport.hostPort == nil || demo.exchangeBusy || demo.pairedCard == nil || (demo.snapshot?.pendingTransfers ?? 0) == 0)
            if demo.exchangeBusy { ProgressView("Uploading saved message") }
            if transport.active && !demo.relayStatus.isEmpty { Text(demo.relayStatus) }
            if !demo.error.isEmpty { Text(demo.error).foregroundStyle(.red) }
        } header: { Text("Saved messages") } footer: {
            Text("A relay can claim it saved a copy; that claim is unverified custody, not delivery. Your message stays queued until the other device's signed receipt returns. A human acknowledgment is separate.")
        }
        Section("Recovery") {
            Text("Keep both endpoints in Via relay mode. Stop ends this contact, keeping queued messages saved. Networking stays stopped after background or restart.").font(.caption)
            Text("For a missing, expired or full retry cache, use New secure sample session below. Keys and pairing change; re-pair both endpoints and update the relay. Previous files remain, but pending messages do not migrate.").font(.caption)
        }
    }
}

/// Pushed from Setup, so trusting a peer returns to Setup rather than stacking sheets.
struct SecurePairingView: View {
    @EnvironmentObject private var demo: DemoController
    @Environment(\.dismiss) private var dismiss
    @State private var peerInput = ""
    @State private var checkedFingerprint = false
    private var candidate: SecurePairingCard? { try? SecurePairingCard(base64: peerInput.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var body: some View {
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
    }
}

private func formattedFingerprint(_ fingerprint: String) -> String {
    let characters = Array(fingerprint)
    return stride(from: 0, to: characters.count, by: 8).map { offset in
        String(characters[offset..<min(offset + 8, characters.count)])
    }.joined(separator: " ")
}
