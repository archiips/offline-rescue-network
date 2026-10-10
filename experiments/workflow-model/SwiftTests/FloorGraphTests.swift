import Testing
@testable import RescueDemoState

@Test func cooperativeReplayDoesNotPromoteContactToFloor() {
    let replay = CooperativeFloorReplay.scenarios[0]
    #expect(replay.results[.sensorOnly]?.level == nil)
    #expect(replay.results[.combined]?.level == nil)
    #expect(replay.results[.combined]?.reason == .noReference)
}

@Test func cooperativeReplayShowsContributionsAndConflict() {
    let anchor = CooperativeFloorReplay.scenarios[1]
    #expect(anchor.results[.sensorOnly]?.level == nil)
    #expect(anchor.results[.wifi]?.level == 2)
    #expect(anchor.results[.peer]?.level == nil)
    #expect(anchor.results[.combined]?.level == 2)
    let peer = CooperativeFloorReplay.scenarios[2]
    #expect(peer.results[.sensorOnly]?.level == nil)
    #expect(peer.results[.wifi]?.level == nil)
    #expect(peer.results[.peer]?.level == 3)
    #expect(peer.results[.combined]?.level == 3)
    let conflict = CooperativeFloorReplay.scenarios[3]
    #expect(conflict.results[.sensorOnly]?.level == 2)
    #expect(conflict.results[.wifi]?.reason == .conflict)
    #expect(conflict.results[.combined]?.reason == .conflict)
}

@Test func cooperativeGraphDeduplicatesOriginalsAndExpiresEvidence() {
    let obs = GraphFloorObservation(node: 1, origin: 20, observation: 100, source: .knownReference,
                                   minimumLevel: 2, maximumLevel: 2, elapsed: 99)
    let edge = GraphFloorEdge(from: 1, to: 2, kind: .relativeLevel, minimumDelta: 1, maximumDelta: 1, elapsed: 99)
    let a = FloorGraph.evaluate(nodes: [1, 2], edges: [edge], observations: [obs, obs], target: 2, now: 100)
    #expect(a.level == 3 && a.origins == 1)
    let b = FloorGraph.evaluate(nodes: [1, 2], edges: [edge], observations: [obs], target: 2, now: 110)
    #expect(b.reason == .noReference && b.skipped == 2)
}

@Test func cooperativeGraphRejectsUnsafeSwiftBounds() {
    let huge = Array(repeating: UInt64(1), count: 10000)
    #expect(FloorGraph.evaluate(nodes: huge, edges: [], observations: [], target: 1, now: 100).reason == .limit)
    let obs = GraphFloorObservation(node: 1, origin: 2, observation: 3, source: .sensor,
                                   minimumLevel: Int.max, maximumLevel: Int.max, elapsed: 99)
    #expect(FloorGraph.evaluate(nodes: [1], edges: [], observations: [obs], target: 1, now: 100).reason == .invalid)
}

@Test func cooperativeGraphNeverCountsForwardedOrDerivedVotes() {
    let a = GraphFloorObservation(node: 1, origin: 2, observation: 3, source: .sensor,
                                 minimumLevel: 2, maximumLevel: 2, elapsed: 99)
    let changed = GraphFloorObservation(node: 1, origin: 2, observation: 3, source: .sensor,
                                       minimumLevel: 3, maximumLevel: 3, elapsed: 99)
    #expect(FloorGraph.evaluate(nodes: [1], edges: [], observations: [a, changed], target: 1, now: 100).reason == .conflict)
    #expect(CooperativeFloorReplay.scenarios[4].results[.combined]?.origins == 1)
    #expect(CooperativeFloorReplay.scenarios[5].results[.combined]?.reason == .ambiguous)
    #expect(CooperativeFloorReplay.scenarios[6].results[.combined]?.reason == .noReference)
}

@Test func cooperativeGraphKeepsUnconnectedReferencesAndInputOrderSeparate() {
    let local = GraphFloorObservation(node: 1, origin: 10, observation: 100, source: .sensor,
                                     minimumLevel: 2, maximumLevel: 2, elapsed: 99)
    let remote = GraphFloorObservation(node: 3, origin: 11, observation: 101, source: .knownReference,
                                      minimumLevel: 7, maximumLevel: 7, elapsed: 99)
    let edge = GraphFloorEdge(from: 1, to: 2, kind: .relativeLevel, minimumDelta: 1, maximumDelta: 1, elapsed: 99)
    let a = FloorGraph.evaluate(nodes: [1, 2, 3], edges: [edge], observations: [local, remote], target: 2, now: 100)
    let b = FloorGraph.evaluate(nodes: [3, 2, 1], edges: [edge], observations: [remote, local], target: 2, now: 100)
    #expect(a.level == 3 && a.origins == 1)
    #expect(b.level == a.level && b.origins == a.origins)
    let contact = GraphFloorEdge(from: 3, to: 2, kind: .contact, elapsed: 99)
    #expect(FloorGraph.evaluate(nodes: [1, 2, 3], edges: [contact], observations: [remote], target: 2, now: 100).reason == .noReference)
}

@Test func cooperativeGraphRejectsNegativeReplayTimes() {
    let negative = GraphFloorObservation(node: 1, origin: 2, observation: 3, source: .sensor,
                                        minimumLevel: 2, maximumLevel: 2, elapsed: -1)
    #expect(FloorGraph.evaluate(nodes: [1], edges: [], observations: [negative], target: 1, now: 0).reason == .invalid)
    #expect(FloorGraph.evaluate(nodes: [1], edges: [], observations: [], target: 1, now: -1).reason == .invalid)
    let edge = GraphFloorEdge(from: 1, to: 2, kind: .contact, elapsed: -1)
    #expect(FloorGraph.evaluate(nodes: [1, 2], edges: [edge], observations: [], target: 1, now: 0).reason == .invalid)
}

@Test func cooperativeAblationExcludesManualAndRemoteWiFiFromSensorBaseline() {
    let manual = GraphFloorObservation(node: 2, origin: 10, observation: 100, source: .knownReference,
                                      minimumLevel: 2, maximumLevel: 2, elapsed: 99)
    let local = CooperativeFloorScenario(title: "local manual", explanation: "", nodes: [1, 2], edges: [], observations: [manual], target: 2)
    #expect(local.results[.sensorOnly]?.reason == .noReference)
    #expect(local.results[.wifi]?.reason == .noReference)
    let remote = GraphFloorObservation(node: 1, origin: 10, observation: 100, source: .surveyedWiFi,
                                      minimumLevel: 2, maximumLevel: 2, elapsed: 99)
    let edge = GraphFloorEdge(from: 1, to: 2, kind: .relativeLevel, minimumDelta: 1, maximumDelta: 1, elapsed: 99)
    let scenario = CooperativeFloorScenario(title: "remote Wi-Fi", explanation: "", nodes: [1, 2], edges: [edge], observations: [remote], target: 2)
    #expect(scenario.results[.sensorOnly]?.reason == .noReference)
    #expect(scenario.results[.wifi]?.reason == .noReference)
    #expect(scenario.results[.peer]?.reason == .noReference)
    #expect(scenario.results[.combined]?.level == 3)
}
