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
