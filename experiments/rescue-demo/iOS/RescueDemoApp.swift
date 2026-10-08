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
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Training demo · sample data", systemImage: "shield.lefthalf.filled").font(.headline)
                Toggle("Simulated connection", isOn: Binding(get: { demo.snapshot?.connected ?? false }, set: { demo.setConnected($0) }))
                    .disabled(demo.snapshot == nil)
                if let state = demo.snapshot {
                    Text("\(state.pendingTransfers) transfers queued · \(state.persistent ? "saved on this device" : "sample memory session")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !demo.error.isEmpty {
                    Text(demo.error).font(.callout).foregroundStyle(.red)
                    if demo.snapshot?.persistent == true { Button("Reopen saved session") { demo.retrySavedSession() } }
                }
                if let state = demo.snapshot, state.connected && state.pendingTransfers > 0 {
                    Button("Retry queued transfers") { demo.setConnected(true) }
                }
            }.padding().background(.thinMaterial)
            if demo.snapshot == nil {
                ContentUnavailableView("Saved session unavailable", systemImage: "externaldrive.badge.exclamationmark", description: Text("Your sample data has not been replaced. Retry opening it when storage is available."))
                Button("Retry saved session") { demo.retrySavedSession() }.buttonStyle(.borderedProminent).padding()
            } else {
            HStack {
                Button { responder = false } label: { Label("Public view", systemImage: "person.fill").frame(maxWidth: .infinity) }
                    .accessibilityAddTraits(responder ? [] : .isSelected)
                Button { responder = true } label: { Label("Responder view", systemImage: "cross.case.fill").frame(maxWidth: .infinity) }
                    .accessibilityAddTraits(responder ? .isSelected : [])
            }.buttonStyle(.bordered).padding(.horizontal).padding(.vertical, 8)
            if responder {
                NavigationStack { ResponderView().toolbar { resetButton } }
            } else {
                NavigationStack { PublicView().toolbar { resetButton } }
            }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .confirmationDialog("Clear this training session?", isPresented: $confirmingReset, titleVisibility: .visible) {
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
