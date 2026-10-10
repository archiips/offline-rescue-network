import SwiftUI
import RescueDemoState

/// Foreground research only. No estimates are written to rescue messages or saved history.
struct FloorResearchView: View {
    @StateObject private var probe = NativeFloorResearch()
    @Environment(\.scenePhase) private var phase
    @State private var anchorLevel = ""
    @State private var floorHeight = ""

    var body: some View {
        Form {
            Section {
                Text("Automatic floor research").font(.headline)
                Text("Experimental sensor estimates, not a verified location. Your reported floor and rescue messages stay separate.")
                Text("Logical level 0 means ground; this may differ from building signs. Confidence is unvalidated.")
                    .foregroundStyle(.secondary)
            }
            Section("Input source") {
                Picker("Source", selection: Binding(get: { probe.synthetic }, set: { probe.changeSource(synthetic: $0) })) {
                    Text("Device sensors").tag(false)
                    Text("Synthetic fixtures").tag(true)
                }.pickerStyle(.menu)
                if probe.synthetic {
                    Text("SYNTHETIC · Logic demonstration only. No device sensors or real floor accuracy.")
                        .foregroundStyle(.orange)
                    Picker("Fixture", selection: Binding(get: { probe.fixture }, set: { probe.applyFixture($0) })) {
                        Text("No anchor").tag(0)
                        Text("Stable one level up").tag(1)
                        Text("Between levels").tag(2)
                        Text("Noisy readings").tag(3)
                        Text("Stale readings").tag(4)
                    }
                } else {
                    Text(probe.status).font(.caption)
                    if probe.running {
                        Button("Stop sensor research") { probe.stop() }
                    } else {
                        Button("Start foreground sensors") { probe.start() }
                    }
                }
            }
            Section("Apple floor observation") {
                LabeledContent("Logical level", value: probe.appleLevel.map(String.init) ?? "Unknown")
                Text(probe.appleStatus).font(.caption).foregroundStyle(.secondary)
                if let date = probe.appleObservedAt {
                    Text("Observed \(date.formatted(date: .abbreviated, time: .standard)) · Core Location · not a building-sign label")
                        .font(.caption)
                }
            }
            Section("Relative-altitude estimate") {
                LabeledContent("Candidate logical level", value: probe.relative.level.map(String.init) ?? "Unknown")
                Text(probe.relative.reason).font(.caption).foregroundStyle(.secondary)
                Text("Confidence: unvalidated · \(probe.synthetic ? "synthetic fixture" : "Core Motion + your starting reference")")
                    .font(.caption)
                if let date = probe.relativeObservedAt {
                    Text("Observed \(date.formatted(date: .abbreviated, time: .standard)) · estimate only")
                        .font(.caption)
                }
                if let altitude = probe.latestAltitude {
                    LabeledContent("Altitude since sensor start", value: String(format: "%.2f m", altitude))
                }
                if let anchor = probe.anchor {
                    Text("Starting reference: logical level \(anchor.level), \(anchor.floorHeight.formatted()) m per level")
                        .font(.caption)
                }
            }
            if !probe.synthetic {
                Section {
                    TextField("Known starting logical level (ground = 0)", text: $anchorLevel)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Measured metres between levels (2–8)", text: $floorHeight)
                        .keyboardType(.decimalPad)
                    Button("Set starting reference here") {
                        probe.setAnchor(level: Int(anchorLevel.trimmingCharacters(in: .whitespaces)), height: try? Double(floorHeight, format: .number.locale(Locale.current)))
                    }.disabled(!probe.running || !probe.referenceReady)
                    if !probe.referenceReady {
                        Text("Wait for at least three fresh, stable altitude readings across two seconds before setting a reference.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !probe.actionStatus.isEmpty { Text(probe.actionStatus).font(.caption) }
                    Button("Clear starting reference") { probe.clearAnchor() }
                        .disabled(probe.anchor == nil)
                    Text("Set this while stationary on a known level, after a fresh altitude reading. Use measured uniform floor spacing. Estimates expire after 10 seconds without readings; recalibrate after 10 minutes, restart, or a building change.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("Known starting reference") }
            }
            Section("Wi-Fi and next validation") {
                Text("No UW access-point map or Wi-Fi floor classifier is connected. Campus Wi-Fi coverage alone does not identify a floor.")
                Text("Device sensors need physical stairs, elevator and stationary trials against independently recorded floors. Synthetic fixtures only verify inference logic. Leaving this screen or backgrounding stops sensor research.")
                    .foregroundStyle(.secondary)
            }
        }
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .navigationTitle("Floor research")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: anchorLevel) { _, value in anchorLevel = String(value.prefix(8)) }
        .onChange(of: floorHeight) { _, value in floorHeight = String(value.prefix(8)) }
        .onChange(of: phase) { _, value in if value == .background { probe.stop() } }
        .onDisappear { probe.stop() }
    }
}
