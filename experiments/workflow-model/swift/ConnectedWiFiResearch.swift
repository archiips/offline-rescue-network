import Foundation
import Combine

/// Local-memory research context only. SSID/BSSID never imply a floor and are never peer payloads.
public struct ConnectedWiFiObservation: Sendable {
    public let ssid, bssid: String
    public let capturedAt: Double
    public init?(ssid: String, bssid: String, capturedAt: Double) {
        let pieces = bssid.lowercased().split(separator: ":", omittingEmptySubsequences: false)
        guard (1...32).contains(ssid.utf8.count), !ssid.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              pieces.count == 6, pieces.allSatisfy({ $0.count == 2 && $0.allSatisfy { $0.isASCII && $0.isHexDigit } }),
              let first = UInt8(pieces[0], radix: 16), first & 1 == 0,
              pieces.contains(where: { $0 != "00" }), capturedAt.isFinite, capturedAt >= 0 else { return nil }
        self.ssid = ssid; self.bssid = pieces.joined(separator: ":"); self.capturedAt = capturedAt
    }
    public func isFresh(at now: Double) -> Bool { now.isFinite && now >= capturedAt && now - capturedAt <= 10 }
}

/// Callback-based adapter permits a finite timeout even when the platform callback never arrives.
@MainActor public final class ConnectedWiFiResearch: ObservableObject {
    @Published public private(set) var observation: ConnectedWiFiObservation?
    @Published public private(set) var busy = false
    @Published public private(set) var status = "Not captured. Connected-network context only, not a floor."
    private var generation = UUID()
    private var deadline: Task<Void, Never>?
    private let timeout: Duration
    public init(timeout: Duration = .seconds(3)) { self.timeout = timeout }
    public func clear() {
        generation = UUID(); deadline?.cancel(); deadline = nil; busy = false; observation = nil
        status = "Cleared. Nothing saved or sent."
    }
    public func capture(authorized: Bool, fetch: (@escaping @Sendable (String?, String?) -> Void) -> Void) {
        guard !busy else { return }
        clear()
        guard authorized else { status = "Unavailable: precise location permission is required for connected Wi-Fi information."; return }
        let run = generation
        let expires = ContinuousClock.now.advanced(by: timeout)
        busy = true; status = "Reading connected network…"
        deadline = Task { [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.generation == run, self.busy else { return }
            self.clear(); self.status = "Unavailable: connected-network lookup timed out. Retry explicitly."
        }
        fetch { [weak self] ssid, bssid in
            Task { @MainActor [weak self] in
                guard let self, self.generation == run, self.busy else { return }
                guard ContinuousClock.now < expires else {
                    self.clear(); self.status = "Unavailable: connected-network lookup timed out. Retry explicitly."
                    return
                }
                self.deadline?.cancel(); self.deadline = nil; self.busy = false
                if let ssid, let bssid, let value = ConnectedWiFiObservation(ssid: ssid, bssid: bssid, capturedAt: ProcessInfo.processInfo.systemUptime) {
                    self.observation = value
                    self.status = "Connected-network snapshot. No surveyed floor mapping; not live."
                } else {
                    self.observation = nil
                    self.status = "Unavailable: no permitted connected-network information. Check permission, Wi-Fi and signing capability; Simulator may not supply it."
                }
            }
        }
    }
}
