# Durable Demo Session Implementation Plan

> Use superpowers:executing-plans inline under the user's existing implementation and publication authorization. Claude Code provides read-only review.

**Goal:** native sample requests and pending transfers survive restart without claiming unsaved success.
**Architecture:** bounded copy-on-write session → C++ SQLite transaction → no-throw state publication; validated ordered replay on open.
**Tech stack:** C++20, system SQLite, Swift 6 / SwiftUI, C ABI, CMake / SwiftPM.
**Spec:** ../specs/2026-10-07-durable-demo-session.md

## Constraints / review focus

Preserve public and responder journeys, explicit human actions and per-message delivery. iOS 18 / macOS 14 declared floors. Synthetic data, one request per reset, two independent models with a simulated link. No third-party download or production security/physical gate completion.

Check corrupted storage, failed reset, stale writers, receipt-only queues and process exit inside a write. Each is exercised below; role controls remain accessible and error/startup states are inspected.

## Checkpoints

- [x] Establish existing 14 C++ / 5 Swift baseline. Add open/reset C ABI and failing recovery tests.
- [x] Add bridge/session_store.hpp/cpp: schema/init, bounded ordered read, transactional save, generation checks and RAII. Link SQLite in CMakeLists.txt and Package.swift. Test corrupt/schema/lock/stale/write failure and uncommitted child exit.
- [x] Refactor bridge/workflow_bridge.cpp to stage mutations and commit before publication. Keep Model unchanged. Validate replay and pending ownership; retain in-memory rc_create. Run sanitizers and existing plus added suites.
- [x] Update swift/DemoController.swift for optional storage URL, safe open/reset/retry; update native app root to use Application Support and saved-session copy. Swift tests cover reopen, reset, startup failure and handling-history preservation.
- [x] Build and terminate/relaunch simulator app with offline and return queues; inspect both views and reset. Complete read-only Claude review/fixes, documents/evidence and ignore/secret/diff checks.

Publication handoff: commit this tested checkpoint, fast-forward main, verify the merged result, push to the authorized repository and remove the clean task-owned worktree. Git history records the publication outcome.

Commands: existing native README commands using /private/tmp/rescue-durable-{swift,cmake,release,derived}; CMake discovers SQLite3 and SwiftPM links sqlite3. New CTest recovery scenarios are registered in the actual manifest. No TODO acceptance entry is marked complete merely for this demo storage layer.

## Review revisions and evidence

Read-only Claude review prompted zero-page interrupted-initialization recovery, exact schema validation, recovery sidecar bounds, pre-open WAL rejection and explicit retry controls. Dirty main-page/journal assertions strengthened interrupted-write tests; COMMIT-lock retry uses the same handle. Optional in-memory retry retains state. Fresh verification: 24/24 sanitizer CTests, 24/24 Release CTests, 10/10 Swift tests, simulator build, iPad offline/return/correction/reconnect/reset and unsupported-version UI, iPhone queued SOS after force quit. Final Claude review found no blockers within this scope; arbitrary file tampering and hardware power loss remain unproven. Publication/merged-result verification is the final outstanding checkpoint.
