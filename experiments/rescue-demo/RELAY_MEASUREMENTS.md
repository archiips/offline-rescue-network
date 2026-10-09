# Signed-relay measurements and recovery evaluation

Captured 2026-10-09 UTC on one Apple Silicon Mac: **20/20 complete signed-relay recovery trials passed, with 60 confirmed original events (20 SOS, 20 human acknowledgments and 20 replies)**. No failed, interrupted or not-run trials; no filtering, warmup removal or trial retries. Every trial passed the existing eleven process/durability facts and three independently correlated confirmation intervals. This evaluates the existing Swift/C++ hosts over loopback; native UI and physical radio timings are outside this population.

[Raw JSON evidence](evidence/2026-10-09-signed-relay-20-trials.json) · [scenario and limits](RELAY_NETWORK.md) · [design/review ledger](../../docs/superpowers/plans/2026-10-09-signed-relay-evaluation.md) · [native demo package](../../docs/PORTFOLIO_DEMO.md)

## What the timings mean

One Python controller calls `perf_counter_ns` immediately before a host command and after `Child.command` has consumed and validated its STATE terminator. These are command-to-observed-result intervals, including Python scheduling, pipes, socket connection, cryptographic work, SQLite work and output validation. They are neither wire-only timings nor device commit timestamps. The existing CLI emits UPLOADED/FLUSH/errors before STATE.

- Custody response means an untrusted relay upload response; the originating outbox remains pending. Initial admission and idempotent re-upload are separate populations.
- A delivered-result flush includes destination processing and its signed acceptance. Initial ack/reply delivery and deduplicated SOS replay are separate populations. Receipt flushes carry the reverse device receipt, not a human acknowledgment.
- Confirmation cycles begin before the SOS/ack/reply action. The runner requires uploaded event ID E, delivered event E returning receipt R, delivered receipt R, then the correct source's pending=0 STATE. That final probe is later than actual receipt commit; these are observed cycle intervals, not exact commit latency.
- **SOS fault recovery includes** refused upload, relay/public process death and restart, an absent-responder flush, a dropped destination acceptance after commit, responder restart, exact ciphertext replay and delayed reverse receipt. Ack/reply cycles include process start/stop and deliberate nonoverlapping contacts but do not include those SOS faults. Do not compare them as equivalent operations.
- Whole-scenario time also includes fresh endpoint/Keychain setup, pairing, topology probes, final database assertions and owned-resource cleanup. Raw evidence retains 940 command records, 600 lifecycle records and per-fact elapsed checkpoints across the 20 trials.

The first-admission group pools three original kinds; first-delivery pools ack/reply; receipt delivery pools all three kinds. These mixed groups describe this scripted workload, not a message-size-controlled protocol benchmark. There is no fixed artificial contact-delay duration: restart/setup/probes impose the scripted gaps. No C++/Swift application, UI or protocol behavior changed.

## Results

Milliseconds, rounded here; raw JSON retains integer nanoseconds. P95 is nearest rank, sorted element ceil(0.95*n), one-based. At n=20 it is the second-largest observation; this sample does not establish a reliable tail bound.

| Population | n | Min ms | Median ms | P95 ms | Max ms |
|---|---:|---:|---:|---:|---:|
| First custody-response command (SOS/ack/reply pooled) | 60 | 8.427 | 12.141 | 15.456 | 17.752 |
| Duplicate SOS custody-response command | 20 | 6.360 | 7.333 | 9.176 | 9.553 |
| Upload command with relay absent | 20 | 6.544 | 8.748 | 9.445 | 9.576 |
| First delivered-result flush (ack/reply pooled) | 40 | 18.844 | 24.856 | 27.650 | 29.340 |
| Repeated SOS delivered-result flush after dropped acceptance | 20 | 15.613 | 19.147 | 23.425 | 25.734 |
| Reverse-receipt delivered-result flush (three kinds pooled) | 60 | 15.227 | 20.538 | 24.289 | 28.879 |
| SOS flush with destination acceptance deliberately ignored | 20 | 14.570 | 18.341 | 22.479 | 25.052 |
| Flush with responder absent | 20 | 3.072 | 3.719 | 4.378 | 5.582 |
| SOS scripted fault-recovery confirmation cycle | 20 | 336.281 | 353.823 | 384.513 | 385.207 |
| Acknowledgment scripted delayed-contact confirmation cycle | 20 | 142.170 | 168.189 | 178.293 | 184.558 |
| Reply scripted delayed-contact confirmation cycle | 20 | 135.429 | 175.316 | 185.092 | 190.726 |
| Whole scenario, including setup/cleanup | 20 | 1035.179 | 1129.657 | 1192.298 | 1194.812 |

Action-only queueing timings for SOS/ack/reply are also retained in JSON. All reported samples come from validated complete trials. `metric_coverage` exposes counts contributed by failed trials if any, and `incomplete_commands_by_action` records commands that fail before a valid result. This capture has zero such samples/commands. Partial failed/interrupt trials remain in output and force a nonzero exit; cleanup failure or interrupt stops further trials and preserves the not-run denominator. Interrupted cleanup is labelled unknown, not successful.

## Recovery outcomes

Each of the 20 scenarios retained the SOS after refused upload and absent-responder forwarding, preserved its ID/ciphertext across killed public/relay restart, retried the already committed SOS after a dropped acceptance/responder restart without creating a second SOS, and held the original pending until its reverse receipt returned. Acknowledgment and reply were separate events with their own delayed receipts. Both endpoint histories ended with six entries (three originals plus receipts); both outboxes and relay custody drained.

Totals: 20 refused uploads, 20 failed flushes, 20 deliberately ignored destination acceptances, 20 duplicate custody uploads and 20 deduplicated delivered-result SOS retries. There were 60 first-admission custody responses, 40 first delivered-result event flushes and 60 delivered reverse-receipt flushes. Expected injected failures are scenario checks, distinct from a failed trial. All recorded normal quits exited zero; test-owned Keychain and scratch cleanup completed in all trials. Contacts are sequential on one Mac, not OS/firewall isolation or separate physical devices.

## Reproduce

From the repository root, build a fresh Debug host without sanitizer flags. Swift/compiler-cache, loopback sockets and test-owned login-Keychain access are required:

```sh
swift build --package-path experiments/workflow-model \
  --scratch-path /private/tmp/rescue-signed-eval-swift --product rescue-relay-host
swift build --package-path experiments/workflow-model \
  --scratch-path /private/tmp/rescue-signed-eval-swift --show-bin-path
```

Use the executable inside the printed directory, replacing the placeholder below. Start from clean committed source. The output file must not exist and its parent directory must already exist. Keep builds and other test workloads out of the measured run.

```text
python3 experiments/workflow-model/tests/measure_relay.py --host /ABSOLUTE/BIN/PATH/rescue-relay-host --configuration debug --trials 20 --output /private/tmp/signed-relay-results.json
```

`--configuration` records the operator-declared build configuration; it does not inspect or attest the binary. `capture_valid` requires initially clean source and equal source/binary hashes before and after capture. A stale unrelated binary can still satisfy that hash check; use the fresh build above. Sudden process death or a second interrupt during result/publication serialization is not a crash-safe evidence journal. Exclusive publication preserves an existing file/symlink and exits nonzero on failure; there is no alternate-path publication.

Run regression checks with both built hosts configured (Swift tests build the executable products):

```sh
swift test --package-path experiments/workflow-model \
  --scratch-path /private/tmp/rescue-signed-eval-swift
```

```text
RESCUE_RELAY_HOST=/ABSOLUTE/BIN/PATH/rescue-relay-host RESCUE_EXCHANGE_HOST=/ABSOLUTE/BIN/PATH/rescue-exchange-host python3 -m unittest discover -s experiments/workflow-model/tests -p 'test_*.py'
```

Fresh verification: **47/47 Python checks, no skips** (20 measurement-runner, 13 relay-harness, 14 retained plain-measurement checks); **96/96 Swift**; **43/43 sanitizer CTest with fatal UBSan**. CMake commands remain in [current state](../../docs/CURRENT_STATE.md#evidence-and-commands); set `UBSAN_OPTIONS=halt_on_error=1` for CTest. New tests were observed failing before fixes. A separate one-trial instrumented preflight passed before the final capture; it is excluded from this 20-trial population. Claude's actual model metadata confirmed `claude-opus-5-5`, all calls explicitly medium effort, no fallback; final read-only follow-up found no remaining Critical/Important findings. Minor limits are recorded in the ledger.

## Capture provenance and independent audit

Raw source revision: `5152edbcd209f82b21ccea5e09f204e5b5ce1cdd`, clean worktree. Host was freshly built from unchanged Swift/C++ source with SwiftPM Debug, no sanitizer flags; its dependency list had no sanitizer runtime. Python 3.14.6, arm64, Apple Swift 6.3. The raw Python `platform.mac_ver()` value is empty; a separate `sw_vers -productVersion` check immediately after capture identified macOS **26.2**. The Swift target triple is not used as the OS version. Simulator GUI was absent at the pre-capture process probe; background services and system load were not controlled. Before/after load averages and clock resolution are in JSON.

- Host SHA256: `f1db51e30eb860efb56c5808634559a4ba7479bf6cb689423405b7cf6336545f`.
- Raw JSON SHA256: `cec0def4d72dc46929f15bac4e4a60ec076860c973f8335188499f2b5d6a48c1`.
- All 30 recorded Swift/C++/header/package/harness source hashes matched the checked-out source and their after-run values. This list does not hash the entire build toolchain or every ancillary input such as module maps.

An independent post-capture audit recomputed every population's n/min/median/nearest-rank p95/max, checked each command's elapsed value against its start/end, matched all 60 confirmation intervals to their event/receipt IDs and source-state probes, and checked all eleven facts, expected operation counts, successful lifecycle/cleanup and source/binary hash equality. No failed or slower trial was removed.

These are descriptive one-Mac loopback results for a synthetic workload. They establish neither physical offline exchange, background delivery, agency identity, encrypted local storage, native UI latency nor operational reliability. The [older plain direct measurements](MEASUREMENTS.md) use a different protocol/scenario and are not a speed comparison or baseline for these signed-relay cycles.
