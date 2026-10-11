import Foundation
import Testing
@testable import RescueDemoState

@Test func liveResearchGraphDisagreementIsUnknownAndNeverShared() {
    let a = ResearchFloorReading(level: 2, source: .appleFloor, sampledAt: 99)
    let b = ResearchFloorReading(level: 3, source: .relativeAltitude, sampledAt: 99)
    #expect(LiveResearchGraph.sharingReading(local: [a,b], now: 100) == nil)
    #expect(LiveResearchGraph.evaluate(local: [a,b], peer: nil, now: 100).reason == .conflict)
}
@Test func liveResearchGraphExpiresLocalSensorAndPreservesOriginalIdentity() {
    let a = ResearchFloorReading(level: 2, source: .appleFloor, sampledAt: 99)
    #expect(LiveResearchGraph.sharingReading(local: [a], now: 100)?.id == a.id)
    #expect(LiveResearchGraph.evaluate(local: [a], peer: nil, now: 100).level == 2)
    #expect(LiveResearchGraph.sharingReading(local: [a], now: 110) == nil)
    #expect(LiveResearchGraph.evaluate(local: [a], peer: nil, now: 110).reason == .noReference)
}
@Test func liveResearchGraphContactDoesNotTransferFloor() {
    let peer = ResearchPeerObservation(level: 8, source: .appleFloor, id: UUID(), fingerprint: "test", receivedAt: 99, ageAtReceipt: 1)
    #expect(LiveResearchGraph.evaluate(local: [], peer: peer, now: 100).reason == .noReference)
    let local = ResearchFloorReading(level: 2, source: .appleFloor, sampledAt: 99)
    #expect(LiveResearchGraph.evaluate(local: [local], peer: peer, now: 100).level == 2)
}

@Test func liveResearchSurveyedWiFiIsLocalBoundedAndCannotMaskConflict() throws {
    let entry = SurveyedWiFiMap.Entry(campus: "Test campus", building: "A", provenance: "Synthetic handset coverage",
        surveyedAt: 100, expiresAt: 300, bssid: "02:00:00:00:00:01", minimumLevel: 2, maximumLevel: 2)
    let map = try SurveyedWiFiMap(entries: [entry])
    let capture = try #require(ConnectedWiFiObservation(ssid: "test", bssid: entry.bssid, capturedAt: 99))
    let evidence = try #require(map.evidence(observation: capture, campus: "Test campus", building: "A", wallTime: 200, elapsed: 100))
    #expect(LiveResearchGraph.evaluate(local: [], peer: nil, surveyedWiFi: evidence, now: 100).level == 2)
    let sensor = ResearchFloorReading(level: 3, source: .appleFloor, sampledAt: 99)
    #expect(LiveResearchGraph.evaluate(local: [sensor], peer: nil, surveyedWiFi: evidence, now: 100).reason == .conflict)
    #expect(LiveResearchGraph.evaluate(local: [], peer: nil, surveyedWiFi: evidence, now: 110).reason == .noReference)
    #expect(LiveResearchGraph.sharingReading(local: [], now: 100) == nil)
    let ambiguous = try SurveyedWiFiMap(entries: [.init(campus: "Test campus", building: "A", provenance: "Synthetic cross-floor coverage", surveyedAt: 100, expiresAt: 300, bssid: entry.bssid, minimumLevel: 2, maximumLevel: 3)])
    let interval = try #require(ambiguous.evidence(observation: capture, campus: "Test campus", building: "A", wallTime: 200, elapsed: 100))
    #expect(LiveResearchGraph.evaluate(local: [], peer: nil, surveyedWiFi: interval, now: 100).reason == .ambiguous)
}
