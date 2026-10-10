import SwiftUI
import Combine
import Network
import RescueDemoState

/// Optional memory-only research; separate ephemeral pairing; entering stops rescue networking while retaining its saved state.
struct LiveCooperativeResearchView: View {
    @StateObject private var probe = NativeFloorResearch()
    @StateObject private var wifi = NativeWiFiResearch()
    @StateObject private var peer = ResearchPeerController()
    @EnvironmentObject private var demo: DemoController
    @Environment(\.scenePhase) private var phase
    @State private var role = 0
    @State private var context = ""
    @State private var peerInput = ""
    @State private var checked = false
    @State private var setupStatus = ""
    @State private var anchorLevel = ""
    @State private var floorHeight = ""
    @State private var tick = ProcessInfo.processInfo.systemUptime
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var candidate: SecurePairingCard? { try? SecurePairingCard(base64: peerInput.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private var localReadings: [ResearchFloorReading] {
        guard probe.running, !probe.synthetic else { return [] }
        var readings: [ResearchFloorReading] = []
        if let level = probe.appleLevel, let time = probe.appleSampledAt {
            readings.append(.init(level: level, source: .appleFloor, sampledAt: time, id: probe.appleReadingID))
        }
        if let level = probe.relative.level, let time = probe.relativeSampledAt {
            readings.append(.init(level: level, source: .relativeAltitude, sampledAt: time, id: probe.relativeReadingID))
        }
        return readings
    }
    private var localReading: ResearchFloorReading? {
        LiveResearchGraph.sharingReading(local: localReadings, now: ProcessInfo.processInfo.systemUptime)
    }
    private var graph: GraphFloorResult {
        LiveResearchGraph.evaluate(local: localReadings, peer: peer.observation, now: max(tick, ProcessInfo.processInfo.systemUptime))
    }
    var body: some View {
        Form {
            Section {
                Text("Live cooperative inputs · experimental").font(.headline)
                Text("Optional foreground research. Sensor estimates are unvalidated. Nothing enters your SOS or saved history. Wi-Fi identifiers stay on this device. Entering stops rescue networking; restart it explicitly in Setup.")
                Text("Two opted-in participants only. Nearby contact never proves the same floor. No campus map or physical accuracy result yet.").font(.caption).foregroundStyle(.secondary)
            }
            Section("This phone’s sensors") {
                Button(probe.running ? "Stop sensors" : "Start foreground sensors") {
                    if probe.running { probe.stop() } else { probe.start() }
                    syncReading()
                }
                LabeledContent("Apple logical floor", value: probe.appleLevel.map(String.init) ?? "Unknown")
                Text(probe.appleStatus).font(.caption)
                LabeledContent("Relative-altitude candidate", value: probe.relative.level.map(String.init) ?? "Unknown")
                Text(probe.relative.reason).font(.caption)
                TextField("Known starting logical level", text: $anchorLevel).keyboardType(.numbersAndPunctuation)
                TextField("Measured metres per level (2–8)", text: $floorHeight).keyboardType(.decimalPad)
                Button("Calibrate relative altitude here") {
                    probe.setAnchor(level: Int(anchorLevel), height: try? Double(floorHeight, format: .number.locale(Locale.current)))
                    syncReading()
                }.disabled(!probe.running || !probe.referenceReady)
                if !probe.actionStatus.isEmpty { Text(probe.actionStatus).font(.caption) }
                Text("Calibration is a known starting reference, not your reported SOS floor. Conflicting sensors or missing reference produce Unknown.").font(.caption).foregroundStyle(.secondary)
            }
            ConnectedNetworkSection(capture: wifi.capture, request: wifi.request, clear: wifi.stop)
            Section("Independent research pairing") {
                Picker("Research role", selection: $role) {
                    Text("Public participant").tag(0)
                    Text("Responder participant").tag(1)
                }.pickerStyle(.menu).disabled(peer.transport.active || peer.busy)
                if let activeContext = peer.configuredContext {
                    Text("Active paired context: \(activeContext). Editing the draft below requires pairing again.").font(.caption)
                }
                Text("Temporary research identity; re-pair after leaving this workspace or restarting. Rescue pairing is separate.").font(.caption)
                Text("Your full fingerprint").font(.caption)
                Text(peer.card.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("Your public research card").font(.caption)
                Text(peer.card.base64).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                TextField("Research context · match the other device", text: $context).disabled(peer.transport.active || peer.busy)
                TextField("Other participant’s research public card", text: $peerInput, axis: .vertical).disabled(peer.transport.active || peer.busy)
                if let candidate {
                    Text("Other full fingerprint").font(.caption)
                    Text(candidate.fingerprint).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                Toggle("I compared the complete fingerprint on the other device", isOn: $checked).disabled(peer.transport.active || peer.busy)
                Button("Pair research participant") {
                    do {
                        try peer.configure(peerBase64: peerInput.trimmingCharacters(in: .whitespacesAndNewlines), context: context, checkedFingerprint: checked)
                        setupStatus = "Research participant paired. Sharing remains stopped."
                        syncReading()
                    } catch { setupStatus = "Research pairing unavailable: \(String(describing: error))" }
                }.disabled(!checked || candidate == nil || peer.transport.active || peer.busy)
                if !setupStatus.isEmpty { Text(setupStatus).font(.caption) }
            }
            ResearchConnectionSection(peer: peer, syncReading: syncReading)
            Section("Current graph · target is this phone") {
                LabeledContent("Candidate logical level", value: graph.level.map(String.init) ?? "Unknown")
                Text(graph.reason.message).font(.caption)
                Text("This phone = node 1; paired participant = node 2. The phone contact adds no floor constraint. Connected Wi-Fi has no surveyed mapping, so it adds context only.").font(.caption).foregroundStyle(.secondary)
                Text("A peer’s estimate is shown separately and cannot determine your floor from contact alone. Relative-position measurements remain a later input.").font(.caption)
            }
            Section {
                Button("Stop and clear all research") { stopAll() }
                Text("Home test first, then repeated Bothell routes, then Seattle evaluation. Leaving or backgrounding stops sharing and sensors; nothing resumes automatically.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Live research inputs").navigationBarTitleDisplayMode(.inline)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .onChange(of: role) { _, value in peer.reset(role: value == 0 ? .publicUser : .responder); checked = false; peerInput = ""; setupStatus = "" }
        .onChange(of: peerInput) { _, value in checked = false; if value.count > 256 { peerInput = String(value.prefix(256)) } }
        .onChange(of: context) { _, value in checked = false; if value.count > 64 { context = String(value.prefix(64)) } }
        .onChange(of: anchorLevel) { _, value in anchorLevel = String(value.prefix(8)) }
        .onChange(of: floorHeight) { _, value in floorHeight = String(value.prefix(8)) }
        .onChange(of: probe.appleLevel) { _, _ in syncReading() }
        .onChange(of: probe.relative.level) { _, _ in syncReading() }
        .onReceive(clock) { _ in tick = ProcessInfo.processInfo.systemUptime; syncReading() }
        .onChange(of: phase) { _, value in if value == .background { stopAll() } }
        .onAppear { demo.stopLocalExchange() }
        .onDisappear { stopAll() }
    }
    private func syncReading() {
        if let localReading { peer.updateLocalReading(localReading) }
        else if probe.running, !probe.synthetic {
            // An original observation of present unavailability, never a floor reference.
            peer.updateLocalReading(.init(level: nil, source: .unavailable, sampledAt: ProcessInfo.processInfo.systemUptime))
        } else { peer.updateLocalReading(nil) }
    }
    private func stopAll() { peer.stop(); probe.stop(); wifi.stop() }
}

private struct ConnectedNetworkSection: View {
    @ObservedObject var capture: ConnectedWiFiResearch
    let request: () -> Void
    let clear: () -> Void
    var body: some View {
        Section("Connected Wi-Fi · local only") {
            #if RESCUE_NO_WIFI_INFO
            Text("Connected Wi-Fi information is disabled in this free-account build. Local messaging and phone sensors remain available.")
            #else
            Button("Capture connected Wi-Fi context", action: request).disabled(capture.busy)
            if capture.busy { ProgressView("Reading connected network") }
            Text(capture.status).font(.caption)
            if let observation = capture.observation {
                LabeledContent("SSID", value: observation.ssid)
                LabeledContent("BSSID", value: observation.bssid)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = ProcessInfo.processInfo.systemUptime
                    Text("Captured \(max(0, now - observation.capturedAt).formatted(.number.precision(.fractionLength(1)))) s ago · \(observation.isFresh(at: now) ? "recent snapshot" : "expired snapshot") · not live").font(.caption)
                }
            }
            #endif
            Button("Clear Wi-Fi context", action: clear)
            Text("Precise location permission and signed Wi-Fi capability are required. No AP scan, no RSSI, no surveyed UW floor map. Identifiers are never shared or saved.").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ResearchConnectionSection: View {
    @ObservedObject var peer: ResearchPeerController
    @ObservedObject private var transport: LocalExchangeTransport
    @State private var startError = ""
    let syncReading: () -> Void
    init(peer: ResearchPeerController, syncReading: @escaping () -> Void) {
        self.peer = peer; self.transport = peer.transport; self.syncReading = syncReading
    }
    var body: some View {
        Section("Opt-in encrypted observation exchange") {
            Button(transport.active ? "Stop research sharing" : "Start research sharing") {
                if transport.active { peer.stop() } else {
                    do { try peer.start(); syncReading(); startError = "" } catch { startError = String(describing: error) }
                }
            }.disabled(peer.peerCard == nil || peer.busy)
            Text(peer.status).font(.caption)
            if !startError.isEmpty { Text(startError).font(.caption) }
            Text(transport.status).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(transport.peers.enumerated()), id: \.offset) { _, result in
                Button("Request observation from \(result.endpoint)") {
                    syncReading()
                    Task { await peer.requestObservation(to: result.endpoint) }
                }.disabled(peer.busy || !transport.active)
            }
            if transport.active && transport.peers.isEmpty { Text("Start research sharing on both paired participants. Discovery names are untrusted.").font(.caption) }
            if let observation = peer.observation {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = ProcessInfo.processInfo.systemUptime
                    LabeledContent("Peer-reported logical level", value: observation.isFresh(at: now) ? observation.level.map(String.init) ?? "Unknown" : "Unknown · expired")
                    Text("\(observation.source.rawValue) · age upper bound \(observation.age(at: now).formatted(.number.precision(.fractionLength(1)))) s · peer claim, not verified floor").font(.caption)
                    Text("Original \(observation.id.uuidString) · pinned sender \(observation.fingerprint)").font(.caption2).textSelection(.enabled)
                }
            }
            Text("Only your checked research participant can decrypt or supply observations. This does not verify their sensor accuracy. Research observations are not rescue receipts.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
