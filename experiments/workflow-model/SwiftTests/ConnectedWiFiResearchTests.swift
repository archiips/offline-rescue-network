import Foundation
import Testing
@testable import RescueDemoState

@Test func connectedWiFiRejectsInvalidIdentifiersAndTime() {
    #expect(ConnectedWiFiObservation(ssid: "eduroam", bssid: "02:AA:bb:00:01:02", capturedAt: 10)?.bssid == "02:aa:bb:00:01:02")
    for ssid in ["", String(repeating: "x", count: 33), "bad\nname"] {
        #expect(ConnectedWiFiObservation(ssid: ssid, bssid: "02:aa:bb:00:01:02", capturedAt: 10) == nil)
    }
    for mac in ["", "00:00:00:00:00:00", "ff:ff:ff:ff:ff:ff", "not-a-mac", "01:aa:bb:00:01:02"] {
        #expect(ConnectedWiFiObservation(ssid: "eduroam", bssid: mac, capturedAt: 10) == nil)
    }
    #expect(ConnectedWiFiObservation(ssid: "eduroam", bssid: "02:aa:bb:00:01:02", capturedAt: .nan) == nil)
}
@Test func connectedWiFiFreshnessDoesNotBecomeFloorEvidence() throws {
    let observation = try #require(ConnectedWiFiObservation(ssid: "eduroam", bssid: "02:aa:bb:00:01:02", capturedAt: 10))
    #expect(observation.isFresh(at: 20))
    #expect(!observation.isFresh(at: 20.001))
    #expect(!observation.isFresh(at: 9))
}
@MainActor @Test func connectedWiFiPermissionMissingNeverCallsProvider() {
    let capture = ConnectedWiFiResearch()
    var called = false
    capture.capture(authorized: false) { _ in called = true }
    #expect(!called && !capture.busy && capture.observation == nil)
}
@MainActor @Test func connectedWiFiClearFencesLateCallbacksAndNilClearsOldValue() async throws {
    let capture = ConnectedWiFiResearch()
    var pending: (@Sendable (String?, String?) -> Void)?
    capture.capture(authorized: true) { pending = $0 }
    capture.clear()
    pending?("eduroam", "02:aa:bb:00:01:02")
    try await Task.sleep(for: .milliseconds(20))
    #expect(capture.observation == nil && !capture.busy)
    capture.capture(authorized: true) { $0("eduroam", "02:aa:bb:00:01:02") }
    try await Task.sleep(for: .milliseconds(20))
    #expect(capture.observation != nil)
    capture.capture(authorized: true) { $0(nil, nil) }
    try await Task.sleep(for: .milliseconds(20))
    #expect(capture.observation == nil && !capture.busy)
}
@MainActor @Test func connectedWiFiTimeoutDiscardsLateProvider() async throws {
    let capture = ConnectedWiFiResearch(timeout: .milliseconds(10))
    var pending: (@Sendable (String?, String?) -> Void)?
    capture.capture(authorized: true) { pending = $0 }
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while capture.busy && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(!capture.busy && capture.observation == nil)
    pending?("eduroam", "02:aa:bb:00:01:02")
    try await Task.sleep(for: .milliseconds(20))
    #expect(capture.observation == nil)
}
