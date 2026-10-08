# Native workflow demo implementation plan

**Goal:** usable SwiftUI public/responder demo with shared C++ state and simulated transport.
**Spec:** ../specs/2026-10-07-native-demo.md
**Architecture:** C++ session wrapper owns two Model instances and a bounded queue; C ABI exposes preset actions and owned JSON snapshots; MainActor Swift controller renders immutable snapshots. No external dependencies.
**Execution:** inline under existing user authorization; review via authorized Claude Code.

## Checkpoints

- [x] Add C++ bridge and Swift package manifests, typed snapshot/controller contracts and failing tests.
- [x] Implement safe ownership/error/bounds handling; manual human actions; queue/reconnect with destination receipts only after in-memory acceptance.
- [x] Implement native public and responder flows with per-message states, preset synthetic data, reset and simulated-link control.
- [x] Run existing CTest suite, bridge/Swift tests, sanitizer checks and simulator build. Inspect rendered screens and replay main journeys.
- [x] Read-only review, fixes, evidence, secret/diff checks and public checkpoint.

## Critique / decisions

Correctness: no remote mutation from merely writing a local acknowledgment; control receipts never create loops; retries use stable receipt IDs and retain transfers when destination acceptance fails. Simplicity: one synthetic request per reset, two role controls in one app. Security: fixture role switching is visibly a demo, no private text input or security claims. Maintainability: reuse workflow.cpp through SwiftPM and CMake; business transitions stay C++. Testing: disconnection, queued return action, repeated withdrawal, malformed/oversized bridge arguments, JSON escaping and repeated reset/lifetime. UX: show each pending update, command-local late-review flag, and clear empty/retry/error states.

Alternative direct C++ interop was considered; retain the established C ABI to keep ownership and Swift imports small. Separate app processes/radio transport are deferred until the native journey is verified. The prototype's acceptance-order late flag remains command-local and is not promoted to a convergent production reducer.

## Validation commands

Swift: `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-native-swift`.
C++: existing CMake/CTest commands from workflow-model/README.md, plus bridge tests registered there.
iOS: `xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-native-derived CODE_SIGNING_ALLOWED=NO build`.
Primary build guidance: https://www.swift.org/documentation/articles/wrapping-c-cpp-library-in-swift.html (accessed 2026-10-07). Apple TN3213 supports investigating foreground local P2P but does not establish our physical feasibility.

## Completed checkpoint evidence

2026-10-07: 5 Swift integration tests pass. All 14 CTest checks pass in Release and Debug with ASan/UBSan. Xcode simulator build succeeds; native public/responder interactions were inspected on iPhone 17 Pro and iPad Pro 11-inch (M5) / iOS 26.4. Read-only Claude Code review and follow-up completed, with bridge exception/error/schema fixes. No blockers remained for the bounded synthetic demo. Receiver/sender receipt disagreement at exhaustion is expected asynchronous knowledge; reset remains the sample recovery policy. See experiments/rescue-demo/README.md for exact commands, journeys and exclusions. Native UI inspection led to explicit accessible role controls and syncing the sample floor from the current reported location on view entry. No production TODO entry or physical/security gate was closed.
