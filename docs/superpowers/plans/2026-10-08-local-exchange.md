# Local Rescue Exchange Implementation Plan

> Use superpowers:executing-plans inline with the user's existing implementation/publication authorization. Actual Claude Code supplies read-only whole-branch review.

**Goal:** sample rescue workflows cross a real local connection between independent saved endpoints.
**Architecture:** C++ single-endpoint Model and transactional outbox; bounded C++ binary packets; Swift foreground NW socket request/receipt exchange; native local mode alongside unchanged training.
**Tech stack:** C++20, SQLite, Swift 6, SwiftUI, Network framework, SwiftPM/CMake.
**Spec:** ../specs/2026-10-08-local-exchange.md

## Constraints / review focus

Retain public/responder journeys and training store. iOS18/macOS14, 128 events/64 outbox, packet4096, network8 sessions/8s deadline/20 peers. Preset synthetic data, plain unauthenticated local protocol, no new external dependencies or physical/security gate closure. Review delayed/missing receipt, process restart, callback after stop, receiving near capacity, wrong-role/old session and malformed stream. Each is pinned in the owning tests.

## Checkpoints

- [x] Baseline 24 CTest / 10 Swift; add C ABI endpoint declarations and failing independent-store exchange test. Files: bridge/include/RescueDemoBridge.h, tests/endpoint_tests.cpp, CMakeLists.txt.
- [x] Add bridge/endpoint.cpp and event_wire.hpp/cpp, extract display helpers to demo_support.hpp; extend SessionStore with isolated role-tagged v2 metadata while preserving v1. Implement rc_endpoint_open/destroy/perform/next/accept/confirm/snapshot/reset. C ABI packets use owned byte buffers freed by rc_free, size_t lengths. next yields oldest unconfirmed non-receipt; accept returns committed receiver receipt, confirm validates/removes exactly matching pending original after commit. Prove retry/reopen, malformed/role/schema isolation, failed receiver/sender saves and capacity. Keep original domain Model unchanged.
- [x] Add swift/EndpointController.swift and LocalExchangeTransport.swift. Red tests for real two-store roundtrip and fragmented/oversized length framing; implement isolated MainActor callbacks, bounded single request/receipt sessions, stop generation checks and sequential batch drain. Add SwiftPM Mac executable Sources/ExchangeHost/ExchangeHost.swift and documented separate-process host/client walkthrough; verify SOS, explicit acknowledgment/reply, correction and restarted queue over loopback.
- [x] Add native mode/role/peer controls in RescueDemoApp.swift, preserve existing views by adapting DemoController to optional endpoint state, update PublicView/ResponderView context copy and Info.plist Bonjour/privacy keys. Build simulator, inspect both modes and exercise real simulator-to-Mac SOS/ack/reply with restart. Retest training journeys and store preservation.
- [x] Claude read-only review, reproduce/fix important findings, sanitizer/Release/Swift/native checks and docs/evidence. Complete ignore/secret/diff review before the authorized publication step; publication and cleanup outcome is recorded by Git history and the task handoff.

Acceptance: each mutation succeeds only after its owning database commit; write/network failures retain pending originals; retries never add duplicate events or regress acknowledgment; no remote Model exists inside a network endpoint. Existing training remains functional. Exact final counts and independent-process/native evidence are recorded after running checks, without invented benchmarks.

Commands: cmake -S experiments/workflow-model -B /private/tmp/rescue-exchange-cmake -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON; cmake --build; ctest --test-dir --output-on-failure. Swift tests use /private/tmp/rescue-exchange-swift. Xcode uses RescueDemo scheme and /private/tmp/rescue-exchange-derived. Release uses separate /private/tmp/rescue-exchange-release. Network harness binds loopback for automated evidence; Bonjour/native availability is separately observed.

Self-review: independent endpoint stores and receipt regeneration preserve semantics without copying the remote state. Native training is retained to avoid deleting earlier demonstrable flows. Packet and TCP framing bounds are separate. Callback invalidation and restart tests prevent false delivery. Synthetic role names and coordinated reset are stated limits; security/product task completion is not inferred.

## Execution ledger

Baseline: 24 CTest and 10 Swift passed. Endpoint test observed red with null open stub, then six endpoint scenarios passed. Invalid UTF-8 and a receipt for a different queued message reproduced failures and were fixed before accepting packets. Capacity fixture revised to leave sender at127/receiver128 events rather than inadvertently exhaust both before the intended receiver check. Receipt-before-human-ack and human-ack-before-device-receipt recovery both covered. Claude implemented only the three named Swift transport/controller/test files; parent owns C++, native adapter and CLI. Initial Swift integration compile error was an error-variable shadow in parent code; fixed. One delegated test assumed display role "responder" instead of the existing fixture "command"; corrected to the C++/spec contract. Networking tests use actual NW loopback sockets and independent databases, not mocked delivery.

C++ review found no initial blockers but recommended receipt-capacity reservation, canonical event IDs and outbox-order validation. New tests reproduced all three gaps, then implementation was revised. Existing pending receipts retain reserved history slots even when new events reject at capacity; changed/aliased IDs and reordered durable queues fail closed. Outgoing action duplicates cannot enter the outbox.


Final adapter/native checkpoint: 33 Swift tests pass, including the preserved ten training/storage tests. Separate Mac CLI processes verify SOS, explicit acknowledgment/reply, correction, refused connection and killed-process outbox recovery. iPhone simulator exchanged SOS/ack/reply with a Mac responder via Bonjour; iPad simulator received SOS from a Mac public endpoint, retained two queued return messages across force-quit and delivered them after restart. Assignment/resolution also reached the Mac. Final native build succeeded, retained resolved responder state after install/relaunch, and training remained empty/separate; start/stop controls and rendered layout were inspected.

Whole-branch actual Claude read-only review found no blockers. Optional findings addressed: background-only shutdown avoids interrupting temporary inactive permission prompts; nextPacket reports a nonempty outbox whose bytes cannot be returned; a failed transfer clears peer selection. The failed-peer regression reproduced red, then all 33 Swift checks passed. A scheduled automatic batch carries the controller generation so stop/start cannot send an old task. C++ final tree passed 30 sanitizer and 30 Release checks. No physical radio, private-data or performance claim follows.

Publication checkpoint: integrate only the reviewed files and docs after ignore, secret, link and diff checks; re-run relevant checks on merged main before pushing. Git history provides the publication outcome; do not infer it from this plan.
