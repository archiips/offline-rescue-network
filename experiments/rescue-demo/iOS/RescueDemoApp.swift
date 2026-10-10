import SwiftUI
import Foundation
import CoreLocation
import UniformTypeIdentifiers
import RescueDemoState

@main struct RescueDemoApp: App {
    @StateObject private var demo = DemoController(storageURL: URL.applicationSupportDirectory.appendingPathComponent("RescueDemo", isDirectory: true).appendingPathComponent("session.sqlite"))
    var body: some Scene { WindowGroup { RescueEntry().environmentObject(demo) } }
}

/// Read the prepared-drill preference once at launch, avoiding a mid-import root replacement.
private struct RescueEntry: View {
    @State private var registered = UserDefaults.standard.bool(forKey: "registeredDrillLaunch")
    var body: some View {
        if registered {
            NavigationStack {
                RegisteredDrillView()
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Other demo modes") {
                            UserDefaults.standard.set(false, forKey: "registeredDrillLaunch")
                            registered = false
                        }
                    } }
            }
            .preferredColorScheme(.dark).tint(Theme.accent)
        } else { DemoShell() }
    }
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
    @StateObject private var phoneRelay = NativeRelayHostController(rootURL: URL.applicationSupportDirectory.appendingPathComponent("RescueDemo/phone-relay", isDirectory: true))
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
        .environmentObject(phoneRelay)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .transaction { if reduceMotion { $0.disablesAnimations = true } }
        .onAppear { if preferredMode == 1 && demo.localRole == nil { demo.useSecureRole(EndpointRole(rawValue: preferredRole) ?? .publicUser, viaRelay: preferredRelay) } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { locationCapture.cancel(); phoneRelay.stop(); demo.stopLocalExchange() } }
        .onChange(of: showingSetup) { _, showing in if showing { locationCapture.cancel() } }
        .onChange(of: preferredMode) { _, _ in locationCapture.clear() }
        .onChange(of: preferredRole) { _, _ in locationCapture.clear() }
        .sheet(isPresented: $showingSetup) { SetupSheet().environmentObject(demo).environmentObject(phoneRelay) }
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
                Section {
                    NavigationLink { PhoneRelayView() } label: {
                        Label("Host a relay on this device", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                } header: { Text("Third-device relay") } footer: {
                    Text("A separate foreground workspace for carrying encrypted packets. Endpoint networking stops when you enter; identity and history are retained.")
                }
                Section {
                    NavigationLink { FloorResearchView() } label: {
                        Label("Automatic floor research", systemImage: "building.2")
                    }
                } header: { Text("Location research") } footer: {
                    Text("Optional foreground sensor feasibility. Estimates never replace your reported floor or enter messages automatically.")
                }
                Section {
                    NavigationLink { RegisteredDrillView() } label: {
                        Label("Prepared registration drill", systemImage: "person.badge.shield.checkmark")
                    }
                } footer: {
                    Text("Synthetic organizer-issued credentials. Prepare before an outage; enrolled devices discover and exchange automatically. One responder can retain up to 16 public conversations; no UW authorization.")
                }
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

// MARK: - Prepared registration drill

private struct RegistrationRequestDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@MainActor private final class RegisteredPreparation: ObservableObject {
    @Published var role: EndpointRole = .publicUser
    @Published var controller: RegisteredExchangeController?
    @Published var inbox: RegisteredResponderInbox?
    @Published var readiness: EnrollmentReadiness?
    @Published var draft: EnrollmentProfile?
    @Published var error = ""
    @Published var request = ""
    @Published var legacyAvailable = false
    private var secure: SecureEndpointController?
    private var store: DefaultKeychainStore?
    private var approvedProfile: EnrollmentProfile?
    func select(_ role: EndpointRole) {
        controller?.stop(); inbox?.stop(); controller = nil; inbox = nil; readiness = nil; draft = nil; secure = nil; approvedProfile = nil; legacyAvailable = false; request = ""; error = ""; self.role = role
        UserDefaults.standard.set(role.rawValue, forKey: "registeredDrillRole")
        let root = URL.applicationSupportDirectory.appendingPathComponent("RescueDemo/registered-drill", isDirectory: true)
        do {
            let secure = try SecureEndpointController(rootURL: root, role: role,
                recordStore: DefaultKeychainStore(rootURL: root, role: role, namespace: "native-registered-keys-v1"))
            self.secure = secure; request = secure.card.base64
            legacyAvailable = role == .responder && secure.peerCard != nil
            let store = DefaultKeychainStore(rootURL: root, role: role, namespace: "native-registered-profile-v1")
            self.store = store
            if let bytes = try store.read() {
                let profile = try EnrollmentProfile.decode(bytes)
                let trust = try profile.validate(card: secure.card, issuerApproved: true, at: Int64(Date().timeIntervalSince1970))
                readiness = try EnrollmentReadiness(profile: profile, card: secure.card, issuerApproved: true, at: Int64(Date().timeIntervalSince1970))
                approvedProfile = profile
                try prepareWorkspace(secure: secure, profile: profile, trust: trust)
            }
        } catch { self.error = "Preparation unavailable; existing keys/history are retained. \(error)" }
    }
    func updatePreparation() {
        controller?.stop(); inbox?.stop(); controller = nil; inbox = nil; draft = nil; error = ""
    }
    private func prepareWorkspace(secure: SecureEndpointController, profile: EnrollmentProfile, trust: EnrollmentTrust) throws {
        if role == .responder && (secure.peerCard == nil || UserDefaults.standard.bool(forKey: "registeredResponderInbox")) {
            inbox = try RegisteredResponderInbox(secure: secure, credential: profile.credential, trust: trust)
        } else {
            controller = try RegisteredExchangeController(secure: secure, credential: profile.credential, trust: trust)
        }
    }
    func switchResponderWorkspace(inbox useInbox: Bool) {
        do {
            guard role == .responder, let secure, let profile = approvedProfile else { throw EnrollmentError.wrongIdentity }
            let trust = try profile.validate(card: secure.card, issuerApproved: true, at: Int64(Date().timeIntervalSince1970))
            let nextInbox = useInbox ? try RegisteredResponderInbox(secure: secure, credential: profile.credential, trust: trust) : nil
            let nextController = useInbox ? nil : try RegisteredExchangeController(secure: secure, credential: profile.credential, trust: trust)
            controller?.stop(); inbox?.stop()
            controller = nextController; inbox = nextInbox; error = ""
            UserDefaults.standard.set(useInbox, forKey: "registeredResponderInbox")
        } catch { self.error = "Workspace unchanged. \(error)" }
    }
    func read(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let secure, controller == nil, inbox == nil else { throw EnrollmentError.busy }
            let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
            let bytes = try file.read(upToCount: 4097) ?? Data()
            let profile = try EnrollmentProfile.decode(bytes)
            _ = try profile.validate(card: secure.card, issuerApproved: true, at: Int64(Date().timeIntervalSince1970))
            draft = profile; error = ""
        } catch { draft = nil; self.error = "Profile rejected; preparation unchanged. \(error)" }
    }
    func approve(issuerApproved: Bool) {
        do {
            guard let draft, let secure, let store else { throw EnrollmentError.wrongIdentity }
            let trust = try draft.validate(card: secure.card, issuerApproved: issuerApproved, at: Int64(Date().timeIntervalSince1970))
            let readiness = try EnrollmentReadiness(profile: draft, card: secure.card, issuerApproved: issuerApproved, at: Int64(Date().timeIntervalSince1970))
            // Validate workspace construction before replacing approved preparation.
            let nextInbox = role == .responder && (secure.peerCard == nil || UserDefaults.standard.bool(forKey: "registeredResponderInbox"))
                ? try RegisteredResponderInbox(secure: secure, credential: draft.credential, trust: trust) : nil
            let nextController = nextInbox == nil
                ? try RegisteredExchangeController(secure: secure, credential: draft.credential, trust: trust) : nil
            try store.write(draft.encoded())
            self.controller = nextController; self.inbox = nextInbox; self.readiness = readiness; approvedProfile = draft; self.draft = nil; error = ""
            UserDefaults.standard.set(true, forKey: "registeredDrillLaunch")
        } catch { self.error = "Could not save preparation; nothing was replaced. \(error)" }
    }
}

private struct RegisteredDrillView: View {
    @EnvironmentObject private var demo: DemoController
    @Environment(\.scenePhase) private var phase
    @StateObject private var preparation = RegisteredPreparation()
    @State private var importing = false
    @State private var exporting = false
    @State private var issuerChecked = false
    var body: some View {
        Group {
            if let inbox = preparation.inbox {
                VStack(spacing: 0) {
                    if !preparation.error.isEmpty { Text(preparation.error).foregroundStyle(.red).padding(.horizontal) }
                    if preparation.legacyAvailable {
                        Button("Open saved single-pair conversation") { preparation.switchResponderWorkspace(inbox: false) }.padding(.vertical, 8)
                        Text("Earlier paired history is preserved separately and is not imported into this inbox.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    RegisteredInboxWorkspace(inbox: inbox, readiness: preparation.readiness)
                }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Update registration") { preparation.updatePreparation(); issuerChecked = false }
                    } }
            } else if let controller = preparation.controller {
                VStack(spacing: 0) {
                    if !preparation.error.isEmpty { Text(preparation.error).foregroundStyle(.red).padding(.horizontal) }
                    if preparation.legacyAvailable {
                        Button("Open inbox for new public devices") { preparation.switchResponderWorkspace(inbox: true) }.padding(.vertical, 8)
                        Text("This saved single-pair conversation stays here. New public devices use the separate inbox; earlier request histories are not migrated.").font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                    }
                    RegisteredConversation(controller: controller, readiness: preparation.readiness)
                }
                    .toolbar { ToolbarItem(placement: .topBarTrailing) {
                        Button("Update registration") { preparation.updatePreparation(); issuerChecked = false }
                    } }
            } else {
                Form {
                    Section {
                        Text("Prepare before an outage").font(.headline)
                        Text("This is a synthetic drill registrar, not a live campus account. An organizer issues a credential for this device. No names, emails or private keys are exported.")
                        Picker("Device role", selection: Binding(get: { preparation.role.rawValue }, set: { preparation.select($0 == 1 ? .responder : .publicUser); issuerChecked = false })) {
                            Text("Public").tag(0); Text("Responder").tag(1)
                        }
                        Button("Export registration request") { exporting = true }.disabled(preparation.request.isEmpty)
                        Button("Import organizer-issued profile") { importing = true }.disabled(preparation.request.isEmpty)
                    }
                    if let draft = preparation.draft {
                        Section("Verify organizer during preparation") {
                            Text("\(preparation.role == .publicUser ? "Public" : "Responder") device · drill realm \(draft.realm.uuidString)").font(.caption)
                            if let summary = try? EnrollmentReadiness(profile: draft, card: SecurePairingCard(base64: preparation.request), issuerApproved: true, at: Int64(Date().timeIntervalSince1970)) {
                                Text("Prepared until \(Date(timeIntervalSince1970: TimeInterval(summary.validUntil)).formatted(date: .abbreviated, time: .shortened))").font(.caption)
                            }
                            Text("Compare the entire issuer fingerprint with the drill organizer over a trusted channel.")
                            Text(draft.issuerFingerprint).font(.caption.monospaced()).textSelection(.enabled)
                            Toggle("I verified this issuer with the organizer", isOn: $issuerChecked)
                            Button("Complete drill registration") { preparation.approve(issuerApproved: issuerChecked); issuerChecked = false }.disabled(!issuerChecked)
                        }
                    }
                    if !preparation.error.isEmpty { Text(preparation.error).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Registered drill")
        .onAppear { demo.stopLocalExchange(); preparation.select(EndpointRole(rawValue: UserDefaults.standard.integer(forKey: "registeredDrillRole")) ?? .publicUser) }
        .onDisappear { preparation.controller?.stop(); preparation.inbox?.stop() }
        .onChange(of: phase) { _, phase in if phase == .background { preparation.controller?.stop(); preparation.inbox?.stop() } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            issuerChecked = false
            switch result { case .success(let url): preparation.read(url); case .failure(let error): preparation.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: RegistrationRequestDocument(text: preparation.request), contentType: .plainText, defaultFilename: "rescue-registration-request") { result in
            if case .failure(let error) = result { preparation.error = error.localizedDescription }
        }
    }
}

private struct RegisteredConversation: View {
    @Environment(\.scenePhase) private var phase
    @State private var userStopped = false
    @ObservedObject var controller: RegisteredExchangeController
    let readiness: EnrollmentReadiness?
    @State private var error = ""
    @State private var reviewing = false
    @State private var reportedLocation = "Training Building A (sample) · Floor 1"
    private var publicSide: Bool { controller.secure.role == .publicUser }
    private func perform(_ action: DemoAction, value: String = "", reference: String = "") {
        do { try controller.perform(action, value: value, reference: reference); error = "" }
        catch { self.error = "Action not saved. \(error)" }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(publicSide ? "Public · registered drill" : "Responder · registered drill").font(.title2.bold())
                Text("Synthetic exercise · does not contact emergency services").font(.caption)
                if let readiness { RegisteredReadinessSummary(readiness: readiness) }
                Text(controller.status).font(.subheadline)
                Button(controller.transport.active ? "Stop exchange" : "Resume foreground exchange") {
                    if controller.transport.active { userStopped = true; controller.stop() }
                    else { do { userStopped = false; try controller.start(); error = "" } catch { self.error = "Could not start. \(error)" } }
                }.buttonStyle(.bordered)
                if let snapshot = controller.snapshot {
                    Text("\(snapshot.pendingTransfers) messages awaiting device receipt").font(.subheadline)
                    if snapshot.state.hasRequest {
                        Text(snapshot.state.reportedLocation).font(.headline)
                        if publicSide {
                            Text(deliveryText(snapshot.state.originalDelivery, publicSide: true))
                            Button("Send sample follow-up") { perform(.followUp, value: "SYNTHETIC: assistance still requested") }
                            Button("Send reported-location correction") { perform(.correction, value: reportedLocation) }
                            Button("Request withdrawal") { perform(.withdrawal) }
                        } else {
                            Button("Acknowledge request") { perform(.acknowledge) }
                            Button("Send sample reply") { perform(.reply, value: "SYNTHETIC: your request is being reviewed") }
                            Menu("Handling actions") {
                                Button("Assign sample team") { perform(.assign, value: "Synthetic team") }
                                Button("Resolve request") { perform(.resolve) }
                                Button("Reopen request") { perform(.reopen) }
                            }
                        }
                        Text("Handling: \(handlingText(snapshot.state.handling))")
                        Conversation(state: snapshot.state, publicSide: publicSide, acknowledge: publicSide ? nil : { reference in perform(.acknowledge, reference: reference) })
                    }
                    if publicSide {
                        TextField("Reported place and floor", text: $reportedLocation).textFieldStyle(.roundedBorder)
                            .onChange(of: reportedLocation) { _, _ in if reportedLocation.utf8.count > 256 { reportedLocation = String(reportedLocation.prefix(128)) } }
                        Text("Building and floor are manually reported. This drill does not include automatic location research.").font(.caption).foregroundStyle(.secondary)
                        if !snapshot.state.hasRequest { Button("Review sample SOS") { reviewing = true }.buttonStyle(PrimaryButtonStyle()) }
                    }
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                Text("Keep this screen open. Registration expires; expired preparation blocks exchange. One public/responder conversation; no automatic relay or background delivery.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: Theme.readableWidth).frame(maxWidth: .infinity)
        }
        .confirmationDialog("Send synthetic SOS with this reported location?", isPresented: $reviewing, titleVisibility: .visible) {
            Button("Send sample SOS") { perform(.sos, value: reportedLocation) }
        } message: { Text(reportedLocation) }
        .onAppear { do { try controller.start() } catch { self.error = "Could not start. \(error)" } }
        .onDisappear { controller.stop() }
        .onChange(of: phase) { _, phase in
            if phase == .background { controller.stop() }
            else if phase == .active && !userStopped && !controller.transport.active {
                do { try controller.start() } catch { self.error = "Could not resume. \(error)" }
            }
        }
    }
}

private struct RegisteredInboxWorkspace: View {
    @Environment(\.scenePhase) private var phase
    @ObservedObject var inbox: RegisteredResponderInbox
    let readiness: EnrollmentReadiness?
    @State private var selectedID: String?
    @State private var userStopped = false
    @State private var error = ""
    private func perform(_ id: String, _ action: DemoAction, value: String = "", reference: String = "") {
        do { try inbox.perform(conversationID: id, action: action, value: value, reference: reference); error = "" }
        catch { self.error = "Action not saved. \(error)" }
    }
    private func start() {
        do { try inbox.start(); userStopped = false; error = "" }
        catch { self.error = "Could not start. \(error)" }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Responder inbox").font(.title.bold())
                Text("Synthetic exercise · does not contact emergency services").font(.caption)
                if let readiness { RegisteredReadinessSummary(readiness: readiness) }
                Text(inbox.status).font(.subheadline)
                Button(inbox.transport.active ? "Stop exchange" : "Resume foreground exchange") {
                    if inbox.transport.active { userStopped = true; inbox.stop() } else { start() }
                }.buttonStyle(.bordered)
                Text("\(inbox.rows.count) of 16 public conversations").font(.headline)
                if inbox.rows.isEmpty {
                    ContentUnavailableView("Waiting for a registered request", systemImage: "tray", description: Text("Verified requests appear here when received locally. No request has arrived yet."))
                }
                ForEach(inbox.rows) { row in
                    Button {
                        selectedID = row.id
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.snapshot.state.reportedLocation).font(.headline)
                            Text("Device \(row.id.prefix(8)) · \(handlingText(row.snapshot.state.handling))").font(.caption)
                            Text("\(row.snapshot.pendingTransfers) replies or updates awaiting device receipt").font(.caption)
                            if selectedID == row.id { Label("Selected conversation", systemImage: "checkmark.circle.fill").font(.caption) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.bordered)
                    .accessibilityLabel("Select request from device \(row.id.prefix(8)), \(row.snapshot.state.reportedLocation)")
                }
                if let id = selectedID, let row = inbox.rows.first(where: { $0.id == id }) {
                    Divider()
                    Text("Request from device \(id.prefix(8))").font(.title3.bold())
                    LocationSummary(value: row.snapshot.state.reportedLocation)
                    Text("Handling: \(handlingText(row.snapshot.state.handling))")
                    Button("Acknowledge selected request") { perform(id, .acknowledge) }
                    Button("Reply to selected request") { perform(id, .reply, value: "SYNTHETIC: your request is being reviewed") }
                    Menu("Handling actions for selected request") {
                        Button("Assign sample team") { perform(id, .assign, value: "Synthetic team") }
                        Button("Resolve request") { perform(id, .resolve) }
                        Button("Reopen request") { perform(id, .reopen) }
                    }
                    Conversation(state: row.snapshot.state, publicSide: false, acknowledge: { reference in perform(id, .acknowledge, reference: reference) })
                }
                if !error.isEmpty { Text(error).foregroundStyle(.red) }
                Text("One saved request history per public device. Keep this screen open. No automatic relay or background delivery. Existing single-pair histories stay in their original workspace.").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(maxWidth: Theme.readableWidth).frame(maxWidth: .infinity)
        }
        .onAppear { start() }
        .onDisappear { inbox.stop() }
        .onChange(of: inbox.rows.map(\.id)) { _, ids in
            if selectedID == nil || !ids.contains(selectedID ?? "") { selectedID = ids.first }
        }
        .onChange(of: phase) { _, phase in
            if phase == .background { inbox.stop() }
            else if phase == .active && !userStopped && !inbox.transport.active { start() }
        }
    }
}

private struct RegisteredReadinessSummary: View {
    let readiness: EnrollmentReadiness
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let expiry = Date(timeIntervalSince1970: TimeInterval(readiness.validUntil))
            VStack(alignment: .leading, spacing: 4) {
                Label(context.date < expiry ? "Registration prepared" : "Registration expired — update before exchange", systemImage: context.date < expiry ? "checkmark.shield" : "exclamationmark.shield")
                    .foregroundStyle(context.date < expiry ? Color.secondary : Color.orange)
                Text("Valid until \(expiry.formatted(date: .abbreviated, time: .shortened)) · this device's clock").font(.caption)
                Text("Drill realm \(readiness.realm.uuidString)").font(.caption2.monospaced())
                Text("Preparation does not mean a responder is reachable. Keep the app open; queued messages wait for verified contact.").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
