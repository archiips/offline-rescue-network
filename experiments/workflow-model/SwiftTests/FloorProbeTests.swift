import Testing
@testable import RescueDemoState

// Behavioral mirror of tests/floor_probe_tests.cpp through the Swift wrapper and real C++ engine.
// Synthetic deterministic fixtures only; these prove estimator logic, not physical floor accuracy.

/// Level 2 at session altitude 1 m, 3 m floors, anchored at t=100; evaluated at t=200.
private func anchor(_ level: Int = 2, _ altitude: Double = 1, _ elapsed: Double = 100, _ height: Double = 3) -> RelativeFloorAnchor {
    RelativeFloorAnchor(level: level, altitude: altitude, elapsed: elapsed, floorHeight: height)
}

private func window(_ altitudes: [Double], last: Double = 199, step: Double = 2) -> [RelativeFloorSample] {
    let first = last - step * Double(altitudes.count - 1)
    return altitudes.enumerated().map { RelativeFloorSample(altitude: $1, elapsed: first + step * Double($0)) }
}

private func samples(_ pairs: [(Double, Double)]) -> [RelativeFloorSample] {
    pairs.map { RelativeFloorSample(altitude: $0.0, elapsed: $0.1) }
}

private func probe(_ a: RelativeFloorAnchor?, _ s: [RelativeFloorSample], now: Double = 200) -> FloorProbeResult {
    FloorProbe.relative(anchor: a, samples: s, now: now)
}

private func expectCandidate(_ a: RelativeFloorAnchor, _ s: [RelativeFloorSample], _ level: Int, now: Double = 200,
                             sourceLocation: SourceLocation = #_sourceLocation) {
    let result = probe(a, s, now: now)
    #expect(result.level == level, sourceLocation: sourceLocation)
    #expect(result.reason == FloorProbeReason.candidate.message, sourceLocation: sourceLocation)
}

private func expectUnknown(_ a: RelativeFloorAnchor?, _ s: [RelativeFloorSample], _ reason: FloorProbeReason, now: Double = 200,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    let result = probe(a, s, now: now)
    #expect(result.level == nil, sourceLocation: sourceLocation)
    #expect(result.reason == reason.message, sourceLocation: sourceLocation)
}

@Test func floorProbeCandidatesAreAnchorRelative() {
    expectCandidate(anchor(), window([7, 7, 7]), 4)
    expectCandidate(anchor(), window([-5, -5, -5]), 0)
    expectCandidate(anchor(0, 0), window([-3, -3, -3]), -1)
    expectCandidate(anchor(), window([1, 1, 1]), 2)
    // Raw session altitude 56 would be ~18 floors from the altimeter baseline; only the anchor matters.
    expectCandidate(anchor(2, 50), window([56, 56, 56]), 4)
    expectCandidate(anchor(), window([6.9, 7.1, 7]), 4)
    expectCandidate(anchor(), window([7.3, 7.3, 7.3]), 4)
    expectCandidate(anchor(5, 0, 100, 4), window([-8, -8, -8]), 3)
}

@Test func floorProbeInclusiveBoundaries() {
    expectCandidate(anchor(2, 1, 100), window([7, 7, 7], last: 699), 4, now: 700)
    expectUnknown(anchor(2, 1, 100), window([7, 7, 7], last: 699), .staleAnchor, now: 700.5)
    expectCandidate(anchor(), window([7, 7, 7], last: 194), 4)
    expectUnknown(anchor(), window([7, 7, 7], last: 194.5, step: 2.5), .staleSamples)
    expectUnknown(anchor(), window([7, 7, 7], last: 189, step: 1), .staleSamples)
    expectCandidate(anchor(), window([7, 7, 7], step: 1), 4)
    expectUnknown(anchor(), window([7, 7, 7], step: 0.75), .shortWindow)
    expectCandidate(anchor(0, 0, 100, 2.5), window([0, 0.35, 0]), 0)
    expectUnknown(anchor(0, 0, 100, 2.5), window([0, 0.36, 0]), .noisy)
    expectCandidate(anchor(0, 0, 100, 2.5), window([3, 3, 3]), 1)
    expectCandidate(anchor(0, 0, 100, 2.5), window([2, 2, 2]), 1)
    expectCandidate(anchor(0, 0, 100, 2.5), window([-3, -3, -3]), -1)
    expectUnknown(anchor(0, 0, 100, 2.5), window([3.01, 3.01, 3.01]), .transition)
    expectUnknown(anchor(0, 0, 100, 2.5), window([1.25, 1.25, 1.25]), .transition)
    expectCandidate(anchor(0, 0, 100, 2), window([2, 2, 2]), 1)
    expectCandidate(anchor(0, 0, 100, 8), window([8, 8, 8]), 1)
    expectUnknown(anchor(0, 0, 100, 1.999), window([2, 2, 2]), .invalidHeight)
    expectUnknown(anchor(0, 0, 100, 8.001), window([8, 8, 8]), .invalidHeight)
    expectCandidate(anchor(-20, 1), window([1, 1, 1]), -20)
    expectCandidate(anchor(200, 1), window([1, 1, 1]), 200)
    expectUnknown(anchor(-21, 1), window([1, 1, 1]), .invalidLevel)
    expectUnknown(anchor(201, 1), window([1, 1, 1]), .invalidLevel)
    expectUnknown(anchor(200, 1), window([4, 4, 4]), .outOfRange)
    expectUnknown(anchor(-20, 1), window([-2, -2, -2]), .outOfRange)
    expectCandidate(anchor(), window([7, 7, 7]), 4)
    expectUnknown(anchor(), window([7, 7]), .tooFew)
    expectUnknown(anchor(), [], .tooFew)
    expectCandidate(anchor(), window(Array(repeating: 7, count: 64), step: 0.125), 4)
    expectUnknown(anchor(), window(Array(repeating: 7, count: 65), step: 0.125), .tooMany)
    expectCandidate(anchor(0, 10000, 100, 2), window([10000, 10000, 10000]), 0)
    expectCandidate(anchor(), window([7, 7, 7], last: 200), 4)
    expectCandidate(anchor(2, 1, 195), window([7, 7, 7]), 4)
    expectUnknown(anchor(2, 1, 200), window([7, 7, 7], last: 200, step: 0), .unordered)
}

@Test func floorProbeRejectsUnsafeOrTransitionalInput() {
    expectUnknown(nil, window([7, 7, 7]), .noAnchor)
    expectUnknown(nil, [], .noAnchor)
    expectUnknown(anchor(2, 1, 200.5), window([7, 7, 7]), .future)
    expectUnknown(anchor(), window([7, 7, 7], last: 200.5), .future)
    expectUnknown(anchor(2, 1, 196), window([7, 7, 7]), .anchorAfterSample)
    expectUnknown(anchor(), samples([(7, 195), (7, 199), (7, 197)]), .unordered)
    expectUnknown(anchor(), samples([(7, 195), (7, 197), (7, 197)]), .unordered)
    expectUnknown(anchor(), window([7, 7.5, 7]), .noisy)
    expectUnknown(anchor(), window([5.5, 6.2, 7]), .noisy)
    expectUnknown(anchor(), window([5.5, 5.5, 5.5]), .transition)
    expectUnknown(anchor(), window([7, 7, 7]), .staleAnchor, now: 800)
    for bad in [Double.nan, .infinity, -.infinity, 10000.5, -10001] {
        expectUnknown(anchor(0, bad), window([7, 7, 7]), .invalidInput)
        expectUnknown(anchor(), window([7, bad, 7]), .invalidInput)
    }
    for bad in [Double.nan, .infinity, -.infinity, -1] {
        expectUnknown(anchor(2, 1, bad), window([7, 7, 7]), .invalidInput)
        expectUnknown(anchor(), samples([(7, 195), (7, bad), (7, 199)]), .invalidInput)
        expectUnknown(anchor(), window([7, 7, 7]), .invalidInput, now: bad)
        expectUnknown(anchor(2, 1, 100, bad), window([7, 7, 7]), .invalidHeight)
    }
    expectUnknown(anchor(0, -10000, 100, 2), window([10000, 10000, 10000]), .outOfRange)
    expectUnknown(anchor(2, 1, 0), window([7, 7, 7]), .staleAnchor, now: .greatestFiniteMagnitude)
    expectUnknown(anchor(2, 1, .greatestFiniteMagnitude), window([7, 7, 7]), .future)
    expectCandidate(anchor(2, 1, 1e15), samples([(7, 1e15 + 2), (7, 1e15 + 4), (7, 1e15 + 6)]), 4, now: 1e15 + 6)
    // Swift Int beyond C int must not wrap into a valid level.
    expectUnknown(anchor(Int.max), window([7, 7, 7]), .invalidLevel)
    expectUnknown(anchor(Int.min), window([7, 7, 7]), .invalidLevel)
    expectUnknown(anchor(Int(Int32.max) + 3), window([7, 7, 7]), .invalidLevel)
}

@Test func floorProbeOversizedInputNeverReachesEngineMemory() {
    let huge = Array(repeating: RelativeFloorSample(altitude: 7, elapsed: 199), count: 10_000)
    expectUnknown(anchor(), huge, .tooMany)
    expectUnknown(nil, huge, .noAnchor)
}

@Test func floorProbeReasonsStateUnknownOrUnvalidated() {
    for reason in FloorProbeReason.allCases {
        if reason == .candidate {
            #expect(reason.message.contains("Unvalidated") && reason.message.contains("anchor-relative"))
        } else {
            #expect(reason.message.hasPrefix("Unknown: "))
        }
    }
    #expect(Set(FloorProbeReason.allCases.map(\.message)).count == FloorProbeReason.allCases.count)
    #expect(FloorProbeReason.message(for: 999).hasPrefix("Unknown: "))
}
