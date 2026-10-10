import SwiftUI
import RescueDemoState

struct ResponderView: View {
    @EnvironmentObject private var demo: DemoController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var hasRequest: Bool { demo.snapshot?.responderState.hasRequest ?? false }
    var body: some View {
        Group {
            if let state = demo.snapshot?.responderState, state.hasRequest {
                workspace(state).transition(.opacity)
            } else {
                empty.transition(.opacity)
            }
        }
        .animation(.rescue(reduceMotion), value: hasRequest)
    }

    private var empty: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Requests").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Divider()
                ContentUnavailableView("No requests received", systemImage: "tray", description: Text(demo.localRole == nil ? "Send a sample SOS from the Public view. Disconnected requests wait until the simulated connection returns." : demo.relayMode ? "Start relay exchange on both endpoints. Upload the Public endpoint’s sample SOS, then forward it from the relay Mac. Queued messages stay saved until a device receipt returns." : "Start local exchange on a separate Public endpoint and transfer its sample SOS. Queued messages remain saved until a receipt returns."))
            }
            .padding(.horizontal, 20).padding(.top, 24)
            .frame(maxWidth: Theme.readableWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func workspace(_ state: DeviceSnapshot) -> some View {
        let acknowledged = state.messages.contains(where: { $0.kind == .acknowledgment && $0.reference == "public-1" })
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Sample assistance request · received locally", systemImage: "tray.and.arrow.down")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    LocationSummary(value: state.reportedLocation)
                        .font(.largeTitle.bold())

                        .accessibilityAddTraits(.isHeader)
                    Text("Reported location · as sent by the public device")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Status")
                    Divider()
                    FactLine(title: "Your acknowledgment", value: acknowledged ? "Recorded" : "Not yet", systemImage: "hand.raised", reached: acknowledged)
                    Divider().padding(.leading, 42)
                    FactLine(title: "Handling", value: handlingText(state.handling), systemImage: handlingIcon(state.handling), reached: state.handling != .open)
                    if !state.assignedTo.isEmpty {
                        Divider().padding(.leading, 42)
                        InfoRow(systemImage: "person.2", title: "Team", subtitle: state.assignedTo)
                    }
                    if state.lateUpdate {
                        Divider().padding(.leading, 42)
                        Notice(text: "Update arrived after resolution. Review before deciding to reopen.", systemImage: "exclamationmark.triangle.fill")
                    }
                    if state.withdrawalPending {
                        Divider().padding(.leading, 42)
                        HStack(alignment: .center) {
                            Notice(text: "The public user asked to withdraw. Record a decision.", systemImage: "hourglass")
                            recordDecisionButton
                                .buttonStyle(CompactButtonStyle(prominent: false))
                        }
                    }
                    Divider()
                    Text("Device receipt does not acknowledge a request. Actions sent while disconnected stay queued.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
                .animation(.rescue(reduceMotion), value: "\(acknowledged)\(state.handling.rawValue)\(state.withdrawalPending)\(state.lateUpdate)\(state.assignedTo)")
                Conversation(state: state, publicSide: false, acknowledge: { demo.perform(.acknowledge, reference: $0) })
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
            .frame(maxWidth: Theme.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            ActionBar {
                if !acknowledged {
                    Button { demo.perform(.acknowledge) } label: { Label("Acknowledge SOS", systemImage: "hand.raised.fill") }
                        .buttonStyle(PrimaryButtonStyle())
                        .transition(.opacity)
                }
                Button { demo.perform(.reply, value: "SYNTHETIC: your request is being reviewed") } label: {
                    Label(acknowledged ? "Send sample reply" : "Reply", systemImage: "bubble.left.fill")
                        .frame(maxWidth: acknowledged ? .infinity : nil)
                }
                .buttonStyle(CompactButtonStyle(prominent: acknowledged))
                .accessibilityLabel("Send sample reply")
                handlingMenu(state)
            }
            .animation(.rescue(reduceMotion), value: acknowledged)
        }
    }

    private var recordDecisionButton: some View {
        Button { demo.perform(.disposition, value: "SYNTHETIC: withdrawal reviewed; handling unchanged") } label: {
            Label("Record withdrawal decision", systemImage: "doc.text")
        }
    }

    private func handlingMenu(_ state: DeviceSnapshot) -> some View {
        Menu {
            if state.handling != .resolved {
                Button { demo.perform(.assign, value: "Training Team A") } label: {
                    Label("Assign Training Team A", systemImage: "person.2.fill")
                }
                Button { demo.perform(.resolve, value: "SYNTHETIC: training assistance completed") } label: {
                    Label("Resolve sample request", systemImage: "checkmark.seal.fill")
                }
            } else {
                Button { demo.perform(.reopen, value: "SYNTHETIC: review late information") } label: {
                    Label("Reopen request", systemImage: "arrow.clockwise.circle")
                }
            }
            if state.withdrawalPending { recordDecisionButton }
        } label: {
            Label("Handling", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(Color(uiColor: .secondarySystemBackground), in: Circle())
        }
        .accessibilityLabel("Handling actions")
        .accessibilityHint("Assign, resolve, reopen or record a withdrawal decision")
    }
}
