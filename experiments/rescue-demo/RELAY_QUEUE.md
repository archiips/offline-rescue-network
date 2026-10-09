# Opaque relay queue foundation

A C++20/SQLite custody queue, a Swift bridge and a runnable process-local encrypted delayed-contact scenario. No relay listener or native relay controls are provided by this checkpoint. Both existing native Secure exchange interfaces and Training retain their behavior.

## Behavior and bounds

The relay accepts opaque envelopes and local caller-supplied ID, flow, priority, logical expiry and hop metadata. It receives no endpoint keys or request text. Admission is trusted-call-only, not an authenticated network interface. Identical ID/metadata/ciphertext retries are idempotent; conflicting reuse rejects. Current direct Secure exchange reseals retries, so a future network adapter needs persistent stable-ID/exact-ciphertext mapping.

Retain at most64 items of181...4276 bytes, with eight selections per item and input hops1...2. Each returned copy consumes one hop; same-hop retries retain stored budget. Flow FIFO preserves prerequisites and exhausted heads block their flow until expiry/removal. Across eligible heads, at most three urgent selections precede an ordinary turn when ordinary work is eligible. Failed attempts never count as delivery. Fairness/attempt state commits before bytes return; full stores reject without eviction.

Expiry uses caller logical time, not an assumption of accurate wall time. Bounds cover retained rows/payload, not total historical filesystem usage. Local removal requires caller validation or administrative intent; the queue cannot verify endpoint receipts. Original endpoint pending state clears only after the endpoint decrypts/validates its destination receipt. This remains separate from human acknowledgment.

## Reproduce

```sh
swift run --package-path experiments/workflow-model \
  --scratch-path /private/tmp/rescue-relay-demo rescue-relay-scenario
```

Runtime-generated CryptoKit identities, independent C++ endpoint SQLite files and a relay file carry a preset encrypted SOS through delayed contact/reopen, lost receipt and exact retry. Reverse encrypted receipt is delayed separately; human acknowledgment has its own action/transfer/receipt. CLI reports named facts, fails nonzero on an unmet invariant and removes temporary stores. Runtime identities stay in memory; scenario reopens stores within one process rather than claiming process-wide key recovery.

## Scope and next step

This verifies code-level custody/contact logic, not radio, background delivery, physical range or an isolated socket topology. Next checkpoint: authenticated bounded routing metadata, persistent exact retry mapping, relay socket adapter, isolated public→relay→responder contacts and reverse path, then explicit native controls. Full NET-03/ENG-07 and security/physical gates remain open. Historical [plain direct benchmark](MEASUREMENTS.md) timings do not measure this queue.

## Fresh verification after reconstruction — 2026-10-08

- CTest:41/41, sanitizer build with fatal undefined-behavior checks, including11 grouped relay scenarios.
- Swift:67/67, including5 grouped bridge/actual encrypted-scenario checks.
- Python:14/14 existing harness checks, with freshly built host and actual socket/SQLite integration enabled.
- CLI:10 named facts, exit0. Usage rejection exit2 checked; forced executable runtime-error exit1 has not been exercised (scenario error handling is tested).
- Signed native simulator build succeeded. No new native relay UI was implemented or inspected; existing interfaces are retained.

Reproduction commands from repository root:

```sh
cmake -S experiments/workflow-model -B /private/tmp/rescue-relay-check-cmake -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON
cmake --build /private/tmp/rescue-relay-check-cmake
UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir /private/tmp/rescue-relay-check-cmake --output-on-failure
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-relay-check-swift
RESCUE_EXCHANGE_HOST=/private/tmp/rescue-relay-check-swift/arm64-apple-macosx/debug/rescue-exchange-host python3 -m unittest discover -s experiments/workflow-model/tests -p test_measure_exchange.py
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-relay-check-derived CODE_SIGNING_ALLOWED=YES build
```

The host path above is the verified arm64 Mac layout; inspect the actual scratch build on another architecture. Fresh runs used task-specific `rescue-relay-recovered-*` scratch paths and exited0. Rejected-open descriptor counting avoids disabled Apple SQLite allocation statistics. A maximum-admission/text-row test reproduced signed overflow before safe comparison validation fixed it. Original receipts/identity semantics were retained.

Existing nonempty files must have a complete SQLite header, DELETE-journal format and this queue's version/application ID before SQLite opens. Foreign hot journals stay untouched. Marked relay files may undergo SQLite recovery before strict schema/row validation; header markers are not authentication and do not promise byte preservation for damaged marked files. Real child-process crashes verify both foreign preservation and owned-store rollback. An incomplete initialization with no valid marker fails closed rather than being repaired automatically.

## Subsequent network checkpoint

[Signed separate-process relay](RELAY_NETWORK.md) adds authenticated metadata, exact retry caches, a listener and delayed reverse receipts. This document remains evidence for the earlier foundation; native controls and physical tests are still pending.
