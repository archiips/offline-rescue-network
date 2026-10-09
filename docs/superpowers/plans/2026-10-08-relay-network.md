# Signed relay network implementation plan

Goal: separate-process encrypted SOS/receipt/ack/reply through a durable relay with nonoverlapping endpoint contacts.
Spec: ../specs/2026-10-08-relay-network.md. Execute continuously with authorized actual Claude Code Opus5.5/medium, parent review and fresh final read-only review. All spec bounds apply; preserve existing native modes. No dependencies. Commit local checkpoints, never keep sole source in temporary storage.

1. Read-only queue lookup/cache policy. Files: RescueRelay.h, relay_queue.cpp, relay_tests.cpp, CMakeLists.txt, RelayQueue.swift, SwiftTests/RelayTests.swift. Add rc_relay_lookup(handle,id,item**) => owned exact copy, absent8, invalid2, failure7; clears output before failure, read transaction strict validation, no attempt/fairness mutation, no pruning. Expose `lookup(id:) throws -> RelayItem?`. Add append-only cache admission (either C API flag/new method, or focused existing queue operation) with no expiry pruning; it must reject expired cached IDs and retain old rows. Tests first: reopen hit exact bytes/attempts0, absent/invalid/null/lock/type damage/no-output/descriptor lifetime; oldest returned selection still attempts1. Run RED then GREEN CTest+Swift.
2. Signed protocol + durable endpoint/service. Files: swift/RelayProtocol.swift, swift/RelayEndpointController.swift, swift/RelayService.swift, SecureEndpointController.swift internal context, LocalExchangeTransport.swift explicit relay initializer; SwiftTests/RelayNetworkTests.swift. ORL1/ORA1 exact spec, CryptoKit pin/signature/length/kind/expiry/correlation checks. Endpoint cache uses C++ append-only policy, epoch-specific file; validated hits exact bytes across controller restart, wrong context/corrupt/expired cache fails. Service enqueue verified wrappers; flush async via callback transport, validate acceptance/return, enqueue return before deletion; no endpoint state access. Tests first: signed wrapper valid bounds; modified metadata/ciphertext/wrong-pin/future-overflow/trailing bytes rejected; forged/wrong-ID/invalid-return acceptance retains original; cache restart ID stable; pending remains until decrypted reverse receipt; duplicate data/receipt and receipt correlation; forced response/cache/custody failures retain retry-safe state. Real crypto/stores, no tests mirroring implementation.
3. Actual Mac processes. Files: Package.swift, Sources/RelayNetworkHost/main.swift, tests/relay_network_smoke.py and tests/test_relay_network_smoke.py. Exact CLI from spec with bounded readiness/stdin offMainActor, diagnostic flush-drop. Test process startup/usage/cleanup/errors and nonoverlapping topology sequence. Harness records named PASS facts and no synthetic timing estimates. No runtime private key file; use existing Mac Keychain endpoint recovery and public cards at relay. Existing Python harness remains intact.
4. Verify/review/publish. Run sanitizer CTest fatalUBSan, complete Swift tests, real process harness, existing14 Python checks, signed native simulator build. Claude read-only review exactmodel/effort; reproduce/fix Important/Critical and rerun affected tests. Update relay walkthrough/current-state/only verified TODO subset/decisions/research/architecture status, keeping native controls/full product gates open. Check Markdown links, staged/full-range diff, secret-bearing ignore coverage. Fast-forward main and push authorized repo; verify remote SHA and clean task-owned worktree/branch cleanup.

Validation commands (repository root):
```
cmake -S experiments/workflow-model -B /private/tmp/rescue-net-cmake -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON
cmake --build /private/tmp/rescue-net-cmake
UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir /private/tmp/rescue-net-cmake --output-on-failure
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-net-swift
python3 experiments/workflow-model/tests/relay_network_smoke.py --host /private/tmp/rescue-net-swift/arm64-apple-macosx/debug/rescue-relay-host
RESCUE_EXCHANGE_HOST=/private/tmp/rescue-net-swift/arm64-apple-macosx/debug/rescue-exchange-host python3 -m unittest discover -s experiments/workflow-model/tests -p test_measure_exchange.py
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-net-derived CODE_SIGNING_ALLOWED=YES build
```

Review focus: cache eviction/prune/reset of expired pending mapping; replayed acceptance releasing wrong custody; return-save fails after endpoint commit; cached keys stale/missing history; overlapping direct endpoint contacts masked as isolated relay; lifecycle/concurrent async flush interleaving. Tests pin each. Serialize one relay flush at a time, admit callback only bounded synchronous operations, validate again after awaited response before deletes.

Preflight/self-critique: existing APIs identified; new thin C++ read/cache policy, Swift metadata/crypto, existing transport and hosts, no UI removal. Central wire sizes cover existing4276 frame. Separate reverse receipt admission/removal deliberately non-atomic but ordered/idempotent. Expired cached rows preserved; explicit error rather than renewal. Acceptance requires destination crypto; upload response only untrusted custody claim. Native UI integration deferred as specified next step. Checkpoint ledger below records actual evidence and deviations rather than claiming unrun tests.

## Execution ledger
Design/research/plan/critique completed before implementation. Baseline b1dd8bc, main clean, persistent ignored `.worktrees/relay-network` created.

### Task 1 — read-only lookup and append-only cache admission (2026-10-08)
- Baseline in worktree: sanitizer CTest 41/41; Swift build OK.
- RED: added relay_tests `lookup`/`cache` scenarios + CMake registration; build failed on undeclared `rc_relay_lookup`/`rc_relay_cache_admit`. Swift RED: `RelayQueue` had no `cacheAdmit`.
- GREEN: `rc_relay_lookup` (read transaction, full strict load, exact copy, stored attempts, expired rows visible, output cleared first; absent 8/invalid 2/storage 7/null -1) and `rc_relay_cache_admit` (shared admission path with `enqueue`, pruning disabled: expired IDs conflict instead of renewing, expired rows hold capacity, no eviction). Swift `lookup(id:)`/`cacheAdmit(...)` share the existing item/admission conversion.
- Checks: `UBSAN_OPTIONS=halt_on_error=1 ctest` 43/43 (sanitizers); `swift test` 68/68.
- Design note: lookup reports `remaining_hops` derived exactly as select does (stored − 1) to keep one struct meaning; cache callers ignore it.
