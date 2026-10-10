import RescueDemoBridge

/// One relative-altimeter observation. Altitude is metres from the session baseline; elapsed is
/// monotonic session seconds, never wall-clock time.
public struct RelativeFloorSample: Sendable {
    public let altitude: Double
    public let elapsed: Double
    public init(altitude: Double, elapsed: Double) {
        self.altitude = altitude
        self.elapsed = elapsed
    }
}

/// Explicit known logical level (0 = ground, not signage) and measured uniform floor height, captured
/// at one session altitude and time.
public struct RelativeFloorAnchor: Sendable {
    public let level: Int
    public let altitude: Double
    public let elapsed: Double
    public let floorHeight: Double
    public init(level: Int, altitude: Double, elapsed: Double, floorHeight: Double) {
        self.level = level
        self.altitude = altitude
        self.elapsed = elapsed
        self.floorHeight = floorHeight
    }
}

/// `level` is an unvalidated anchor-relative candidate, never a confirmed or reported floor.
public struct FloorProbeResult: Sendable {
    public let level: Int?
    public let reason: String
}

/// Matches rc_floor_reason. Presentation only; the C++ engine decides.
enum FloorProbeReason: Int32, CaseIterable, Sendable {
    case noOutput = -1, candidate = 0, noAnchor, invalidInput, invalidHeight, invalidLevel, future, staleAnchor,
         tooFew, tooMany, anchorAfterSample, unordered, staleSamples, shortWindow, noisy, transition, outOfRange

    var message: String {
        switch self {
        case .noOutput: "Unknown: estimator output unavailable"
        case .candidate: "Unvalidated anchor-relative candidate"
        case .noAnchor: "Unknown: no anchor set"
        case .invalidInput: "Unknown: invalid time or altitude input"
        case .invalidHeight: "Unknown: floor height must be 2–8 m"
        case .invalidLevel: "Unknown: anchor level must be -20…200"
        case .future: "Unknown: anchor or sample is later than now"
        case .staleAnchor: "Unknown: anchor older than 10 minutes"
        case .tooFew: "Unknown: fewer than 3 altitude samples"
        case .tooMany: "Unknown: more than 64 altitude samples"
        case .anchorAfterSample: "Unknown: anchor is later than a sample"
        case .unordered: "Unknown: sample times not strictly increasing"
        case .staleSamples: "Unknown: altitude samples older than 10 seconds"
        case .shortWindow: "Unknown: sample window shorter than 2 seconds"
        case .noisy: "Unknown: altitude unstable"
        case .transition: "Unknown: between floors"
        case .outOfRange: "Unknown: candidate outside level -20…200"
        }
    }

    static func message(for raw: Int32) -> String { Self(rawValue: raw)?.message ?? "Unknown: unrecognized estimator result" }
}

public enum FloorProbe {
    /// Calibrate only from a window accepted by the same C++ stability/freshness guards. The
    /// median reduces sensitivity to one sample; the reference epoch begins at the latest event.
    public static func calibrate(level: Int, height: Double, samples: [RelativeFloorSample], now: Double) -> (anchor: RelativeFloorAnchor?, reason: String) {
        let proposed = RelativeFloorAnchor(level: level, altitude: samples.last?.altitude ?? 0,
                                          elapsed: samples.first?.elapsed ?? now, floorHeight: height)
        let validation = relative(anchor: proposed, samples: samples, now: now)
        guard validation.level == level, let last = samples.last else { return (nil, validation.reason) }
        let ordered = samples.map(\.altitude).sorted()
        let reference = RelativeFloorAnchor(level: level, altitude: ordered[ordered.count / 2],
                                            elapsed: last.elapsed, floorHeight: height)
        return (reference, "Stable starting reference; confidence remains unvalidated")
    }

    /// Thin adapter over rc_floor_relative; every threshold and ordering rule lives in C++.
    public static func relative(anchor: RelativeFloorAnchor?, samples: [RelativeFloorSample], now: Double) -> FloorProbeResult {
        // Clamping keeps out-of-range Swift levels out of range for the engine instead of wrapping.
        let cAnchor = anchor.map {
            rc_floor_anchor(level: Int32(clamping: $0.level), altitude: $0.altitude, elapsed: $0.elapsed, floor_height: $0.floorHeight)
        }
        var level: Int32 = 0
        let raw: rc_floor_reason
        if samples.count > 64 {
            // The engine rejects the count before reading; no buffer is exposed.
            raw = withAnchor(cAnchor) { rc_floor_relative($0, nil, samples.count, now, &level) }
        } else {
            let buffer = samples.map { rc_floor_sample(altitude: $0.altitude, elapsed: $0.elapsed) }
            raw = buffer.withUnsafeBufferPointer { s in
                withAnchor(cAnchor) { rc_floor_relative($0, s.baseAddress, s.count, now, &level) }
            }
        }
        let code = raw.rawValue
        let candidate = code == FloorProbeReason.candidate.rawValue
        return FloorProbeResult(level: candidate ? Int(level) : nil, reason: FloorProbeReason.message(for: code))
    }

    private static func withAnchor<T>(_ anchor: rc_floor_anchor?, _ body: (UnsafePointer<rc_floor_anchor>?) -> T) -> T {
        guard let anchor else { return body(nil) }
        return withUnsafePointer(to: anchor) { body($0) }
    }
}
