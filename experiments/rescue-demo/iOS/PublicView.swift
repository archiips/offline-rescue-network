import SwiftUI
import RescueDemoState

struct PublicView: View {
    @EnvironmentObject private var demo: DemoController
    @Binding var floor: String
    @Binding var reviewing: Bool
    @State private var updating = false
    @State private var withdrawing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var location: String { "Training Building A · \(floor)" }
    private static let floors = ["Unknown floor", "Floor 1", "Floor 2", "Floor 3", "Floor 4"]
    private var hasRequest: Bool { demo.snapshot?.publicState.hasRequest ?? false }

    var body: some View {
        Group {
            if let state = demo.snapshot?.publicState, state.hasRequest {
                active(state).transition(.opacity)
            } else {
                idle.transition(.opacity)
            }
        }
        .animation(.rescue(reduceMotion), value: hasRequest)
        .onAppear {
            if let value = demo.snapshot?.publicState.reportedLocation.split(separator: "·").last {
                floor = value.trimmingCharacters(in: .whitespaces)
            }
        }
        .sheet(isPresented: $reviewing) { reviewSheet }
        .sheet(isPresented: $updating) { updateSheet }
    }

    // MARK: Idle

    private var idle: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ask for help nearby")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Save a request with your reported location. Track device receipt and human acknowledgment separately.")
                        .font(.body).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Your location")
                    Divider()
                    InfoRow(systemImage: "building.2", title: "Training Building A", subtitle: "Sample reported location")
                    Divider().padding(.leading, 42)
                    floorRow
                    Divider()
                }
                DisclosureGroup("How delivery works") {
                    SectionLabel(text: "What happens next")
                    Divider()
                    step(1, "Review before sending", "Nothing leaves this device until you confirm.")
                    Divider().padding(.leading, 42)
                    step(2, "Device receipt", "Confirms a responder device saved it — not that a person has seen it.")
                    Divider().padding(.leading, 42)
                    step(3, "Human acknowledgment", "A responder confirms they have read your request.")
                    Divider()
                }
                Text(demo.localRole == nil ? "This sample uses a simulated connection. It does not contact emergency services." : (demo.secureMode ? "Pair with a checked sample endpoint to exchange requests. This does not contact emergency services." : "This sample exchanges data with an unverified local peer. It does not contact emergency services."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
            .frame(maxWidth: Theme.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            ActionBar {
                Button { reviewing = true } label: { Text("Review sample SOS") }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityHint("Opens a review before anything is sent")
            }
        }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        InfoRow(systemImage: "\(number).circle", title: title, subtitle: detail)
    }

    private var floorRow: some View {
        InfoRow(systemImage: "stairs", title: "Reported floor") {
            Picker("Reported floor", selection: $floor) { ForEach(Self.floors, id: \.self) { Text($0) } }
                .pickerStyle(.menu).labelsHidden()
        }
    }

    // MARK: Active request

    private func active(_ state: DeviceSnapshot) -> some View {
        let received = state.originalDelivery != .waiting
        let acknowledged = state.originalDelivery == .humanAcknowledged
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your request").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Label {
                        Text(deliveryText(state.originalDelivery, publicSide: true)).contentTransition(.opacity)
                    } icon: {
                        Image(systemName: acknowledged ? "hand.raised.fill" : received ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(acknowledged ? Theme.accent : Theme.ink)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .font(.title3.weight(.semibold))
                    InfoRow(systemImage: "mappin.and.ellipse", title: state.reportedLocation, subtitle: "Reported location", symbolColor: Theme.ink)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Status")
                    Divider()
                    FactLine(title: "Device receipt", value: received ? "Received" : "Not yet", systemImage: "iphone.gen3", reached: received)
                    Divider().padding(.leading, 42)
                    FactLine(title: "Human acknowledgment", value: acknowledged ? "Recorded" : "Not yet", systemImage: "hand.raised", reached: acknowledged)
                    Divider().padding(.leading, 42)
                    FactLine(title: "Handling", value: handlingText(state.handling), systemImage: handlingIcon(state.handling), reached: state.handling != .open)
                    if !state.assignedTo.isEmpty {
                        Divider().padding(.leading, 42)
                        InfoRow(systemImage: "person.2", title: "Team", subtitle: state.assignedTo)
                    }
                    if !state.reason.isEmpty {
                        Divider().padding(.leading, 42)
                        InfoRow(systemImage: "text.alignleft", title: state.reason)
                    }
                    if state.withdrawalPending {
                        Divider().padding(.leading, 42)
                        Notice(text: "Withdrawal awaiting responder decision", systemImage: "hourglass")
                    }
                    if !state.withdrawalDisposition.isEmpty {
                        Divider().padding(.leading, 42)
                        InfoRow(systemImage: "doc.text", title: state.withdrawalDisposition)
                    }
                    Divider()
                    Text("\(state.pendingPublicMessages) public messages awaiting device receipt")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        .contentTransition(.numericText())
                }
                .animation(.rescue(reduceMotion), value: "\(state.originalDelivery.rawValue)\(state.handling.rawValue)\(state.withdrawalPending)\(state.assignedTo)\(state.pendingPublicMessages)")
                Conversation(state: state, publicSide: true, acknowledge: nil)
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
            .frame(maxWidth: Theme.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            ActionBar {
                Text(state.withdrawalPending ? "Withdrawal requested" : "Request actions")
                    .font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button { updating = true } label: { Label("Update", systemImage: "square.and.pencil") }
                    .buttonStyle(CompactButtonStyle(prominent: false))
                    .accessibilityHint("Location correction, follow-up or withdrawal")
            }
        }
    }

    // MARK: Sheets

    private var reviewSheet: some View {
        NavigationStack {
            List {
                Section {
                    Label("SYNTHETIC assistance request", systemImage: "sos")
                    Label(location, systemImage: "mappin.and.ellipse")
                } header: { Text("Review sample request") }
                Section {
                    Button { demo.perform(.sos, value: location); reviewing = false } label: {
                        Text("Send sample SOS")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                } footer: {
                    Text("The request is saved on this device first. Only a device receipt confirms it arrived; a person's acknowledgment is a separate step.")
                }
            }
            .navigationTitle("Review SOS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reviewing = false } } }
        }
        .tint(Theme.ink)
        .presentationDetents([.medium, .large])
    }

    private var updateSheet: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Reported floor", selection: $floor) { ForEach(Self.floors, id: \.self) { Text($0) } }
                        .pickerStyle(.menu)
                    Button { demo.perform(.correction, value: location); updating = false } label: {
                        Label("Send location correction", systemImage: "mappin.and.ellipse")
                    }
                } header: { Text("Location") } footer: { Text("Sends \(location) as a correction.") }
                Section("Message") {
                    Button { demo.perform(.followUp, value: "SYNTHETIC: assistance still requested"); updating = false } label: {
                        Label("Send sample follow-up", systemImage: "text.bubble")
                    }
                }
                Section {
                    Button(role: .destructive) { withdrawing = true } label: {
                        Label("Request withdrawal", systemImage: "arrow.uturn.backward.circle")
                    }
                } footer: { Text("A responder records the decision; this only asks.") }
            }
            .navigationTitle("Update request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { updating = false } } }
            .confirmationDialog("Ask the responder to withdraw this request?", isPresented: $withdrawing, titleVisibility: .visible) {
                Button("Send withdrawal request", role: .destructive) {
                    demo.perform(.withdrawal, value: "SYNTHETIC withdrawal request"); updating = false
                }
            }
        }
        .tint(Theme.ink)
        .presentationDetents([.medium, .large])
    }
}
