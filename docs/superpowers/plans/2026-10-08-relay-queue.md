# Relay queue recovery/execution plan

Spec: ../specs/2026-10-08-relay-queue.md. Outcome is bounded custody foundation, not full multi-hop task. Pre-build discovery/research/design/critique completed before interruption; baseline d1ac5cb remains. Temporary worktree was lost after laptop restart; do not claim historical tests as reconstructed verification.

1. Persistent .worktrees/relay-queue, ignored; commit design/recovery metadata before rebuilding. Preserve main and user changes. Never keep sole uncommitted deliverables in /tmp.
2. Test-first C++ C ABI+SQLite implementation: bridge/include/RescueRelay.h, bridge/relay_queue.cpp, tests/relay_tests.cpp, CMakeLists.txt, Package.swift. Expected RED missing implementation; then all bounded/failure scenarios GREEN including failed constructor descriptor lifetime. Exact schema validation/numeric types, FIFO3:1, transactional attempts/retries and limits per spec.
3. Test-first Swift wrapper and real encrypted scenario: swift/RelayQueue.swift, swift/RelayScenario.swift, SwiftTests/RelayTests.swift, Sources/RelayScenarioHost/main.swift, explicit module.modulemap. Test actual ciphertext, delayed contacts, dedupe and receipt facts. No native/endpoint/envelope/transport behavior edits. Commit verified foundation checkpoint locally.
4. Fresh full CTest sanitizers, Swift tests, CLI,14 Python harness checks with RESCUE_EXCHANGE_HOST set, signed native build. Read-only Claude Opus5.5 medium review; reproduce/fix important defects, full affected suites. Diff/secrets/ignore checks, only completed TODO subset, current-state/decisions/research/walkthrough updated. Merge main fast-forward and push authorized archiips/offline-rescue-network, clean task worktree after verified publication.

Scratch artifacts may use /tmp; source/plans/log evidence pointer must be durable. CMake/Swift/Xcode commands from existing manifests, scratch directories task-specific. Record exact final commands/counts and failures. Model --model claude-opus-5-5 --effort medium, no fallback. If unavailable implement locally/report.

Review focus: corrupted schema/row types/counters, constructor/commit lifetime, changed duplicate ciphertext, exhausted FIFO head, failed saves before output, custody versus validated endpoint receipt.

Ledger: Prior ephemeral implementation reported40 CTest/70 Swift/14 Python/13 CLI/signed native build; those artifacts and review output lost. Reconstructed code must be verified afresh. Scope preserved; no completed main milestone restarted.
