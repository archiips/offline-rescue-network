import SwiftUI
import Foundation
import CoreLocation
import RescueDemoState

@main struct RescueDemoApp: App {
    @StateObject private var demo = DemoController(storageURL: URL.applicationSupportDirectory.appendingPathComponent("RescueDemo", isDirectory: true).appendingPathComponent("session.sqlite"))
    var body: some Scene { WindowGroup { DemoShell().environmentObject(demo) } }
}

// MARK: - Visual language

/// Dark operational console. Status is always carried by text and symbols, never amber alone.
enum Theme {
    static let ink = Color(red: 0.92, green: 0.94, blue: 0.97)
    static let canvas = Color(red: 0.035, green: 0.050, blue: 0.073)
    static let surface = Color(red: 0.08, green: 0.105, blue: 0.14)
    static let sentSurface = Color(red: 0.20, green: 0.16, blue: 0.105)
    static let accent = Color(red: 0.96, green: 0.69, blue: 0.32)
    static let bubbleRadius: CGFloat = 20
    static let readableWidth: CGFloat = 680
}

extension Animation {
    /// State-driven motion; nil when Reduce Motion is on so changes apply instantly.
    static func rescue(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86) }
}

/// Small uppercase-free section label above a hairline group.
struct SectionLabel: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.tertiary) }
        }
        .padding(.bottom, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One row in a thin-separated list: leading symbol, title/subtitle, optional trailing content.
struct InfoRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil
    var symbolColor: Color = .secondary
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(symbolColor)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary).contentTransition(.opacity) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension InfoRow where Trailing == EmptyView {
    init(systemImage: String, title: String, subtitle: String? = nil, symbolColor: Color = .secondary) {
        self.init(systemImage: systemImage, title: title, subtitle: subtitle, symbolColor: symbolColor) { EmptyView() }
    }
}

/// One fact among device receipt, human acknowledgment and handling; never merged into one status.
struct FactLine: View {
    let title: String
    let value: String
    let systemImage: String
    let reached: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: reached ? "checkmark.circle.fill" : systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(reached ? Theme.ink : Color.secondary)
                .frame(width: 28)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(reached ? .semibold : .regular))
                .foregroundStyle(reached ? Theme.ink : Color.secondary)
                .multilineTextAlignment(.trailing)
                .contentTransition(.opacity)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Inline notice for states that need a decision; icon and text, never color alone.
struct Notice: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label { Text(text) } icon: { Image(systemName: systemImage).foregroundStyle(Theme.accent) }
            .font(.subheadline)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Full-width primary action used for the one dominant call to action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var fill: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.canvas)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(fill.opacity(isEnabled ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Compact capsule action for secondary-but-frequent actions; ink fill adapts to dark mode.
struct CompactButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Theme.canvas : Theme.ink)
            .padding(.horizontal, 16).frame(minHeight: 44)
            .background(prominent ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)), in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Bottom action bar over the content, separated by a hairline.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) { content() }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .frame(maxWidth: Theme.readableWidth)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.surface)
    }
}

/// Wrapping row for status items so long labels never truncate at large text sizes.
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
    @StateObject private var locationCapture = NativeLocationCapture()
    @State private var publicFloor = "Unknown floor"
    @State private var reviewingSOS = false
    @State private var showingSetup = false
    @AppStorage("sampleConnectionMode") private var preferredMode = 0
    @AppStorage("sampleRelayRoute") private var preferredRelay = false
    @AppStorage("sampleEndpointRole") private var preferredRole = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var title: String {
        switch demo.localRole {
        case nil: "Offline Rescue"
        case .responder?: "Responder"
        default: "Offline Rescue"
        }
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatusStrip(transport: demo.transport) { showingSetup = true }
                RecoveryBanner()
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingSetup = true } label: { Label("Setup", systemImage: "gearshape") }
                        .accessibilityHint("Mode, role, pairing, route, connection and session reset")
                }
            }
        }
        .environmentObject(locationCapture)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .onAppear { if preferredMode == 1 && demo.localRole == nil { demo.useSecureRole(EndpointRole(rawValue: preferredRole) ?? .publicUser, viaRelay: preferredRelay) } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { locationCapture.cancel(); demo.stopLocalExchange() } }
        .onChange(of: showingSetup) { _, showing in if showing { locationCapture.cancel() } }
        .onChange(of: preferredMode) { _, _ in locationCapture.clear() }
        .onChange(of: preferredRole) { _, _ in locationCapture.clear() }
        .sheet(isPresented: $showingSetup) { SetupSheet().environmentObject(demo) }
        .confirmationDialog(resetPrompt(training: demo.localRole == nil), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset session", role: .destructive) { demo.reset() }
        }
    }
    @ViewBuilder private var content: some View {
        if demo.snapshot == nil {
            ScrollView {
                VStack(spacing: 16) {
                    ContentUnavailableView("Saved session unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your sample data has not been replaced. Retry opening it when storage is available."))
                    Button("Retry saved session") { demo.retrySavedSession() }
                        .buttonStyle(PrimaryButtonStyle(fill: Theme.ink))
                        .frame(maxWidth: 320)
                    if demo.secureMode { Button("New secure sample session") { confirmingReset = true }.buttonStyle(.bordered) }
                }.padding(24)
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
                    Picker("Training view", selection: $responder.animation(.rescue(reduceMotion))) {
                        Text("Public").tag(false)
                        Text("Responder").tag(true)
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 2)
                    Group {
                        if responder { ResponderView().transition(.opacity) }
                        else { PublicView(floor: $publicFloor, reviewing: $reviewingSOS).transition(.opacity) }
                    }
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

/// Compact connection strip: link, pairing, queue and storage facts plus the persistent synthetic disclosure.
struct StatusStrip: View {
    @EnvironmentObject private var demo: DemoController
    @ObservedObject var transport: LocalExchangeTransport
    let openSetup: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var modeTitle: String {
        guard let role = demo.localRole else { return "Training · simulated link" }
        let side = role == .responder ? "Responder" : "Public"
        guard demo.secureMode else { return "\(side) · plain diagnostic" }
        return "\(side) · \(demo.relayMode ? "relay" : "direct")"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 14) {
                Button(action: openSetup) { connectionItem }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Setup")
                if demo.localRole != nil {
                    if demo.pairedCard == nil { StripItem(text: "Not paired", systemImage: "person.2.slash", attention: true) }
                    else { StripItem(text: "Paired", systemImage: "person.2") }
                }
                if let state = demo.snapshot {
                    if state.pendingTransfers == 0 {
                        StripItem(text: "Queue clear", systemImage: "tray")
                    } else {
                        StripItem(text: "\(state.pendingTransfers) awaiting receipt", systemImage: "tray.full", attention: true)
                    }
                    StripItem(text: state.persistent ? "Saved" : "Memory only", systemImage: state.persistent ? "internaldrive" : "memorychip")
                }
            }
            Text("\(modeTitle) · Synthetic exercise")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Does not contact emergency services")
                .font(.caption2).foregroundStyle(.secondary)
            if demo.localRole != nil {
                if let listening = transport.hostPort, demo.relayMode {
                    Text("Listening on port \(listening.rawValue) · keep this app open")
                        .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                } else if transport.status != "Stopped" {
                    Text(transport.status).font(.caption2).foregroundStyle(.secondary)
                }
                if transport.active && !demo.relayStatus.isEmpty {
                    Text(demo.relayStatus).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if demo.exchangeBusy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(demo.relayMode ? "Uploading saved message" : "Transferring saved messages")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas)
        .overlay(alignment: .bottom) { Divider() }
        .animation(.rescue(reduceMotion), value: demo.snapshot?.pendingTransfers)
        .animation(.rescue(reduceMotion), value: demo.exchangeBusy)
    }
    @ViewBuilder private var connectionItem: some View {
        if demo.localRole == nil {
            let connected = demo.snapshot?.connected ?? false
            StripItem(text: connected ? "Simulated link on" : "Simulated link off", systemImage: connected ? "link" : "link.badge.plus", attention: !connected, live: connected)
        } else if transport.active {
            StripItem(text: demo.relayMode ? "Relay exchange on" : "Local exchange on", systemImage: "antenna.radiowaves.left.and.right", live: true)
        } else {
            StripItem(text: "Stopped", systemImage: "antenna.radiowaves.left.and.right.slash", attention: true)
        }
    }
}

struct StripItem: View {
    let text: String
    let systemImage: String
    var attention = false
    var live = false
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(attention ? Theme.accent : live ? Theme.ink : Color.secondary)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(attention ? Theme.accent : live ? Theme.ink : Color.secondary)
        }
        .font(.caption.weight(attention || live ? .semibold : .regular))
        .accessibilityElement(children: .combine)
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
                        .font(.subheadline).foregroundStyle(.red)
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
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Color.red.opacity(0.06))
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

/// Status events render as centered timeline markers; requests, updates and replies as chat bubbles.
private func isEvent(_ kind: DemoMessageKind) -> Bool {
    switch kind {
    case .receipt, .acknowledgment, .assignment, .resolution, .reopen, .withdrawalDisposition: true
    default: false
    }
}

/// Full message history as a conversation. Each new saved message slides in when it actually appears in state.
struct Conversation: View {
    let state: DeviceSnapshot
    let publicSide: Bool
    let acknowledge: ((String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var motionKey: [String] { state.messages.map { "\($0.id)·\($0.delivery.rawValue)" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Conversation", trailing: state.messages.isEmpty ? nil : "\(state.messages.count)")
            Divider()
            if state.messages.isEmpty {
                Text("No messages yet.").foregroundStyle(.secondary).padding(.vertical, 16)
            }
            VStack(spacing: 14) {
                ForEach(state.messages) { message in
                    Group {
                        if isEvent(message.kind) { eventRow(message) } else { bubble(message) }
                    }
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                }
            }
            .padding(.top, 16)
        }
        .animation(.rescue(reduceMotion), value: motionKey)
    }
    private func direction(_ message: MessageSnapshot) -> String { message.outgoing ? "You sent" : "Received locally" }
    private func bubble(_ message: MessageSnapshot) -> some View {
        let (title, icon) = kindLabel(message.kind)
        return HStack(alignment: .bottom, spacing: 0) {
            if message.outgoing { Spacer(minLength: 56) }
            VStack(alignment: message.outgoing ? .trailing : .leading, spacing: 5) {
                Label("\(title) · \(direction(message))", systemImage: icon)
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    Text(message.text)
                    if !message.location.isEmpty {
                        LocationSummary(value: message.location)
                            .opacity(0.85)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(Theme.ink)
                .background(message.outgoing ? Theme.sentSurface : Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.bubbleRadius, style: .continuous))
                if message.outgoing { deliveryLine(message) }
                ackButton(message)
            }
            if !message.outgoing { Spacer(minLength: 56) }
        }
        .accessibilityElement(children: .contain)
    }
    private func eventRow(_ message: MessageSnapshot) -> some View {
        let (title, icon) = kindLabel(message.kind)
        return VStack(spacing: 3) {
            Label("\(title) · \(direction(message))", systemImage: icon)
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
            if !message.text.isEmpty {
                Text(message.text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if !message.location.isEmpty {
                LocationSummary(value: message.location).font(.caption).foregroundStyle(.secondary)
            }
            if message.outgoing { deliveryLine(message) }
            ackButton(message)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
    private func deliveryLine(_ message: MessageSnapshot) -> some View {
        Label(deliveryText(message.delivery, publicSide: publicSide), systemImage: message.delivery == .waiting ? "clock" : "checkmark")
            .font(.caption2).foregroundStyle(.secondary)
            .contentTransition(.opacity)
    }
    @ViewBuilder private func ackButton(_ message: MessageSnapshot) -> some View {
        if let acknowledge, !message.outgoing, message.kind.isPublicUpdate, message.kind != .request,
           !state.messages.contains(where: { $0.kind == .acknowledgment && $0.reference == message.id }) {
            Button { acknowledge(message.id) } label: { Label("Acknowledge update", systemImage: "hand.raised") }
                .buttonStyle(.bordered).controlSize(.small).padding(.top, 2)
        }
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
        .tint(Theme.accent)
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
                LabeledContent("Storage", value: state.persistent ? "Saved" : "Memory only")
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
            Text(demo.localRole == .responder ? "Responder" : "Public")
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

// MARK: - Optional foreground observation

// Core Location delivers on its creation run loop; this manager is created on MainActor.
// The imported delegate protocol predates actor annotations; retain runtime isolation checks.
@MainActor final class NativeLocationCapture: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var observation: DeviceObservation?
    @Published var status = ""
    @Published var busy = false
    @Published var reported = "Training Building A (sample)"
    @Published var frozenReview = ""
    private var manager: CLLocationManager?
    private var timeout: Task<Void, Never>?

    func capture() {
        cancel()
        let next = CLLocationManager()
        manager = next; busy = true; status = "Waiting for location permission or a fix…"
        next.delegate = self; next.desiredAccuracy = kCLLocationAccuracyBest
        timeout = Task { [weak self, weak next] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, let next, self.manager === next else { return }
            self.finish("Location unavailable. You can still report your location manually.")
        }
        authorize(next)
    }
    private func authorize(_ manager: CLLocationManager) {
        guard self.manager === manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        case .denied, .restricted: finish("Location access unavailable. Use a reported location, or change permission in Settings.")
        @unknown default: finish("Location unavailable. Use a reported location.")
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorize(manager) }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager else { return }
        let now = Date()
        let fixes = locations.sorted { $0.timestamp > $1.timestamp }
        guard let fix = fixes.compactMap({ try? DeviceObservation.capture(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, accuracy: $0.horizontalAccuracy, observedAt: $0.timestamp, approximate: manager.accuracyAuthorization == .reducedAccuracy, now: now) }).first else {
            finish("No recent valid fix. Try again or use a reported location."); return
        }
        observation = fix
        finish("Observation captured. Review it before sending.")
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager else { return }
        finish("Location unavailable. Try again or use a reported location.")
    }
    func cancel() {
        let wasBusy = busy
        manager?.delegate = nil; manager?.stopUpdatingLocation(); manager = nil
        timeout?.cancel(); timeout = nil; busy = false
        if wasBusy { status = "Capture cancelled. No location was sent." }
    }
    func clear() { cancel(); observation = nil; status = ""; frozenReview = "" }
    private func finish(_ message: String) { cancel(); status = message }
}

struct LocationSummary: View {
    let value: String
    var body: some View {
        let report = LocationReport.display(value)
        VStack(alignment: .leading, spacing: 6) {
            Label(report.title, systemImage: "mappin.and.ellipse")
            if let observation = report.observation {
                Text("Device observation\n" + observation.detail).font(.caption).foregroundStyle(.secondary)
                Text("Building and floor are manually reported.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
