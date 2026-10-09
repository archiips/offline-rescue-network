import SwiftUI
import RescueDemoState

struct PublicView: View {
    @EnvironmentObject private var demo: DemoController
    @Binding var floor: String
    @Binding var reviewing: Bool
    @State private var withdrawing = false
    private var location: String { "Training Building A · \(floor)" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let state = demo.snapshot?.publicState, state.hasRequest {
                    AudienceHeading(eyebrow: "Public", title: "Your request", systemImage: "person.fill")
                    summary(state)
                    updates
                    Conversation(state: state, publicSide: true, acknowledge: nil)
                } else {
                    AudienceHeading(eyebrow: "Public", title: "Ask for help nearby", systemImage: "person.fill")
                    intro
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .id(demo.snapshot?.publicState.hasRequest ?? false)
        .onAppear {
            if let value = demo.snapshot?.publicState.reportedLocation.split(separator: "·").last {
                floor = value.trimmingCharacters(in: .whitespaces)
            }
        }
        .sheet(isPresented: $reviewing) {
            NavigationStack {
                List {
                    Section("Review sample request") {
                        Label("SYNTHETIC assistance request", systemImage: "sos")
                        Label(location, systemImage: "mappin.and.ellipse")
                    }
                    Section {
                        Button { demo.perform(.sos, value: location); reviewing = false } label: {
                            Text("Send sample SOS").font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.amber).controlSize(.large)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    } footer: {
                        Text("The request is saved on this device first. Only a device receipt confirms it arrived; a person's acknowledgment is a separate step.")
                    }
                }
                .navigationTitle("Review SOS")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reviewing = false } } }
            }
            .fontDesign(.rounded)
            .tint(Theme.teal)
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Ask the responder to withdraw this request?", isPresented: $withdrawing, titleVisibility: .visible) {
            Button("Send withdrawal request", role: .destructive) { demo.perform(.withdrawal, value: "SYNTHETIC withdrawal request") }
        }
    }

    private var intro: some View {
        Group {
            Card {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle).foregroundStyle(Theme.amber)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Explore how a request reaches a responder and receives a human acknowledgment.")
                            .font(.body)
                        Text(demo.localRole == nil ? "This sample uses a simulated connection. It does not contact emergency services." : (demo.secureMode ? "Pair with a checked sample endpoint to exchange requests. This does not contact emergency services." : "This sample exchanges data with an unverified local peer. It does not contact emergency services."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Card("Sample reported location", systemImage: "mappin.and.ellipse") {
                Text("Training Building A").font(.headline)
                floorPicker
            }
            Button { reviewing = true } label: {
                Label("Review sample SOS", systemImage: "sos").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.amber).controlSize(.large)
        }
    }

    private func summary(_ state: DeviceSnapshot) -> some View {
        let received = state.originalDelivery != .waiting
        let acknowledged = state.originalDelivery == .humanAcknowledged
        return Card {
            Label(deliveryText(state.originalDelivery, publicSide: true), systemImage: acknowledged ? "hand.raised.fill" : received ? "checkmark.circle.fill" : "paperplane.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(received ? Theme.teal : Color.primary)
            FactRow {
                FactTile(title: "Device receipt", value: received ? "Received" : "Not yet", systemImage: "iphone.gen3", reached: received)
                FactTile(title: "Human", value: acknowledged ? "Acknowledged" : "Not yet", systemImage: "hand.raised.fill", reached: acknowledged)
                FactTile(title: "Handling", value: handlingText(state.handling), systemImage: handlingIcon(state.handling), reached: state.handling != .open)
            }
            LabeledContent("Reported location", value: state.reportedLocation)
            if !state.assignedTo.isEmpty { LabeledContent("Team", value: state.assignedTo) }
            if !state.reason.isEmpty { Text(state.reason) }
            if state.withdrawalPending {
                Label("Withdrawal awaiting responder decision", systemImage: "hourglass").foregroundStyle(Theme.amber)
            }
            if !state.withdrawalDisposition.isEmpty { Text(state.withdrawalDisposition) }
            Text("\(state.pendingPublicMessages) public messages awaiting device receipt")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var updates: some View {
        Card("Update your request", systemImage: "square.and.pencil") {
            floorPicker
            Button { demo.perform(.correction, value: location) } label: {
                Label("Send location correction", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button { demo.perform(.followUp, value: "SYNTHETIC: assistance still requested") } label: {
                Label("Send sample follow-up", systemImage: "text.bubble").frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(role: .destructive) { withdrawing = true } label: {
                Label("Request withdrawal", systemImage: "arrow.uturn.backward.circle").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.bordered)
    }

    private var floorPicker: some View {
        LabeledContent("Reported floor") {
            Picker("Reported floor", selection: $floor) { ForEach(["Unknown floor", "Floor 1", "Floor 2", "Floor 3", "Floor 4"], id: \.self) { Text($0) } }
                .pickerStyle(.menu).labelsHidden()
        }
    }
}
