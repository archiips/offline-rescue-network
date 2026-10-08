# Measurement Harness Implementation Plan

> Execute inline with superpowers:executing-plans under the user's existing build/publication authorization; whole-branch read-only Claude review uses exactly Opus 5.5, medium effort.

**Goal:** repeatable actual loopback exchange/recovery evidence for the résumé project.
**Architecture:** stdlib Python launches existing Swift/C++ endpoint hosts; validates command results and read-only SQLite state; bounded proxy replays and drops a receipt; exports versioned raw evidence and descriptive statistics.
**Tech stack:** Python stdlib orchestration, existing Swift Network/C++20/SQLite hosts.
**Spec:** ../specs/2026-10-08-measurement-harness.md

## Global constraints / review focus

No product/UI/protocol changes, external dependencies, private data or physical claims. Trials1–100, timeout 12s, TCP1–4096 payload, bounded host output, exclusive output file and cleanup. Focus: timed-out/closed hosts, truncated/oversized proxy frames, all trials fail, existing output, incorrect duplicate/pending counts. Tests pin each boundary.

## Checkpoints

- [x] Baseline 30 CTest /33 Swift, preserve original smoke test. Add tests/test_measure_exchange.py importing tests/measure_exchange.py: summary([1,2,3,4]) yields median2.5/p95=4, empty yieldsnull; report with one pass and one failure keeps failed record and count but summarizes only passed values; invalid trial range rejects. Run unittest red against stub/absent implementation.
- [x] Implement measure_exchange.py statistics/argument validation, bounded frame reader, Host ownership/output queue/command deadlines/EOF/cleanup and DropReceiptProxy; read-only store_facts validates eight histories/four originals/receipts/no pending at final. Tests exercise real frame sockets, actual EOF child and bounded overflow. Use no global mutable CLI state.
- [x] Implement run_trial(binary,trial): fresh temporary stores, SOS/explicitack/reply, refusedconnection, public kill/restart, two identical proxy receipts dropped, direct retry; preserve failures/partial measurements and clean resources. End-to-end unittest runs one actual host trial; CLI failure/collision test checks exit behavior. Run full unittest and existing process smoke against built host. Run 20 trials, inspect JSON counts and independently recompute summary.
- [x] Claude read-only branch review with --model claude-opus-5-5 --effort medium, no fallback; fix material findings with tests. Re-run affected checks. Update walkthrough/README, TODO, decisions and current-state exact next step; preserve original product gates. Review links/diff/ignore/secrets, commit/ffmerge, verify merged tests, push and clean only this task-created worktree.

Commands: swift test/build --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-measure-swift; python3 -m unittest discover -s experiments/workflow-model/tests -p 'test_measure_exchange.py' -v. Integration tests receive RESCUE_EXCHANGE_HOST absolute binary path. CLI: python3 experiments/workflow-model/tests/measure_exchange.py --host <absolute binary> --trials 20 --output <new json path> (arguments separated normally). Existing CTest baseline 30; new Python tests are separate and not added to CTest count.

Self-review: timing boundary is source-confirmation command, not fire-service response/radio latency. Duplicate proof inspects persisted IDs/receipts rather than message total alone. Failures remain in export, output never silently overwrites and subprocess loops are finite. Port availability races become failures rather than silently retried/excluded trials. No product function or native UI change is planned.

## Execution ledger

Discovery complete; baseline 30 CTest passed. Existing user approval covers this continuation; no new scope or destructive action. Existing observations0005/0006 apply: preserve both journeys and portfolio brief. Final code review must honor the explicit Claude model/effort preference.


Checkpoint evidence: baseline 30 CTest and 33 Swift pass. Test stub produced the expected summary/validation red failures; implementation boundary tests ran with socket permission and passed. First real integration failed with a missing tempfile import at startup; fixed the import, then all 10 original harness tests passed including actual lost-receipt/restart. Actual Claude review used explicit claude-opus-5-5 and --effort medium (no fallback). It had read the pre-import-fix snapshot, so that blocker was already fixed and independently verified.

Review response: confirmed report() emits ERROR after STATE. New fake-host regression reproduced false success; added an untimed state fence while preserving the measurement stop at the first STATE. Exact numeric field matching, programmer errors propagating and atomic report output each reproduced red before fixes. Explicit SQLite closing,3s Git timeout, sanitized expected failures and per-host cleanup preserve resources/traceability. Failure CLI test moved outside real-host skip and now checks the actual Hostclosed cause/type. All14 Python tests pass with the real host configured. Fingerprint-layout concern rejected against actual Package.swift: swift/*.swift is the configured target and already hashed. Proxy-framing concern resolved by actual lost-receipt integration, not a protocol change. Whole-branch follow-up uses the same exact requested Claude model/effort.

Ruling: retain Python as test orchestration only; source/endpoint/SwiftUI code remains unchanged. A preliminary20-trial run passed but final evidence is rerun after reporting changes rather than reusing old measurements. New Python bytecode ignore rules prevent generated test files from entering Git. Original process smoke passes unchanged. No physical/security product gate is completed.


Follow-up review returned no Critical/Important issues and no blockers. Its JSON metadata reports exactly claude-opus-5-5; CLI effort was explicitly medium. Minor cleanup-error attribution, future nested fingerprint paths and report-publication filesystem limits are recorded as limitations, not silently treated as fixes. Current macOS filesystem supports exclusive hardlink publication; source target has no nested Swift directories. Existing output and invalid JSON serialization safety tests pass. Source/host fingerprints and dirty-worktree status are retained in the evidence.

Recovery note: the daemon restart interrupted the post-review run before final JSON publication. The old tool process/session was gone; no measurement/host processes remained and the output path did not exist. Restarted twenty fresh trials with stdout redirected to a durable local log. The preliminary pre-fence 20-trial run is not reused for the published measurements; the incomplete interrupted run is not a completed measurement report.

Final capture:20/20 passed. Independently recomputed median/nearest-rank p95/min/max from all 20 raw trials, verified all five checks/final histories and matched every recorded source SHA256 to the final files.14 harness tests pass, original smoke passes. Publication remains represented by Git history; perform diff/link/ignore/secret checks and merged verification before authorized push.
