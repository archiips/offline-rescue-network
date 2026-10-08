# Local exchange measurement and recovery harness

## Brief

One résumé-first rescue project retains public and responder interfaces, C++ state ownership and Swift networking. The next checkpoint makes local evidence reproducible without physical devices: fresh independent Mac endpoints, actual TCP loopback messages, controlled failures and inspectable timings. No app/engine/protocol behavior changes, private data, new dependencies, physical claims or performance targets.

## Discovery and approaches

Baseline code is `60cbf99`; current branch forks documentation checkpoint `83ba38a`. Existing process_exchange.py proves one workflow but uses unstructured text, retains temporary artifacts and has no repeated timing/failure report. ExchangeHost emits command STATE lines separately from INBOUND SAVED; each command is awaited serially, so no host API change is necessary. SQLite v2 stores expose acceptance-order rows in area0(public)/1(command) and pending rows in area2; read-only inspection can independently validate persisted counts/IDs.

Chosen: stdlib Python orchestrates existing Swift hosts with command timing and read-only database checks. A test-only loopback proxy delivers the same correction twice, compares returned receipt bytes and drops both responses before the public host restarts its direct retry. Rejected: C++-only microbenchmark (misses actual process/socket recovery); changing the host for machine-readable timing (avoidable app-adjacent scope); simulated latency/radio claims (not measured). Python is only test orchestration; the existing C++ engine still performs all state transitions and commits.

## Trial and measurement contract

Each of 1–100 trials has fresh stores and independent host processes. Send SOS, verify device receipt, explicitly submit acknowledgment/reply and deliver their two-message batch. Queue one correction, attempt a bound-but-not-listening port and prove transfer error plus retained outbox. Kill/relaunch public host; prove history and pending original match. Proxy forwards correction twice to responder, reads bounded framed receipts and verifies equality, but closes without returning a receipt to sender. Assert sender remains unconfirmed and responder history contains one correction. Retry directly, prove no duplicate history and empty outboxes on both sides. Exactly four original events exist on each endpoint at the end, along with four receipts: eight history rows, four message IDs and no pending originals.

Three metrics in milliseconds: sos_transfer, responder_return_batch, correction_retry. Start is immediately before writing a send command to stdin; stop is receipt of that command's STATE line after source confirmation. An untimed state probe catches trailing ERROR lines before allowing success. These measure orchestration + source/receiver durable commits + real loopback exchange + stdout/thread scheduling; SOS composition, manual acknowledgment delay, process startup and injected outage duration are excluded. Returning batch has two originals; never call it per-message latency. No warmup/excluded trials or latency pass threshold. Export every trial status/phase, observed faults/invariants and successful timings. Failed-trial partial timings stay raw but are excluded from the clearly labeled passed-trial summaries; requested/passed/failed counts and exit1 expose failures. Median and nearest-rank p95 with raw values and sample count, no interpolated confidence or general performance claim.

## Resource and evidence contract

Per-command timeout 12s; socket proxy reads at most4100 framed bytes, two deliveries only; stdout bounded per host; finite trials; child/thread/socket cleanup; fresh temporary directories removed after each trial. Persistent evidence contains no databases, absolute private paths, hostnames or credentials. Output publication is atomic and exclusive (existing path rejected before work, fully serialized temporary JSON linked without overwrite at completion); JSON version1, UTC timestamp, macOS/arch/Python/clock info, host executable SHA256, harness/source digests, git base revision/dirty indicator, metric definitions, raw trials and summaries. Timing clock is perf_counter_ns, statistics explicitly defined and unit tested. Invalid executable/trial/output arguments fail before launches.

## Acceptance / self-critique

Correctness: assert command STATE plus actual SQLite IDs, kinds/receipt relationships and outboxes; do not infer success from socket send or log text alone. Simplicity: no changes to production code or earlier smoke harness. Security: preset fixture data only, binds127.0.0.1, read-only DB inspection, no private telemetry. Maintainability: importable runner and stdlib unittest, explicit failure phases. Testing: pin percentile/empty/failure aggregation, malformed proxy frame, failed child EOF, real host trial, missing binary and output collision. UX: CLI prints per-trial progress and final summary, documents limits and reproducible commands. Preserve existing 30 CTest/33 Swift checks and native journeys; no UI change requires a new native render.

## Primary references — accessed 2026-10-08

- Python [time/perf_counter_ns](https://docs.python.org/3/library/time.html#time.perf_counter_ns): monotonic elapsed-time counter, integer nanoseconds; units are not a precision guarantee.
- Python [statistics](https://docs.python.org/3/library/statistics.html): median support; choose explicit nearest-rank p95 rather than default quantiles extrapolation for small samples.
- Anthropic [model overview](https://platform.claude.com/docs/en/models/overview): Opus 5.5 ID claude-opus-5-5. Local Claude help supports --effort medium. User explicitly requests these if Claude is used; no fallback model.
