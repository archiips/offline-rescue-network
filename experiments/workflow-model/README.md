# C++ synthetic workflow model

Early domain engine prototype for **both** the public and responder workflows. Two independent C++20 instances exchange typed synthetic events in a deterministic command-line demonstration. This is separate from the Swift networking probe and has no radio, encryption, authenticated identity, wire serialization or durable storage in the domain Model. Its C ABI wrapper provides SQLite saved-session recovery, a bounded experimental binary codec and independently saved network endpoints. Its Swift package powers the [native rescue demo](../rescue-demo/README.md) and Mac exchange host. These wrappers do not add radio, persistence or serialization to the domain Model itself.

## Run

```sh
cmake -S experiments/workflow-model -B /private/tmp/rescue-workflow-build -DCMAKE_BUILD_TYPE=Debug
cmake --build /private/tmp/rescue-workflow-build
ctest --test-dir /private/tmp/rescue-workflow-build --output-on-failure
/private/tmp/rescue-workflow-build/workflow_demo
```

CMake >=3.20, C++20 compiler and system SQLite development library; no downloaded packages. The walkthrough demonstrates SOS, simulated device receipt, explicit acknowledgment, reply, outage correction, assignment/resolution, late withdrawal, withdrawal disposition and explicit reopen. Every event/actor/building is synthetic. A receipt means **in-memory model acceptance**, not production durable device receipt or a network measurement.

For sanitizer checks, configure another directory with `-DRESCUE_SANITIZERS=ON` and Debug; use Clang/GNU. Release uses the same checks (test assertions do not disappear under NDEBUG).

## Model contract

- `submit`: requires the local fixture author. `receive`: requires the local fixture destination. Neither updates the other model automatically.
- Events are immutable by ID; exact duplicates are idempotent, changed-content collisions reject. Per-author/request sequence collisions reject. A lower-sequence correction cannot overwrite a newer reported location.
- Supplied fixture roles, exercise, original requester ownership and exact receipt/acknowledgment reference are checked. **These are policy tests, not cryptographic authentication.** Anyone supplying the fixture data can impersonate a member.
- `receiptFor`: only for an already accepted inbound non-receipt event. Commit/transport are explicit harness steps; receipts never generate receipt loops. Each return message has independent delivery state. Snapshots expose **all** public messages with delivery per event plus an undelivered count; showing only the latest status can hide an earlier lost correction. Acknowledgment can precede a weaker device receipt without regressing.
- Single command authority; handling revisions increment by one. Resolution records observed public sequence; late updates, including delayed lower-sequence gaps, remain visible while resolved. Reopen requires an explicit reason. Withdrawal/disposition do not automatically resolve. Each disposition references an exact withdrawal; a later withdrawal has its own pending decision.
- Default 128 stored events, 64-byte IDs, 2 KiB combined text/location. Configured capacity is bounded at 4096. Full or injected failed store returns an error before mutation. Accepted events remain only in memory and are lost on process exit.
- Unknown request/reference or future revision returns `MissingDependency`; the caller must retry after the missing event. The endpoint wrapper persists pending originals and reserves receipt capacity. Production reconciliation, epochs and retention remain future work. Caller-provided deterministic IDs are not a production random-ID mechanism.

## Verification and limits

See [implementation plan](../../docs/superpowers/plans/2026-10-07-workflow-model.md). The tests cover the end-to-end synthetic workflow, independent delayed return delivery, late updates, fixture authority, references, storage failure, duplicates/conflicts, arrival order and bounds. This does not close NET-01, SEC-01, ENG-01–05 or M1. Native Swift integration is available as a synthetic training demo; physical connection testing can be done later.

### Projection interpretation

Interpret delivery from the **sending model**: requester delivery for public events, command delivery for its replies/handling messages. A receiver's locally created acknowledgment/receipt does not prove its return message reached the sender. The demo and tests keep these views separate.

`lateUpdate` is a **command-local review flag** based partly on acceptance order. The requester can have a different flag while still showing an undelivered correction. Replaying the same event set in a different arrival order may change that flag. The saved-session wrapper preserves acceptance order; future distributed replay must also preserve it or replace this with an explicit causal seen-event contract; do not promote this experiment to a convergent replicated reducer unchanged.

Verified 2026-10-07 on macOS arm64, AppleClang 21 and CMake 4.3.2: 13/13 CTest scenarios pass in Debug, Release and AddressSanitizer/UndefinedBehaviorSanitizer builds. Full demo ran successfully. Claude Code completed two read-only reviews; ordering, per-message and withdrawal regressions were reproduced and fixed. Declared minimum CMake/compiler portability beyond this machine is not validated.

The native-demo checkpoint added one C++ bridge test and 5 Swift integration tests. The saved-session checkpoint adds 10 CTest recovery scenarios and 5 Swift tests: **24 CTest checks and 10 Swift tests total**. The original 13-scenario baseline remains unchanged. See the [native demo README](../rescue-demo/README.md) for current commands, recovery evidence and limits.


## Local-endpoint checkpoint — 2026-10-08

The wrapper adds role-tagged v2 endpoint storage alongside unchanged v1 training sessions. Each endpoint owns only its local model; incoming events and deterministic receipts commit together. Confirmation commits a returned receipt and removes its corresponding pending original together. Retry regenerates the same saved receipt without duplicating the message. Recovery validates role, history, outbox order and reserved receipt capacity.

C++ binary packets validate UTF-8, canonical fixture IDs, lengths and field bounds; Swift adds bounded TCP framing. This is an experimental plain protocol with fixed exercise/request IDs, not authenticated private messaging. Reset must be coordinated on both endpoints. [Commands, current checks and evidence](../rescue-demo/LOCAL_EXCHANGE.md) cover the endpoint scenarios, real socket tests, separate processes and native simulator exchange. The original domain and training tests are retained.


The [repeated measurement harness](../rescue-demo/MEASUREMENTS.md) adds Python stdlib test orchestration around these unchanged C++ endpoints and Swift sockets. It validates raw results and persisted histories under controlled failures; it introduces no new backend or production dependency.
