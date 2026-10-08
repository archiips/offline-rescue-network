# Synthetic networking spike

> Current execution status (2026-10-08): see [current state / resume](CURRENT_STATE.md) and [portfolio tasks](TODO.md#current-portfolio-tasks). This document retains its product requirements, proposal or dated evidence; it does not claim that all described capabilities are implemented.

Status: probe prepared; physical validation pending · 2026-10-07 · NET-01 remains open

## Question and scope

Can the available iPhone and Mac exchange a small diagnostic request/receipt using Network framework, first over a local network and then without an access point? The older iPad is temporarily unavailable. This spike prepares that experiment; it is separate from the two-interface rescue product.

The user authorized this synthetic probe on 2026-10-07. Use Swift for Apple transport/lifecycle and C++20 for a fixed wire codec with a C bridge. No new external dependencies. No real SOS, participant data, location, responder identity, persistence, relays, AI, or background service. Plain TCP here is intentionally limited to fixed test frames, with no text-entry field. A diagnostic receipt conveys neither human acknowledgment nor trustworthy responder identity.

## Plan and acceptance

1. Test C++ wire validation against known bytes, malformed headers, wrong lengths and null arguments; prove failing then passing tests.
2. Implement a foreground Swift listener/browser/client with peer-to-peer opt-in, explicit peer selection, one frame per connection, a connection deadline and bounded concurrent sessions. Stop browsing before connecting; invalidate callbacks when stopped/restarted.
3. Provide a Mac host and a small iPhone/iPad SwiftUI test app. Stop the app's exchange when it enters the background. Expose failures and a retry rather than suggesting background delivery.
4. Build Mac and iOS Simulator targets; exercise actual loopback TCP and malformed/timeout behavior. Inspect the UI when simulator tooling permits. Record what each check proves.
5. Record a candidate product message contract and security decisions, keeping SEC-01 unresolved. Publish reviewed code/docs at a verified checkpoint.

Acceptance for **preparation**: source builds, fixed wire rejects malformed input, real localhost round trip and interruption tests pass, instructions enable manual hardware testing, and all claims distinguish simulator/loopback from radio evidence. NET-01 acceptance still requires physical measurements.

## Alternatives and self-review

Apple's current TN3213 recommends Network framework and documents Multipeer Connectivity deprecation in Xcode 27. Use the older NWListener/NWBrowser/NWConnection API surface to investigate broader OS compatibility; don't require an iOS 27 update or infer hardware support from SDK compilation. Wi-Fi Aware remains a candidate for supported hardware but adds pairing/entitlement/device constraints. LAN is a useful baseline but cannot establish access-point-free operation. BLE and mesh routing would broaden this first experiment without answering the direct-path question.

Correctness: fixed frames and matching random request IDs prevent accidental success from stale receipts; this is correlation, not authentication. Simplicity: one request per TCP connection eliminates stream framing/state complexity. Security: no arbitrary body, strict bounds, finite sessions/deadlines; no private-data exception. Maintainability: native networking stays outside the portable C++ codec. Testing: byte fixtures plus real TCP, with physical testing still gated. UX: label synthetic receipts clearly, keep explicit connection controls, stop on backgrounding. Both eventual product journeys remain unchanged.

## Hardware run sheet

Record exact device/OS, app revision, topology, permission result, foreground/locked/background state, discovery time, receipt time, failure and retry outcome. Avoid device serial numbers and personal data.

- Baseline: iPhone and Mac on the same Wi-Fi, with internet unavailable. Proves local exchange only.
- No access point: remove the shared network/hotspot while keeping Wi-Fi enabled; run peer discovery and receipt. Record actual route/interface where available. A same-LAN pass is not this result.
- Interruptions: deny Local Network, stop host, retry, lock phone, background then foreground, restart host. This probe deliberately stops on background; no background relay claim follows.
- Older iPad: repeat when available; do not presume its supported OS or radio capability.

Build/run commands and exact evidence will be recorded with the experiment README. No task in TODO.md is closed merely by this preparation.

## Preparation evidence — 2026-10-07

- `swift test --package-path experiments/network-probe --scratch-path /private/tmp/rescue-probe-build`: **8 Swift Testing tests passed**, including the C++ byte contract/malformed boundaries, actual localhost round trip/restart, stopping before connection, stopping after a host receives the request but before its delayed reply, split TCP writes, wrong receipt ID, truncated stream and idle timeout. The XCTest compatibility runner reports zero XCTest tests; the eight tests run under Swift Testing.
- Initial codec test failed against the deliberately empty implementation, then passed after implementation. Negative network tests exposed test-fixture problems (missing final-message EOF and listener readiness); those were corrected without weakening expected behavior.
- `xcodebuild -project experiments/network-probe/iOS/NetworkProbe.xcodeproj -scheme NetworkProbe -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-probe-derived CODE_SIGNING_ALLOWED=NO build`: **build succeeded** with Xcode 26.4. The AppIntents metadata warning is informational; no AppIntents dependency is used.
- iPhone 17 Pro / iOS 26.4 **simulator**: installed/launched; screen inspected for readable text/wrapping; Find test host → selected Mac host → synthetic receipt worked through UI controls; Stop was checked. Updated run reported one receipt and NWPath `loopback` / `lo0`. These runs used the same Mac, not physical phone radios. Home/background action was exercised, but return-state inspection was interrupted by unavailable Simulator UI; no complete background/resume validation claimed.
- Claude Code performed two read-only reviews, with exact test paths supplied on the second pass. No blockers remained; two minor findings led to the delayed-reply test and weak timeout ownership. Also corrected the rolling-log host output and inactive-scene cancellation, added qualified path diagnostics, and documented trailing bytes/idle-peer denial-of-service limits. This is engineering review, not a security audit.

**Still unverified:** phone installation/signing, physical iPhone/Mac or iPhone/iPad networking, no-internet/no-access-point operation, older-device/OS runtime support, permission denial and lock/background behavior on hardware. NET-01/SEC-01/ENG-01 remain open. The next step is the controlled iPhone/Mac run in the experiment README; iPad testing can follow when it is available.
