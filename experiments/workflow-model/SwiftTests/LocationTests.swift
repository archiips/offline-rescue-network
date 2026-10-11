import XCTest
@testable import RescueDemoState

final class LocationTests: XCTestCase {
    func testCaptureRejectsInvalidAndStaleFixes() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (lat, lon, accuracy, age) in [(91.0, 0.0, 5.0, 0.0), (0, 181, 5, 0), (.nan, 0, 5, 0), (0, 0, -1, 0), (0, 0, .infinity, 0), (0, 0, 5, 61), (0, 0, 5, -6)] {
            XCTAssertThrowsError(try DeviceObservation.capture(latitude: lat, longitude: lon, accuracy: accuracy, observedAt: now.addingTimeInterval(-age), approximate: false, now: now))
        }
        let fix = try DeviceObservation.capture(latitude: 37.3349, longitude: -122.009, accuracy: 200, observedAt: now.addingTimeInterval(-60), approximate: true, now: now)
        XCTAssertTrue(fix.approximate)
        XCTAssertEqual(fix.observedAt, now.addingTimeInterval(-60))
    }

    func testEstimatedFloorRemainsSeparateAndRetainsOriginalTime() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let estimate = try EstimatedFloorObservation.capture(level: 2, source: .combinedGraph, observedAt: now, context: "Synthetic building", now: now)
        var report = LocationReport(reported: "Sample building", floor: "Floor 3", estimatedFloor: estimate)
        XCTAssertEqual(report.title, "Sample building · Floor 3")
        let original = try report.encoded()
        report.floor = "Floor 4"
        let restored = LocationReport.display(try report.encoded())
        XCTAssertEqual(restored.floor, "Floor 4")
        XCTAssertEqual(restored.estimatedFloor, estimate)
        XCTAssertEqual(LocationReport.display(original).estimatedFloor?.level, 2)
        XCTAssertTrue(estimate.detail.contains("unvalidated"))
        XCTAssertTrue(estimate.detail.contains("not live"))
        let legacy = LocationReport.display(#"ORLOC1:{"floor":"Floor 3","reported":"Sample building"}"#)
        XCTAssertEqual(legacy.floor, "Floor 3")
        XCTAssertNil(legacy.estimatedFloor)
    }

    func testEstimatedFloorRejectsInvalidOrStaleCaptureAndMalformedHistory() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (level, age) in [(-21, 0.0), (201, 0), (2, 10.01), (2, -0.01)] {
            XCTAssertThrowsError(try EstimatedFloorObservation.capture(level: level, source: .appleFloor, observedAt: now.addingTimeInterval(-age), now: now))
        }
        XCTAssertThrowsError(try EstimatedFloorObservation.capture(level: 2, source: .appleFloor, observedAt: Date(timeIntervalSince1970: .infinity), now: now))
        XCTAssertThrowsError(try EstimatedFloorObservation.capture(level: 2, source: .appleFloor, observedAt: now, context: "bad\ncontext", now: now))
        XCTAssertThrowsError(try EstimatedFloorObservation.capture(level: 2, source: .appleFloor, observedAt: now, context: String(repeating: "a", count: 257), now: now))
        let malformed = #"ORLOC1:{"floor":"Floor 3","reported":"Sample building","estimatedFloor":{"level":201,"source":"appleFloor","observedAt":0}}"#
        XCTAssertEqual(LocationReport.display(malformed).reported, "Location report unavailable")
        let estimate = try EstimatedFloorObservation.capture(level: 2, source: .relativeAltitude, observedAt: now.addingTimeInterval(-10), now: now)
        XCTAssertEqual(estimate.observedAt, now.addingTimeInterval(-10))
        let bounded = try LocationReport(reported: String(repeating: "a", count: 512), floor: String(repeating: "f", count: 128), estimatedFloor: estimate).encoded()
        XCTAssertLessThanOrEqual(bounded.utf8.count, 1800)
        let escapedEstimate = try EstimatedFloorObservation.capture(level: 2, source: .combinedGraph, observedAt: now, context: String(repeating: "\"", count: 256), now: now)
        XCTAssertThrowsError(try LocationReport(reported: String(repeating: "\"", count: 512), floor: String(repeating: "\"", count: 128), estimatedFloor: escapedEstimate).encoded())
        let invalidEstimate = #"{"level":201,"source":"appleFloor","observedAt":0}"#
        XCTAssertThrowsError(try JSONDecoder().decode(EstimatedFloorObservation.self, from: Data(invalidEstimate.utf8)))

    }

    func testLegacyAndMalformedReportsNeverInventCoordinates() throws {
        XCTAssertEqual(LocationReport.display("Training Building A · Floor 3").reported, "Training Building A · Floor 3")
        XCTAssertNil(LocationReport.display("Training Building A · Floor 3").observation)
        XCTAssertEqual(LocationReport.display("ORLOC1:{broken}").reported, "Location report unavailable")
        XCTAssertThrowsError(try LocationReport(reported: String(repeating: "a", count: 2100), floor: "Floor 1").encoded())
    }

    func testSerializedReviewRetainsOriginalObservationAndReportedFloor() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fix = try DeviceObservation.capture(latitude: 37.3349, longitude: -122.009, accuracy: 15, observedAt: now, approximate: false, now: now)
        var draft = LocationReport(reported: "Sample building", floor: "Floor 3", observation: fix)
        let frozen = try draft.encoded()
        draft.floor = "Floor 4"
        draft.observation = nil
        let restored = LocationReport.display(frozen)
        XCTAssertEqual(restored.floor, "Floor 3")
        XCTAssertEqual(restored.observation?.latitude, 37.3349)
        XCTAssertEqual(restored.observation?.observedAt, now)
        XCTAssertEqual(LocationReport.display(try draft.encoded()).floor, "Floor 4")
    }
}

@MainActor final class LocationPersistenceTests: XCTestCase {
    func testCorrectionAndRestartKeepOriginalObservationInHistory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("session.sqlite")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fix = try DeviceObservation.capture(latitude: 37.3349, longitude: -122.009, accuracy: 15, observedAt: now, approximate: false, now: now)
        let estimate = try EstimatedFloorObservation.capture(level: 2, source: .surveyedWiFi, observedAt: now, context: "Synthetic route", now: now)
        let original = try LocationReport(reported: "Sample building", floor: "Floor 3", observation: fix, estimatedFloor: estimate).encoded()
        let correction = try LocationReport(reported: "Sample building", floor: "Floor 4").encoded()
        do {
            let demo = DemoController(storageURL: url)
            demo.perform(.sos, value: original)
            XCTAssertTrue(demo.error.isEmpty)
            demo.setConnected(false)
            demo.perform(.correction, value: correction)
            XCTAssertEqual(demo.snapshot?.responderState.reportedLocation, original)
        }
        let reopened = DemoController(storageURL: url)
        reopened.setConnected(true)
        XCTAssertEqual(reopened.snapshot?.responderState.reportedLocation, correction)
        let saved = try XCTUnwrap(reopened.snapshot?.responderState.messages.first { $0.kind == .request })
        XCTAssertEqual(LocationReport.display(saved.location).observation?.observedAt, now)
        XCTAssertEqual(LocationReport.display(saved.location).floor, "Floor 3")
        XCTAssertEqual(LocationReport.display(saved.location).estimatedFloor, estimate)
        XCTAssertNil(LocationReport.display(correction).estimatedFloor)
    }
}
