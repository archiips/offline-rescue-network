import Foundation
import Combine
import CoreLocation
import NetworkExtension
import RescueDemoState

/// Explicit local-only connected-network capture. Never scans APs or sends their identifiers.
@MainActor final class NativeWiFiResearch: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    let capture = ConnectedWiFiResearch()
    private var manager: CLLocationManager?
    private var pending = false
    func request() {
        #if RESCUE_NO_WIFI_INFO
        return
        #else
        guard !capture.busy, !pending else { return }
        pending = true
        if manager == nil {
            manager = CLLocationManager()
            manager?.delegate = self
        }
        authorize()
        #endif
    }
    func stop() { pending = false; capture.clear() }
    private func authorize() {
        guard pending, let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            pending = false
            let precise = manager.accuracyAuthorization == .fullAccuracy
            capture.capture(authorized: precise) { completion in
                NEHotspotNetwork.fetchCurrent { network in completion(network?.ssid, network?.bssid) }
            }
        default:
            pending = false
            capture.capture(authorized: false) { _ in }
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === self.manager else { return }
        authorize()
    }
}
