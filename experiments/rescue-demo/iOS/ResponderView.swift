import SwiftUI
import RescueDemoState

struct ResponderView: View {
    @EnvironmentObject private var demo: DemoController
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let state = demo.snapshot?.responderState, state.hasRequest {
                    let acknowledged = state.messages.contains(where: { $0.kind == .acknowledgment && $0.reference == "public-1" })
                    AudienceHeading(eyebrow: "Responder", title: "Sample assistance request", systemImage: "cross.case.fill")
                    overview(state, acknowledged: acknowledged)
                    if !acknowledged {
                        Button { demo.perform(.acknowledge) } label: {
                            Label("Acknowledge SOS", systemImage: "hand.raised.fill").font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    respond(state)
                    Conversation(state: state, publicSide: false, acknowledge: { demo.perform(.acknowledge, reference: $0) })
                } else {
                    AudienceHeading(eyebrow: "Responder", title: "Workspace", systemImage: "cross.case.fill")
                    Card {
                        ContentUnavailableView("No requests received", systemImage: "tray", description: Text(demo.localRole == nil ? "Send a sample SOS from the Public view. Disconnected requests wait until the simulated connection returns." : demo.relayMode ? "Start relay exchange on both endpoints. Upload the Public endpoint’s sample SOS, then forward it from the relay Mac. Queued messages stay saved until a device receipt returns." : "Start local exchange on a separate Public endpoint and transfer its sample SOS. Queued messages remain saved until a receipt returns."))
                    }
                }
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private func overview(_ state: DeviceSnapshot, acknowledged: Bool) -> some View {
        Card {
            Label("Request received locally", systemImage: "tray.and.arrow.down.fill")
                .font(.title3.weight(.semibold))
            FactRow {
                FactTile(title: "Your acknowledgment", value: acknowledged ? "Recorded" : "Not yet", systemImage: "hand.raised.fill", reached: acknowledged)
                FactTile(title: "Handling", value: handlingText(state.handling), systemImage: handlingIcon(state.handling), reached: state.handling != .open)
            }
            LabeledContent("Reported location", value: state.reportedLocation)
            if !state.assignedTo.isEmpty { LabeledContent("Team", value: state.assignedTo) }
            if state.lateUpdate {
                Label("Update arrived after resolution. Review before deciding to reopen.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.amber)
            }
            if state.withdrawalPending {
                Label("The public user asked to withdraw. Record a decision below.", systemImage: "hourglass")
                    .foregroundStyle(Theme.amber)
            }
        }
    }

    private func respond(_ state: DeviceSnapshot) -> some View {
        Card("Respond", systemImage: "arrowshape.turn.up.left") {
            Button { demo.perform(.reply, value: "SYNTHETIC: your request is being reviewed") } label: {
                Label("Send sample reply", systemImage: "bubble.left.fill").frame(maxWidth: .infinity, alignment: .leading)
            }
            if state.handling != .resolved {
                Button { demo.perform(.assign, value: "Training Team A") } label: {
                    Label("Assign Training Team A", systemImage: "person.2.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { demo.perform(.resolve, value: "SYNTHETIC: training assistance completed") } label: {
                    Label("Resolve sample request", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Button { demo.perform(.reopen, value: "SYNTHETIC: review late information") } label: {
                    Label("Reopen request", systemImage: "arrow.clockwise.circle").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if state.withdrawalPending {
                Button { demo.perform(.disposition, value: "SYNTHETIC: withdrawal reviewed; handling unchanged") } label: {
                    Label("Record withdrawal decision", systemImage: "doc.text").frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Device receipt does not acknowledge a request. Actions sent while disconnected stay queued.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
    }
}
