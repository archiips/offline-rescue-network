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
            Section("Cooperative localization") {
                NavigationLink("Wi-Fi + nearby-phone graph replay") { CooperativeGraphResearchView() }
                Text("Synthetic references and constraints only. Live Wi-Fi and participating-phone inputs are not connected yet.").font(.caption).foregroundStyle(.secondary)
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


/// Isolated replay. No sensor callbacks, networking, history writes or SOS estimate attachment.
private struct CooperativeGraphResearchView: View {
    @State private var selection = 0
    private var scenario: CooperativeFloorScenario { CooperativeFloorReplay.scenarios[selection] }

    var body: some View {
        Form {
            Section {
                Text("SYNTHETIC · Cooperative floor graph").font(.headline).foregroundStyle(.orange)
                Text("Fictional observations, not your location. No live Wi-Fi or nearby-phone positioning. Confidence and physical accuracy are unvalidated.")
                Text("One building/session · replay time 100 s · evidence expires after 10 s · logical level 0 = ground")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Replay scenario") {
                Picker("Scenario", selection: $selection) {
                    ForEach(CooperativeFloorReplay.scenarios.indices, id: \.self) { index in
                        Text(CooperativeFloorReplay.scenarios[index].title).tag(index)
                    }
                }.pickerStyle(.menu)
                Text(scenario.explanation)
            }
            Section("Matched input comparison") {
                let results = scenario.results
                ForEach(CooperativeFloorMode.allCases, id: \.self) { mode in
                    if let result = results[mode] {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(mode.rawValue, value: result.level.map { "Candidate \($0)" } ?? "Unknown")
                            Text(result.reason.message).font(.caption).foregroundStyle(.secondary)
                            if let low = result.minimumLevel, let high = result.maximumLevel, low != high {
                                Text("Possible logical levels: \(low)…\(high)").font(.caption)
                            }
                            if result.reason == .candidate || result.reason == .ambiguous || result.reason == .noReference {
                                Text("Contributing origins: \(result.origins) · expired/future records: \(result.skipped) · not a confidence score")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Evidence counts unavailable for rejected input · not a confidence score")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section("Graph inputs · target phone \(scenario.target)") {
                Text("Nodes: \(scenario.nodes.map { String($0) }.joined(separator: ", "))").font(.caption)
                ForEach(Array(scenario.observations.enumerated()), id: \.offset) { _, observation in
                    VStack(alignment: .leading) {
                        Text("Node \(observation.node) reference: level \(observation.minimumLevel)…\(observation.maximumLevel)")
                        Text("\(sourceName(observation.source)) · origin \(observation.origin)/observation \(observation.observation) · observed t=\(observation.elapsed.formatted()) s")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(scenario.edges.enumerated()), id: \.offset) { _, edge in
                    Text(edge.kind == .contact
                         ? "\(edge.from) ↔ \(edge.to): contact only; no floor constraint"
                         : "\(edge.from) → \(edge.to): synthetic relative levels \(edge.minimumDelta)…\(edge.maximumDelta)")
                        .font(.caption)
                }
            }
            Section("What remains") {
                Text("Next: opt-in authenticated phone observations, permitted Wi-Fi references, and independent physical comparisons. First campus routes: Bothell; later evaluation: Seattle.")
                Text("A phone contact or shared SSID never proves the same floor. Reported floor and rescue messages remain separate.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Cooperative graph")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sourceName(_ source: GraphFloorSource) -> String {
        switch source {
        case .sensor: "Synthetic sensor"
        case .surveyedWiFi: "Synthetic surveyed Wi-Fi reference"
        case .knownReference: "Synthetic known reference"
        }
    }
}
