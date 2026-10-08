# C++ synthetic workflow model implementation plan

**Goal:** exercise the public/requester and responder workflows without physical devices.
**Architecture:** two independent C++20 model instances exchange typed synthetic events through a manual delivery harness. Native transport, wire serialization and endpoint cryptography remain separate and unimplemented here. Each instance validates fixture role/ownership, stores bounded immutable events in memory, and derives snapshots.
**Spec:** docs/SYSTEM_DESIGN.md sections 3–5, narrowed as below; docs/PROTOCOL_SECURITY_DRAFT.md is a candidate, not a frozen wire protocol.
**Execution:** inline, under the user's existing authorization to keep building and publish verified checkpoints.

## Scope and design choices

Create `experiments/workflow-model/{CMakeLists.txt,include/workflow.hpp,src/workflow.cpp,src/demo.cpp,tests/workflow_tests.cpp,README.md}`. No external dependency. Build a library, deterministic scenario executable and CTest tests. All fixtures are synthetic; IDs and roles are explicit test inputs, not authenticated identities.

`Model(localActor, exercise, members, capacity)` distinguishes local submission from inbound delivery. Submission requires the local actor; inbound requires the intended local destination. Author role, original requester ownership, exercise and reference binding are checked using the supplied fixture registry. A receipt references an accepted non-receipt event and comes from that event's intended destination. Local inbound acceptance alone never changes the remote model. Receipts are explicitly created after acceptance and independently delivered. No receipt loops.

Request, follow-up, correction, withdrawal, acknowledgment, reply, assignment, resolution, reopen and withdrawal disposition are immutable event kinds. Per-author/request sequence collisions reject; arrival order does not overwrite a higher-sequence reported location. Handling uses one fixture command author and strict revision increments. Resolution records the latest public sequence observed; later-arriving updates, including lower-sequence gaps, remain visible while resolved and require explicit reopen. Withdrawal and its disposition do not automatically resolve a request. Disposition references its exact withdrawal; new withdrawals have new pending decisions. Snapshots expose all public messages and an undelivered count.

Bounds: 64-byte IDs, 2 KiB combined text/location, 128 events by default. Capacity and injected memory-store failure reject before acceptance; this is not crash durability. Unknown request/reference or future handling revision returns MissingDependency for caller retry. Unlike the eventual design, this milestone does not persist pending reconciliation, queues, key epochs or wire versions. These are deliberate omissions, not completed ENG-02/04 capabilities.

Alternatives: production client scaffolding would depend on unresolved transport/security gates; UI-only mock screens would duplicate domain rules in Swift. A small isolated C++ model advances domain behavior without choosing either. No protocol serialization, radio claim or private-data exception follows.

## Critique and revision

Correctness: independent models prevent a locally written responder acknowledgment from magically appearing at the requester. Simplicity: snapshots derive from a small bounded event list rather than a database/cache pair. Privacy: synthetic fixture authority is visibly not authentication. Maintainability: domain-only C++ can be evaluated before a Swift bridge. Testing: test dropped/delayed delivery, stronger acknowledgment before receipt, duplicates/conflicts, ownership, limits and failed writes. UX: preserve corrections/withdrawal and responder handling; never merge their statuses into delivery.

## Checkpoints and acceptance

- [x] Write meaningful failing tests against stub implementations; verify failure.
- [x] Implement domain validation/projections and independent-model round trip.
- [x] Add demo showing queued request, device receipt, human acknowledgment, reply, correction, withdrawal and explicit handling.
- [x] Run Debug and Release CTest plus AddressSanitizer/UndefinedBehaviorSanitizer build; inspect demo output and diff.
- [x] Obtain read-only Claude review; fix substantive findings; document evidence and publish.

Commands are established in the CMake manifest: configure with `cmake -S experiments/workflow-model -B /private/tmp/rescue-workflow-build -DCMAKE_BUILD_TYPE=Debug`, then `cmake --build ...` and `ctest --test-dir ... --output-on-failure`. Sanitizer flags are a manifest option. NET-01, SEC-01 and ENG-01–05 remain incomplete.

## Verification record — 2026-10-07

Initial tests compiled against stub methods and all eight scenarios failed as expected. The final suite contains 13 CTest scenarios: normal round trip, corrections/withdrawal, handling, ownership, references, failed store/conflict, ordering, bounds, late sequence gaps, repeated withdrawals, dependency retry, invalid handling and hidden pending updates. Debug passes 13/13. The complete command-line walkthrough was run and inspected: an undelivered acknowledgment remains local, the requester retains a pending correction, and a late withdrawal does not silently reopen a resolved request.

Claude's first read-only review identified late gaps below the sequence high-water mark, latest-message-only snapshots hiding pending corrections, unbound withdrawal dispositions, and missing dependency-retry coverage. Regression tests reproduced the first three defects before fixes. The model now flags post-resolution arrival independently of highest public sequence, exposes per-event public delivery, binds dispositions to withdrawals, and tests retry after missing predecessors. This is engineering review of synthetic semantics, not a security audit.

Review focus for later UI/storage integration: do not infer all updates arrived from a highest sequence; do not show only the latest message status; preserve the exact withdrawal reference. Native state snapshots must carry these facts to both interfaces.

No existing TODO.md item is marked complete: production tooling, serialization, durable storage, authenticated identities, Swift integration and physical NET-01 remain future work.

Final verification: Release and AddressSanitizer/UndefinedBehaviorSanitizer configurations also pass all 13 tests (AppleClang 21, CMake 4.3.2, macOS arm64). Second Claude read-only review: no blockers. Its non-blocking notes are documented: delivery is interpreted from the sending model, and the command-local late flag depends on acceptance order. Production convergence/durable replay must preserve that evidence or introduce explicit causal references.

Ruling: keep this model an isolated experiment ahead of NET-01/SEC-01 rather than silently completing the gated production tasks. This advances synthetic domain behavior while preserving every existing security/physical-validation gate.
