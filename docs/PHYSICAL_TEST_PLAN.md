# First physical test protocol

Prepared 2026-10-09. No physical tests have run. Use synthetic rescue content and consenting participants. Hardware availability and iPad model/OS remain unconfirmed; do not repeatedly request unavailable hardware. Public iPhone and responder iPad workflows remain required.

Use the [home session guide and local-only worksheets](testing/HOME_TEST.md) for installation and recording attempts. Templates contain no completed results.

## 1. Controlled location near home

Start in an accessible room or building near the user, before travelling to campus. Use two supported physical Apple devices with the signed app installed (deployment target iOS/iPadOS 18). Record actual model, OS, app commit, permissions and network configuration. Preserve existing histories; use coordinated fresh exercise identities if a separate test is needed.

- Establish a normal connected baseline: manually check complete public pairing fingerprints; send synthetic SOS, obtain destination device receipt, explicitly acknowledge and reply. Record each distinct state.
- Repeat on a personally controlled Wi-Fi access point with its WAN disconnected and cellular data unavailable on participating devices. Keep Wi-Fi enabled. Verify internet unavailability independently; do not disconnect or interfere with UW infrastructure. This tests local exchange without internet, not router-free radio.
- Separately test without a shared access point: leave infrastructure Wi-Fi networks and personal hotspots, retain Wi-Fi/Bluetooth radios enabled, disable cellular data, start foreground exchange on both devices and attempt Bonjour discovery/transfer. Record failure as well as success. No shared AP plus successful transfer supports a bounded router-free result; without interface diagnostics do not claim a particular radio path or physical range.
- Interrupt contact, queue a correction, stop/restart the apps, reconnect explicitly and verify recovery without duplicate requests. Test Local Network permission denied and background/lock; document stopped exchange rather than expecting background delivery.

Use three physical devices for a later actual relay trial: public, relay and responder. Sequential attended contacts can test store-and-forward but do not prove endpoints were outside direct radio range. A two-device test cannot establish a third-device relay path.

## 2. One Bothell building, repeated routes

Choose one building the user can routinely access, with known floor signage and safe stairs/elevator routes. Exact building remains unselected. Start with the existing sensor baseline, using one device; compare Apple logical floor and calibrated relative altitude against independently recorded signed levels and timestamps. Map logical ground level to building signage explicitly. Measure actual floor spacing rather than assume a campus constant.

Repeat stationary, stairs and elevator sessions on different days. Record no-floor/unsupported permission cases, calibration age, time to transition, wrong-floor and Unknown outputs. Avoid treating test labels entered by the observer as automatic estimates. Capture only consented research data; existing sample history is not encrypted at rest.

Then add at least two opted-in participating devices, including peers on adjacent floors, disconnected peers, contradictory references and stale/repeated evidence. Connectivity alone is not proximity or same-floor evidence. Connected-network collection needs its own permission/entitlement check; eduroam association alone supplies no building/floor label. No infrastructure API or AP inventory is assumed.

## 3. Seattle as a separate evaluation site

After a repeatable Bothell protocol, choose one accessible Seattle building. Keep independently surveyed building/reference mappings separate from algorithm settings. Freeze the estimator and its thresholds before Seattle evaluation; report any mapping/calibration required there. Shared campus Wi-Fi credentials do not establish transferable location accuracy or device-to-device reachability. Tacoma is excluded.

## Evidence and acceptance

For each messaging attempt record source event ID, configuration, start/end boundaries, receipt state, explicit human action, interruption and outcome. Separate first delivery, duplicate retry and intentional outage/recovery timing. Include every failed or incomplete attempt in denominators. Do not call a relay custody response delivery.

For localization compare sensor-only, sensor + Wi-Fi, sensor + peer and combined results on matched sessions, with held-out days/devices/routes. Report correct-floor, wrong-floor, Unknown, transition delay and observation age by route and building; inspect disagreement and missing-anchor cases. Do not claim an improvement from synthetic replay or repeated copies of one origin. No physical acceptance box closes until raw observations support it.

## Design review

Correctness: discovery names and contact edges are not trusted positions; authenticated evidence can still be wrong. Simplicity: test the existing peer-to-peer opt-in before adding another stack. Privacy: opt-in, synthetic messages, no arbitrary-user tracking or public location broadcasts. Maintainability: retain the C++ workflow and separate native adapters. Testing: use independent labels and held-out sessions, including failures. UX: keep manual reported floor separate, retain Unknown and show observation age. These checks constrain the next cooperative implementation rather than assert readiness.

Primary platform constraints: [Apple peer-to-peer networking](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api), [iOS Wi-Fi API limits](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview). Consulted 2026-10-09.
