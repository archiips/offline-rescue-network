import XCTest
@testable import RescueDemoState

final class FloorCalibrationTests: XCTestCase {
    func testCalibrationRequiresStableRecentWindow() {
        let moving = [RelativeFloorSample(altitude: 100, elapsed: 8), .init(altitude: 101, elapsed: 9), .init(altitude: 102, elapsed: 10)]
        XCTAssertNil(FloorProbe.calibrate(level: 0, height: 3.4, samples: moving, now: 10).anchor)
        XCTAssertNil(FloorProbe.calibrate(level: 0, height: 3.4, samples: [moving[0]], now: 10).anchor)
        let stable = [RelativeFloorSample(altitude: 100, elapsed: 8), .init(altitude: 100, elapsed: 9), .init(altitude: 100, elapsed: 10)]
        XCTAssertNil(FloorProbe.calibrate(level: 0, height: 3.4, samples: stable, now: 21).anchor)
        XCTAssertNil(FloorProbe.calibrate(level: 0, height: .nan, samples: stable, now: 10).anchor)
        XCTAssertNil(FloorProbe.calibrate(level: 201, height: 3.4, samples: stable, now: 10).anchor)
    }
    func testMedianCalibrationBeginsAtLatestSampleAndSubtractsItsReference() throws {
        let samples = [RelativeFloorSample(altitude: 100.02, elapsed: 8), .init(altitude: 100, elapsed: 9), .init(altitude: 100.01, elapsed: 10)]
        let anchor = try XCTUnwrap(FloorProbe.calibrate(level: 4, height: 3.4, samples: samples, now: 10).anchor)
        XCTAssertEqual(anchor.altitude, 100.01)
        XCTAssertEqual(anchor.elapsed, 10)
        let later = [RelativeFloorSample(altitude: 103.4, elapsed: 11), .init(altitude: 103.41, elapsed: 12), .init(altitude: 103.42, elapsed: 13)]
        XCTAssertEqual(FloorProbe.relative(anchor: anchor, samples: later, now: 13).level, 5)
    }
}
