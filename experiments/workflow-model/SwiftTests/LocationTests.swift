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
        let original = try LocationReport(reported: "Sample building", floor: "Floor 3", observation: fix).encoded()
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
    }
}
