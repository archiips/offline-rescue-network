import SwiftUI
import RescueDemoState

struct PublicView: View {
    @EnvironmentObject private var demo: DemoController
    @State private var floor = "Floor 1"
    @State private var reviewing = false
    @State private var withdrawing = false
    private var location: String { "Training Building A · \(floor)" }
    var body: some View {
        List {
            if let state = demo.snapshot?.publicState, state.hasRequest {
                Section("Your assistance request") {
                    Label(deliveryText(state.originalDelivery, publicSide: true), systemImage: "paperplane.fill").font(.headline)
                    LabeledContent("Handling", value: handlingText(state.handling))
                    LabeledContent("Reported location", value: state.reportedLocation)
                    if !state.assignedTo.isEmpty { LabeledContent("Team", value: state.assignedTo) }
                    if !state.reason.isEmpty { Text(state.reason) }
                    if state.withdrawalPending { Text("Withdrawal awaiting responder decision").foregroundStyle(.orange) }
                    if !state.withdrawalDisposition.isEmpty { Text(state.withdrawalDisposition) }
                    Text("\(state.pendingPublicMessages) public messages awaiting device receipt").font(.caption)
                }
                Section("Update your request") {
                    floorPicker
                    Button("Send location correction") { demo.perform(.correction, value: location) }
                    Button("Send sample follow-up") { demo.perform(.followUp, value: "SYNTHETIC: assistance still requested") }
                    Button("Request withdrawal", role: .destructive) { withdrawing = true }
                }
                Conversation(state: state, publicSide: true, acknowledge: nil)
            } else {
                Section {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 44)).foregroundStyle(.orange).accessibilityHidden(true)
                    Text("Ask for help nearby").font(.title2.bold())
                    Text("Explore how a request reaches a responder and receives a human acknowledgment.")
                    Text(demo.localRole == nil ? "This sample uses a simulated connection. It does not contact emergency services." : (demo.secureMode ? "Pair with a checked sample endpoint to exchange requests. This does not contact emergency services." : "This sample exchanges data with an unverified local peer. It does not contact emergency services.")).font(.caption).foregroundStyle(.secondary)
                }
                Section("Sample reported location") { floorPicker; Text("Training Building A") }
                Section { Button("Review sample SOS") { reviewing = true }.buttonStyle(.borderedProminent).tint(.orange) }
            }
        }.id(demo.snapshot?.publicState.hasRequest ?? false).navigationTitle("Public").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let value = demo.snapshot?.publicState.reportedLocation.split(separator: "·").last {
                floor = value.trimmingCharacters(in: .whitespaces)
            }
        }
        .sheet(isPresented: $reviewing) {
            NavigationStack {
                List {
                    Section("Review sample request") { Text("SYNTHETIC assistance request"); Text(location) }
                    Section { Button("Send sample SOS") { demo.perform(.sos, value: location); reviewing = false }.buttonStyle(.borderedProminent) }
                }.navigationTitle("Review SOS").toolbar { Button("Cancel") { reviewing = false } }
            }.presentationDetents([.medium, .large])
        }
        .confirmationDialog("Ask the responder to withdraw this request?", isPresented: $withdrawing, titleVisibility: .visible) {
            Button("Send withdrawal request", role: .destructive) { demo.perform(.withdrawal, value: "SYNTHETIC withdrawal request") }
        }
    }
    private var floorPicker: some View {
        Picker("Reported floor", selection: $floor) { ForEach(["Unknown floor", "Floor 1", "Floor 2", "Floor 3", "Floor 4"], id: \.self) { Text($0) } }
    }
}
