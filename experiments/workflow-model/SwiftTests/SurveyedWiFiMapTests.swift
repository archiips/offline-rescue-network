import Foundation
import Testing
@testable import RescueDemoState

private func survey(_ minimum: Int = 2, _ maximum: Int = 2, campus: String = "Synthetic campus", building: String = "Test building", bssid: String = "02:00:00:00:00:01", surveyedAt: Int64 = 100, expiresAt: Int64 = 200) -> SurveyedWiFiMap.Entry {
    .init(campus: campus, building: building, provenance: "Synthetic handset coverage survey", surveyedAt: surveyedAt, expiresAt: expiresAt, bssid: bssid, minimumLevel: minimum, maximumLevel: maximum)
}

@Test func surveyedWiFiMapMatchesExactContextAndRetainsCaptureIdentity() throws {
    let map = try SurveyedWiFiMap(entries: [survey(2, 3)])
    let observation = try #require(ConnectedWiFiObservation(ssid: "same-network", bssid: "02:00:00:00:00:01", capturedAt: 99))
    let evidence = try #require(map.evidence(observation: observation, campus: "Synthetic campus", building: "Test building", wallTime: 150, elapsed: 100))
    #expect(evidence.minimumLevel == 2 && evidence.maximumLevel == 3)
    #expect(evidence.sampledAt == 99)
    #expect(evidence.observation == observation.id)
    #expect(map.evidence(observation: observation, campus: "Synthetic campus", building: "Test building", wallTime: 151, elapsed: 101)?.observation == evidence.observation)
    #expect(try SurveyedWiFiMap.decode(map.encoded()).entries == map.entries)
}

@Test func surveyedWiFiMapMissingOrExpiredEvidenceStaysMissing() throws {
    let map = try SurveyedWiFiMap(entries: [survey()])
    let observation = try #require(ConnectedWiFiObservation(ssid: "same-network", bssid: "02:00:00:00:00:01", capturedAt: 99))
    let other = try #require(ConnectedWiFiObservation(ssid: "same-network", bssid: "02:00:00:00:00:02", capturedAt: 99))
    #expect(map.evidence(observation: other, campus: "Synthetic campus", building: "Test building", wallTime: 150, elapsed: 100) == nil)
    #expect(map.evidence(observation: observation, campus: "Other campus", building: "Test building", wallTime: 150, elapsed: 100) == nil)
    #expect(map.evidence(observation: observation, campus: "Synthetic campus", building: "Other building", wallTime: 150, elapsed: 100) == nil)
    for (wall, elapsed): (Int64, Double) in [(99,100), (100,101), (200,100), (150,110), (150,98), (150,.nan)] {
        #expect(map.evidence(observation: observation, campus: "Synthetic campus", building: "Test building", wallTime: wall, elapsed: elapsed) == nil)
    }
}

@Test func surveyedWiFiMapRejectsInvalidAndConflictingReferences() throws {
    for entry in [survey(-21), survey(201), survey(3,2), survey(campus: ""), survey(building: "bad\nname"), survey(bssid: "invalid"), survey(bssid: "02:00:00:00:00:AA"), survey(campus: String(repeating: "a", count: 129)), survey(surveyedAt: -1), survey(surveyedAt: 200, expiresAt: 200)] {
        #expect(throws: (any Error).self) { try SurveyedWiFiMap(entries: [entry]) }
    }
    #expect(throws: (any Error).self) { try SurveyedWiFiMap(entries: [survey(), survey(3,3)]) }
    #expect(throws: (any Error).self) { try SurveyedWiFiMap(entries: Array(repeating: survey(), count: 129)) }
    #expect(throws: (any Error).self) { try SurveyedWiFiMap.decode(Data(repeating: 32, count: 65537)) }
    let large = (0..<128).map { index in
        SurveyedWiFiMap.Entry(campus: String(repeating: "a", count: 128), building: String(repeating: "b", count: 128),
            provenance: String(repeating: "p", count: 512), surveyedAt: 100, expiresAt: 200,
            bssid: String(format: "02:00:00:00:00:%02x", index), minimumLevel: 2, maximumLevel: 2)
    }
    #expect(throws: (any Error).self) { try SurveyedWiFiMap(entries: large) }

    // Identical AP identifiers in distinct explicit contexts do not supply a context guess.
    #expect(try SurveyedWiFiMap(entries: [survey(), survey(3,3,campus: "Other campus")]).entries.count == 2)
}

@Test func surveyedWiFiMapStrictSchemaRejectsUnknownAndDuplicateKeys() throws {
    let data = try SurveyedWiFiMap(entries: [survey()]).encoded()
    var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["version"] = 2
    #expect(throws: (any Error).self) { try SurveyedWiFiMap.decode(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) }
    #expect(throws: (any Error).self) { try JSONDecoder().decode(SurveyedWiFiMap.self, from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) }
    object["version"] = 1; object["unexpected"] = true
    #expect(throws: (any Error).self) { try SurveyedWiFiMap.decode(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) }
    let text = String(decoding: data, as: UTF8.self)
    let duplicate = text.replacingOccurrences(of: "\"version\":1", with: "\"version\":1,\"version\":1")
    #expect(throws: (any Error).self) { try SurveyedWiFiMap.decode(Data(duplicate.utf8)) }
}
