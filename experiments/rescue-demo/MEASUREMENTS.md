# Reproducible local exchange measurements

The résumé-first project needs numbers supported by runnable evidence. This harness exercises the existing C++ state engine/SQLite stores and Swift Network socket host in independent Mac processes. Python is test orchestration only. It does not simulate successful delivery or change either app interface.

## Run

From the repository root:

```sh
swift build --package-path experiments/workflow-model \
  --scratch-path /private/tmp/rescue-measure-swift --product rescue-exchange-host
RESCUE_EXCHANGE_HOST=/private/tmp/rescue-measure-swift/arm64-apple-macosx/debug/rescue-exchange-host \
  python3 -m unittest discover -s experiments/workflow-model/tests \
  -p 'test_measure_exchange.py' -v
python3 experiments/workflow-model/tests/measure_exchange.py \
  --host /private/tmp/rescue-measure-swift/arm64-apple-macosx/debug/rescue-exchange-host \
  --trials 20 --output /private/tmp/rescue-measured-run.json
```

Use a new output path on each run; existing evidence is never overwritten. The executable path shown is for the verified Apple-silicon host. Trials accept 1–100, default 20. The command prints progress, writes all trial results and exits1 if any fails. Temporary sample databases/processes are cleaned after each trial; JSON is the durable evidence. Reports are written completely to a temporary file and published exclusively, so interrupted/invalid serialization cannot leave a partial result at the requested path.

## What each trial proves

Fresh independent public/responder processes exchange SOS and device receipt, then explicit human acknowledgment and reply. A correction is queued against a refused connection; the public process is killed/restarted with the same store. A bounded loopback proxy then delivers that original twice, verifies equal saved receipt bytes and discards the responses. The sender must remain unconfirmed, with the same outbox. Direct retry must clear it without changing the receiver's already committed history. Read-only database checks verify exact message/receipt IDs, references, role ownership and final empty outboxes, independently of displayed status.

Every successful trial ends with four original messages and four receipts in each endpoint history. These are two copies of the same four exchanged originals, not eight unique messages. The proxy is fault injection, not a product relay or multi-hop implementation.

## Timing definitions and reporting

All three timings start immediately before writing a send command to the source process's stdin and stop when its STATE response is observed after saving returned receipts. An untimed state probe then fences any trailing error output; a trial is successful only after those checks:

| Metric | What it includes | Excluded |
|---|---|---|
| SOS transfer | One original + receiver durable receipt + sender confirmation | SOS composition, startup/discovery |
| Responder return batch | Acknowledgment and reply, each with saved return receipt | Manual responder delay; not per-message latency |
| Correction retry | Direct retry after receiver already saved the original | Refused connection, process restart and dropped-receipt duration |

Measurements include stdin/stdout, process/thread scheduling and local SQLite commit overhead. They are Mac loopback results, not C++ microbenchmarks, native phone latency or physical radio performance. No warmups or slow trials are removed. Raw successful/failed trial records stay in JSON; aggregate timing statistics use only fully passed trials and say so. Median and nearest-rank p95 include sample counts and extrema; an empty population has null metrics. Nanosecond clock units do not promise nanosecond accuracy.

Environment/provenance includes UTC capture date, macOS version, architecture, Python, monotonic clock resolution, executable SHA256, source digests and Git base revision/dirty status. It omits username, hostname, private paths and database files. The host is explicitly built before measurement; hashes identify the actual executable and inspected sources, rather than asserting an unverified build configuration.

[Design and primary timing sources](../../docs/superpowers/specs/2026-10-08-measurement-harness.md) · [Implementation/review ledger](../../docs/superpowers/plans/2026-10-08-measurement-harness.md).


## Verified capture — 2026-10-08

[Raw 20-trial evidence](evidence/2026-10-08-loopback-20-trials.json) records **20/20 passed**, zero failures and80 confirmed original-message transfers across20 fresh sample sessions. Every trial verified refused-connection retention, killed-process outbox recovery, duplicate receipt equality, an unconfirmed sender after lost response and duplicate-free direct retry. Each trial's final histories and checks remain inspectable.

| Command-to-confirmation metric | Trials | Median (ms) | Nearest-rank p95 (ms) | Maximum (ms) |
|---|---:|---:|---:|---:|
| SOS transfer | 20 | 7.76 | 10.86 | 11.01 |
| Acknowledgment + reply batch | 20 | 13.28 | 16.31 | 19.01 |
| Correction retry | 20 | 7.92 | 17.97 | 28.55 |

Captured on macOS , arm64, Python 3.14.6, using the SwiftPM Debug host built for this checkpoint. The raw metadata records base revision `83ba38a` with dirty_worktree=true because this harness was under development. Committed source SHA256 values were independently checked against that record; the executable's own SHA256 identifies what actually ran. Raw values retain full precision. These are descriptive measurements from one development machine, not a promised performance threshold or physical device benchmark.

14/14 Python harness tests pass with the real host configured, alongside unchanged 30 CTest and 33 Swift checks. Actual Claude Opus 5.5 review ran at medium effort; follow-up found no blockers. The original process smoke also passes. No native UI or production C++/Swift code changed, so the earlier rendered journey evidence remains applicable.

Run history: a preliminary pre-reporting-fix 20-trial run passed but is not the capture above. A subsequent capture was interrupted by a daemon restart before publishing its report. After confirming no report or child processes remained, the final 20-trial run was restarted with fresh stores and completed. No trials from a completed report were removed for slowness/failure. Expected trial failures are retained and cause exit1; an external interruption is not a completed report.

Current limits: loopback only, foreground host, fixed synthetic roles/request, plain protocol and storage. A rare cleanup failure can replace the earlier failure reason; it still fails the trial. Source fingerprints cover the current flat Swift target; revisit traversal if nested source directories are added. Exclusive hard-link publication is verified on this Mac filesystem; other filesystems may reject publication.
