import SwiftUI
import RescueDemoState

struct ResponderView: View {
    @EnvironmentObject private var demo: DemoController
    var body: some View {
        List {
            if let state = demo.snapshot?.responderState, state.hasRequest {
                Section("Sample assistance request") {
                    Label("Request received locally", systemImage: "tray.and.arrow.down.fill").font(.headline)
                    LabeledContent("Reported location", value: state.reportedLocation)
                    LabeledContent("Handling", value: handlingText(state.handling))
                    if !state.assignedTo.isEmpty { LabeledContent("Team", value: state.assignedTo) }
                    if state.lateUpdate { Label("Update arrived after resolution. Review before deciding to reopen.", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    if !state.messages.contains(where: { $0.kind == .acknowledgment && $0.reference == "public-1" }) {
                        Button("Acknowledge SOS") { demo.perform(.acknowledge) }.buttonStyle(.borderedProminent)
                    }
                }
                Section("Respond") {
                    Button("Send sample reply") { demo.perform(.reply, value: "SYNTHETIC: your request is being reviewed") }
                    if state.handling != .resolved {
                        Button("Assign Training Team A") { demo.perform(.assign, value: "Training Team A") }
                        Button("Resolve sample request") { demo.perform(.resolve, value: "SYNTHETIC: training assistance completed") }
                    } else {
                        Button("Reopen request") { demo.perform(.reopen, value: "SYNTHETIC: review late information") }
                    }
                    if state.withdrawalPending {
                        Button("Record withdrawal decision") { demo.perform(.disposition, value: "SYNTHETIC: withdrawal reviewed; handling unchanged") }
                    }
                    Text("Device receipt does not acknowledge a request. Actions sent while disconnected stay queued.").font(.caption).foregroundStyle(.secondary)
                }
                Conversation(state: state, publicSide: false, acknowledge: { demo.perform(.acknowledge, reference: $0) })
            } else {
                ContentUnavailableView("No requests received", systemImage: "tray", description: Text("Send a sample SOS from the Public view. Disconnected requests wait until the simulated connection returns."))
            }
        }.navigationTitle("Responder").navigationBarTitleDisplayMode(.inline)
    }
}
