import Foundation
import Combine
import CoreLocation
import CoreMotion
import RescueDemoState

@MainActor final class NativeFloorResearch: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var synthetic = false
    @Published private(set) var fixture = 0
    @Published private(set) var running = false
    @Published private(set) var referenceReady = false
    @Published private(set) var actionStatus = ""
    @Published private(set) var status = "Stopped. Optional foreground research; nothing is sent or saved."
    @Published private(set) var appleLevel: Int?
    @Published private(set) var appleObservedAt: Date?
    @Published private(set) var appleStatus = "Unknown · no recent Apple floor observation."
    @Published private(set) var relative = FloorProbe.relative(anchor: nil, samples: [], now: 0)
    @Published private(set) var relativeObservedAt: Date?
    @Published private(set) var latestAltitude: Double?
    @Published private(set) var anchor: RelativeFloorAnchor?
    private var samples: [RelativeFloorSample] = []
    private var location: CLLocationManager?
    private var altimeter: CMAltimeter?
    private var clock: Task<Void, Never>?
    private var generation = UUID()
    private var began = 0.0
    private var altitudeStatus = "Unknown · no recent altitude readings."
    private var elapsed: Double { ProcessInfo.processInfo.systemUptime - began }

    func changeSource(synthetic: Bool) {
        stop()
        self.synthetic = synthetic
        fixture = 0
        if synthetic { applyFixture(0) }
    }

    func start() {
        guard !synthetic else { return }
        stop()
        running = true
        began = ProcessInfo.processInfo.systemUptime
        let run = generation
        let next = CLLocationManager()
        location = next
        next.delegate = self
        next.desiredAccuracy = kCLLocationAccuracyBest
        authorize(next)
        if CMAltimeter.isRelativeAltitudeAvailable() {
            switch CMAltimeter.authorizationStatus() {
            case .denied, .restricted:
                altitudeStatus = "Unknown · motion permission unavailable."
            default:
                let meter = CMAltimeter()
                altimeter = meter
                altitudeStatus = "Waiting for relative-altitude readings."
                meter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                    let value = data?.relativeAltitude.doubleValue
                    let uptime = data?.timestamp
                    let failed = error != nil
                    MainActor.assumeIsolated {
                        guard let self, self.running, !self.synthetic, self.generation == run else { return }
                        if failed {
                            self.altimeter?.stopRelativeAltitudeUpdates(); self.altimeter = nil
                            self.samples = []; self.anchor = nil; self.latestAltitude = nil
                            self.altitudeStatus = "Unknown · altitude sensor unavailable; restart to retry."
                        } else if let value, let uptime {
                            self.acceptAltitude(value, at: uptime - self.began)
                        }
                        self.refresh()
                    }
                }
            }
        } else {
            altitudeStatus = "Unknown · relative altitude unsupported on this device or Simulator."
        }
        status = "Foreground sensor research running. No observations are sent or saved."
        clock = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.running, self.generation == run else { return }
                self.refresh()
            }
        }
        refresh()
    }

    func stop() {
        generation = UUID()
        location?.delegate = nil; location?.stopUpdatingLocation(); location = nil
        altimeter?.stopRelativeAltitudeUpdates(); altimeter = nil
        clock?.cancel(); clock = nil; running = false; fixture = 0
        referenceReady = false; actionStatus = ""
        samples = []; anchor = nil; latestAltitude = nil
        appleLevel = nil; appleObservedAt = nil
        appleStatus = "Unknown · research stopped; no current floor observation."
        relative = FloorProbe.relative(anchor: nil, samples: [], now: 0)
        relativeObservedAt = nil
        status = "Stopped. Nothing was sent or saved; restart requires a new starting reference."
    }

    private func authorize(_ manager: CLLocationManager) {
        guard manager === location, running, !synthetic else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            appleStatus = "Unknown · waiting for an Apple-provided floor; coverage is not assumed."
        case .denied, .restricted:
            appleLevel = nil; appleObservedAt = nil
            appleStatus = "Unknown · location permission unavailable. Relative altitude is separate."
        @unknown default:
            appleLevel = nil; appleObservedAt = nil
            appleStatus = "Unknown · location authorization unavailable."
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorize(manager) }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations fixes: [CLLocation]) {
        guard manager === location, running, !synthetic else { return }
        // Only the newest fix can describe current provider knowledge. Do not reuse an older floor
        // when the newest fix explicitly lacks one.
        guard let fix = fixes.max(by: { $0.timestamp < $1.timestamp }) else { return }
        let age = Date().timeIntervalSince(fix.timestamp)
        guard age.isFinite, age >= 0, age <= 10, fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0,
              let floor = fix.floor, (-20...200).contains(floor.level) else {
            appleLevel = nil; appleObservedAt = nil
            appleStatus = "Unknown · latest location has no fresh valid floor information."
            return
        }
        appleLevel = floor.level; appleObservedAt = fix.timestamp
        appleStatus = "Apple-provided logical level · accuracy/confidence unvalidated here."
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === location, running, !synthetic else { return }
        appleLevel = nil; appleObservedAt = nil
        appleStatus = "Unknown · location sensor unavailable. Relative altitude is separate."
    }

    private func acceptAltitude(_ value: Double, at time: Double) {
        let now = elapsed
        guard value.isFinite, abs(value) <= 10_000, time.isFinite, time >= 0, time <= now,
              now - time <= 10, samples.last.map({ time > $0.elapsed }) ?? true else {
            samples = []; latestAltitude = nil
            altitudeStatus = "Unknown · invalid or out-of-order altitude reading."
            return
        }
        samples.append(RelativeFloorSample(altitude: value, elapsed: time))
        samples = Array(samples.filter { now - $0.elapsed <= 10 }.suffix(64))
        latestAltitude = value
        altitudeStatus = ""
    }
    func setAnchor(level: Int?, height: Double?) {
        guard running, !synthetic else { return }
        guard let level, let height else {
            actionStatus = "Enter a known starting logical level and measured floor spacing. Existing reference retained."
            return
        }
        let calibration = FloorProbe.calibrate(level: level, height: height, samples: samples, now: elapsed)
        guard let reference = calibration.anchor, let last = samples.last else {
            actionStatus = "Reference not changed. " + calibration.reason
            return
        }
        anchor = reference
        samples = [last] // inference starts at the calibrated latest event
        actionStatus = "Reference set from a stable window. Wait for fresh stable readings; confidence remains unvalidated."
        refresh()
    }
    func clearAnchor() {
        guard !synthetic else { return }
        anchor = nil
        actionStatus = "Starting reference cleared. Relative floor stays Unknown until recalibrated."
        refresh()
    }

    private func refresh() {
        guard running, !synthetic else { return }
        let now = elapsed
        samples.removeAll { now - $0.elapsed > 10 }
        latestAltitude = samples.last?.altitude
        relative = FloorProbe.relative(anchor: anchor, samples: samples, now: now)
        relativeObservedAt = relative.level == nil ? nil : samples.last.map { Date().addingTimeInterval($0.elapsed - now) }
        referenceReady = FloorProbe.calibrate(level: 0, height: 3.4, samples: samples, now: now).anchor != nil
        if samples.isEmpty {
            status = "Foreground research · " + (altitudeStatus.isEmpty ? "Unknown · no altitude readings in the last 10 seconds." : altitudeStatus)
        } else {
            status = "Foreground research · receiving altitude readings. " + (anchor == nil ? "Starting reference not set." : "Starting reference set; see current estimate below.")
        }
        if let date = appleObservedAt, !(0...10).contains(Date().timeIntervalSince(date)) {
            appleLevel = nil; appleObservedAt = nil
            appleStatus = "Unknown · Apple floor observation expired after 10 seconds."
        }
    }

    func applyFixture(_ index: Int) {
        guard synthetic else { return }
        fixture = index
        appleLevel = nil; appleObservedAt = nil
        appleStatus = "Unknown · synthetic fixture does not simulate Apple venue coverage."
        let baseline = RelativeFloorAnchor(level: 0, altitude: 100, elapsed: 90, floorHeight: 3.4)
        anchor = index == 0 ? nil : baseline
        let values: [Double]
        switch index {
        case 1: values = [103.38, 103.4, 103.42]
        case 2: values = [101.69, 101.7, 101.71]
        case 3: values = [102.8, 103.4, 104]
        default: values = [100, 100, 100]
        }
        let end = index == 4 ? 94.0 : 100.0
        // Stale fixture must be older than the engine's 10-second freshness limit.
        let times = index == 4 ? [86.0, 87.0, 88.0] : [end - 2, end - 1, end]
        let fixtureAnchor = index == 4 ? RelativeFloorAnchor(level: 0, altitude: 100, elapsed: 80, floorHeight: 3.4) : anchor
        anchor = fixtureAnchor
        samples = zip(values, times).map { RelativeFloorSample(altitude: $0.0, elapsed: $0.1) }
        relative = FloorProbe.relative(anchor: anchor, samples: samples, now: 100)
        latestAltitude = nil; relativeObservedAt = nil
        status = "SYNTHETIC · no sensors, no observations saved or transmitted."
    }
}
