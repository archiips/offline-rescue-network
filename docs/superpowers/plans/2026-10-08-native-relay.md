# Native relay controls implementation plan

> Execute inline with superpowers:executing-plans; independent final review. Existing user approval covers continuing this checkpoint and scoped publication.

Goal: expose the verified signed relay path in both native interfaces without changing workflow semantics.
Architecture: DemoController owns current secure endpoint plus optional relay adapter; one bounded transport per route. Shared SwiftUI controls make route/upload/listening explicit.
Stack: C++20, Swift6, SwiftUI, CryptoKit, Network, SQLite; iOS18/macOS14 floors unchanged.
Spec: ../specs/2026-10-08-native-relay.md

## Constraints and risks

Synthetic data only. No direct fallback or automatic relay upload; ORC1 never confirms delivery. Cache loss/expiry requires explicit reset/re-pair and preserves files. Foreground only. Preserve both audiences/Training/direct journeys. No new dependencies. Important risks: post-await route/epoch changes, stale custody labels, cached retry mismatch, incoming callback refreshing UI before receipt commit and compact-phone overflow.

## Task1 — controller integration

Files: experiments/workflow-model/swift/DemoController.swift; SwiftTests/NativeRelayTests.swift.
Interface: useRelayRoute(_ enabled: Bool), relayMode, relayStatus, startLocalExchange(port: UInt16? = nil), uploadViaRelay(host: String, port: String) async. useSecureRole has optional viaRelay=false for restored preference. transferQueued refuses relay mode; perform never auto-uploads in relay. bindSecureEndpoint supplies correct incoming handler; reset/reopen rebuild adapter, stops before reopen. Same identity/outbox survives route toggle.

- [x] Write failing tests for secure route switching/preserved card/history, pairing/start guard, validated manual address, custody-ID mismatch/no outbox confirmation, exact retry, route change during awaiting response, no direct-send path, delayed SOS/receipt/ack/reply over real relay sockets and reset/reopen.
- [x] Run Swift tests, inspect expected missing APIs/behavior. Implement minimal controller integration; rerun full suite. Record actual RED/GREEN and commit coherent code checkpoint.

## Task2 — shared native controls

File: experiments/rescue-demo/iOS/RescueDemoApp.swift. Consumers use Task1 controller interface. Persist route preference via AppStorage; role/mode restore uses viaRelay. Add Direct/Via relay selector and shared RelayConnectionControls with manual address fields, bounded input, listener port/status, Upload/Stop and waiting explanation. Preserve existing pairing/error/reset views; no debug launch hooks. Inspect compact phone and tablet rendered controls, then signed native build. Test interaction availability and recovery copy in realistic views.

## Task3 — verification, review and publication

Run actual manifests: Swift suite, fatal-UBSan43 CTest, real13 relay and14 measurement Python checks, signed native simulator build. Exercise native-to-Mac path with paired synthetic endpoints if tools permit; record exactly the evidence achieved. Independent reviewer examines full8bf23d3 range, especially generation invalidation/route separation/receipt semantics. Reproduce/fix consequential findings. Update current state, only verified TODO entry, walkthrough, decisions and status banners. Check links/diff/ignore/secret patterns, scoped commits, ff main/push exact authorized repo, remote SHA then task-owned worktree cleanup.

Commands:
```
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-native-swift
cmake -S experiments/workflow-model -B /private/tmp/rescue-native-cmake -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON
cmake --build /private/tmp/rescue-native-cmake
UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir /private/tmp/rescue-native-cmake --output-on-failure
RESCUE_RELAY_HOST=/private/tmp/rescue-native-swift/arm64-apple-macosx/debug/rescue-relay-host python3 -m unittest discover -s experiments/workflow-model/tests -p test_relay_network_smoke.py
RESCUE_EXCHANGE_HOST=/private/tmp/rescue-native-swift/arm64-apple-macosx/debug/rescue-exchange-host python3 -m unittest discover -s experiments/workflow-model/tests -p test_measure_exchange.py
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-native-derived CODE_SIGNING_ALLOWED=YES build
```

Self-review: tasks share the controller interface specified once above; no protocol/role removal, test-only production flags or new dependencies. Signed native path verification is distinct from Swift integration and build evidence. Source labels must remain honest if UI automation blocks an end-to-end exercise.

## Ledger
2026-10-08: discovered current baseline8bf23d3, research/design/critique before implementation. Persistent ignored .worktrees/native-relay on feat/native-relay. Inline local execution while Claude quota unavailable; exact Opus5.5/medium only when available. Previous observation4/5/6/7/8 insights applied. No repeated approval request under existing explicit execution authorization.

Task1 complete: test-first missing route/upload APIs failed compilation; corrected fixture API names before GREEN. Added controller route/upload/listener-port integration, preserving one endpoint identity/history. Five tests passed/full94 Swift. A sixth race test initially triggered a Swift compiler assertion with nested #require calls; separated bindings, reproduced late ORC1 overwriting a committed device receipt, then fixed via original-head comparison. Full95 Swift passed. No test-only hooks or protocol changes.
Task2 code checkpoint: shared native route picker/connection sheet, host/port fields and explicit start/upload/stop/recovery. Native build exposed sheet modifier attached to conditional view; wrapped controls in VStack, signed build passed. Read-only review found no blocker, requested compact-phone render inspection. Fresh43 sanitizer CTest,13 relay Python with actual hosts and14 existing Python passed. Native interaction evidence pending.

Review revision: Claude Opus5.5/medium became available and its read-only review identified a mixed-route delayed-receipt blockage. Preserve route switching rather than disable an existing journey. Add a read-only C++ bridge lookup returning the original only for an exact receipt already committed in history. Relay correlation must still validate the previously signed/cached outgoing event; no arbitrary receipt or missing cache bypass. Test upload → Direct confirmation → reopen → delayed relay receipt → acknowledgment, plus malformed/history lookup checks. This adds a bridge API, not a wire/store-format change. Recheck sanitizer, Swift, hosts and native build after the fix.

Final bounded checkpoint: Opus5.5/medium identity verified from modelUsage on both reviews, no fallback. Reproduced mixed-route blockage after correcting test-fixture API errors; read-only exact-history bridge lookup fixed it. Follow-up review found no remaining Critical/Important issue. Strengthened test with a newer pending head and C++ negative/null/read-only lookup checks. Full96 Swift,43 fatal-UBSan CTest,13 relay Python/11 subprocess facts,14 retained harness tests and signed native build pass. No product code changes after that build. Minor residuals: raw diagnostic error strings, incoming rejection surfaced to relay rather than native error banner and extreme Dynamic Type/error-layout matrix not comprehensively exercised.

Rendered updated iPhone17 Pro/iPad Pro11 M5 controls, host/port sheets, disabled unpaired Start/Upload and scrollable recovery copy inspected on iOS26.4; signed apps installed and relaunch stays stopped. iPad empty-state copy now explicitly names the relay Mac. Native full relay round trip NOT claimed: automatic approval review rejected fingerprint trust confirmation without fresh action-time consent. Explicit approval question pending; both synthetic endpoints remain unpaired, old epoch files retained, no workaround. Split completed controller/UI TODO from pending attended native exercise. Publication uses existing authorization for verified checkpoint only.


Attended verification2026-10-08/09: explicit user approval received, full fingerprints checked and native trust established through normal UI on both simulators. Completed SOS/custody/waiting/delayed receipt, human acknowledgment, reply and Floor4 correction with eight successful relay flushes. Home/return stopped responder listener; public restart retained unsent correction/pairing/route/address, absent-relay upload retained queue, same relay DB restart/new endpoint ports recovered correction; responder restart retained full history/corrected location and stopped networking. Both queues/relay custody zero; relay quit normally, both apps left stopped with synthetic history. No code changes/new test counts. Structured manual evidence committed beside NATIVE_RELAY.md. User requested ending this window; docs identify the exact next portfolio step. Earlier pending-approval ledger is historical and superseded.
