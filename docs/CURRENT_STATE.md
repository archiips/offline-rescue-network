# Current state and resume instructions

Updated 2026-10-08. This is the entry point for **“continue tasks from where we left off.”** Read it with repository-root AGENTS.md and the current Git state before choosing work. Durable repo files are authoritative; temporary tool sessions and chat memory are not required.

## Goal and constraints

Build one impressive, working portfolio project: a public person sends an SOS and a responder receives, acknowledges and replies over an available local connection. Shared engine/backend logic stays C++20; native Apple UI and networking use Swift/SwiftUI. Retain both audiences. Commercialization is deferred. Use real measured results on the résumé; earlier estimates are not verification evidence.

The user cannot physically test now and authorized continued local development. iPhone 17 with approximately iOS 26 is reported; the older iPad is unavailable and its model/OS remain unknown. Simulator device names do not establish physical device ownership or compatibility. Figma draft is in Archit Jaiswal's team; recorded MCP quota prevented further refinement. Actual Claude Code CLI implementation/review is authorized, as are scoped commits/pushes to `archiips/offline-rescue-network`. No outreach, live deployment or private-data use follows from this authorization.

## Earlier plain local-exchange milestone

Native exchange code checkpoint: `60cbf99a124dc92d9d9628f30039083750a46061` — independently saved local rescue endpoints and native exchange. The subsequent measurement harness/evidence lives in the current repository; use recent Git history for its publication commit. Main was clean and remote matched after publication; check again on resume rather than assuming it remains unchanged. The local-exchange task-created worktree/branch was removed after merge and push. Measurement publication/cleanup is reported by its Git history/task handoff; check current worktrees on resume.

- Training mode: original two independent C++ models, simulated link, v1 SQLite saved session.
- Local exchange: one selected role/model and v2 SQLite outbox per app/CLI instance; real foreground sockets and Bonjour discovery.
- Receiver commits event + device receipt before returning success. Sender commits receipt + pending-original removal. Lost receipts retry idempotently; history reserves capacity for pending confirmations.
- Both interfaces support SOS, explicit acknowledgment/reply, correction and request handling. Mode/role/history survive restart; networking stays stopped. Background/stop invalidates callbacks and retains queues.
- This earlier diagnostic remains plain and uses fixed exercise/request IDs. Current native Secure exchange wraps its C++ packets as described below. No physical radio, background delivery, relay, AI or sensor estimate is established; SQLite sample storage remains unencrypted.

## Evidence and commands

[Local walkthrough and evidence](../experiments/rescue-demo/LOCAL_EXCHANGE.md) records 30/30 CTest checks in sanitizer/Release, 33/33 Swift tests, separate Mac-process recovery, iPhone/iPad simulator-to-Mac rescue workflows and a successful native build. [Local design](superpowers/specs/2026-10-08-local-exchange.md) and [execution ledger](superpowers/plans/2026-10-08-local-exchange.md) explain the implementation and review fixes. Earlier checkpoint docs remain historical evidence.

Run from the repository root with fresh task-specific scratch directories:

```sh
cmake -S experiments/workflow-model -B /private/tmp/rescue-resume-cmake \
  -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON
cmake --build /private/tmp/rescue-resume-cmake
ctest --test-dir /private/tmp/rescue-resume-cmake --output-on-failure
swift test --package-path experiments/workflow-model \
  --scratch-path /private/tmp/rescue-resume-swift
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj \
  -scheme RescueDemo -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rescue-resume-derived CODE_SIGNING_ALLOWED=YES build
```

The separate-process harness and host commands are in the walkthrough. Read actual manifests before changing commands. Temporary databases/logs/screenshots are not required to resume; fixtures/tests reproduce the evidence. Measured Mac loopback command-to-confirmation values are now recorded in [measurements](../experiments/rescue-demo/MEASUREMENTS.md); no physical benchmark is established.

## Last completed measurement checkpoint

The stdlib Python harness runs existing Swift/C++ hosts with real loopback sockets and fresh SQLite endpoints. 20/20 trials passed with 80 confirmed original-message transfers. Every trial validated explicit acknowledgment/reply, refused connection, killed-process restart, duplicated correction/lost receipt and exact retry recovery. 14/14 harness tests pass; original 30 CTest/33 Swift checks are retained. [Report and raw evidence](../experiments/rescue-demo/MEASUREMENTS.md) define the timing populations, limits and independently verified hashes. Python is test orchestration, not a new backend. No product/UI/protocol behavior changed.

Claude Code preference: if used, explicitly request `--model claude-opus-5-5 --effort medium`, no fallback. The review's model metadata confirmed Opus 5.5; follow-up found no blockers. This preference is also in AGENTS.md.

## Latest secure-exchange checkpoint

Native Secure exchange now pins one manually checked opposite-role public card and carries signed/encrypted CryptoKit HPKE envelopes. C++ retains ORX1 parsing, role/action authority, SQLite transactions, delivery facts and dedupe. Each key epoch has a separate UUID-named v2 store; keys and pinned cards persist in Keychain. Training and the explicit plain diagnostic remain separate. No plaintext fallback in secure mode.

[Walkthrough/evidence](../experiments/rescue-demo/SECURE_EXCHANGE.md) records 62/62 Swift checks, unchanged 30/30 sanitizer CTest and 14/14 Python harness checks, a reproducible real-Keychain/two-Mac-process loss/retry smoke scenario and signed native iPhone/iPad simulator-to-Mac workflows. Pairing, queued correction and explicit acknowledgment survive force-quit/reinstall and Mac restart without automatic networking. Reviews exposed/corrected unstable identity paths, stale cached packets and surviving keys with missing history. Missing keys/history fails closed; explicit new-session recovery rotates identity and requires re-pairing. All Claude calls used verified Opus 5.5/medium.

iOS keys use a stable app-scoped data-protection Keychain namespace, non-synchronizing WhenUnlockedThisDeviceOnly. Mac diagnostics deliberately use login Keychain, with weaker accessibility semantics, rather than silently falling back from a failed DP lookup. Simulator-only signing entitlements are configured; **do not disable signing** for native Keychain checks. Physical device signing needs the real development team. See the secure specification and ledger for platform/security decisions and remaining limits. One active owner per role/root; no cross-process Keychain CAS.

Preset synthetic data only. Saved bodies/old sample files are unencrypted; agency verification, encrypted storage, independent audit, physical lock/radio/older OS compatibility and forward secrecy remain unestablished. Existing measured loopback timings describe the plain baseline, not secure exchange.

## Exact next action

Continue the **bounded relay/disruption demonstration and urgent-message scheduling** portfolio task in [TODO](TODO.md), as a separately researched/designed checkpoint. Start with the secure envelope, fixed inner IDs, saved outbox and retry invariants. Define an isolated public→relay→responder topology and return path, enforce that the relay has no endpoint decryption keys, bound hops/retries/storage and prove urgent scheduling without starving messages or losing receipt dependencies. Compare queue/transport approaches using local code and current primary sources, write and critique a plan before building. Do not assume the current direct-only UI already relays.

Keep both interfaces, the C++ engine, training mode and synthetic-data restriction. Physical testing can still wait. Full NET-01/SEC-01/ENG-05/product gates remain open. Avoid sales, AI, localization and unrelated infrastructure as immediate prerequisites for the résumé deliverable.

## Resume checklist

1. Read AGENTS.md, this file, current TODO portfolio section and latest decisions. Check branch, worktree status and recent commits; preserve user changes.
2. Confirm the current baseline with proportionate tests. Choose the next uncompleted portfolio task; do not rebuild completed milestones or treat old plans as fresh tasks.
3. Carry out the required pre-build loop, implement and verify the next coherent checkpoint. Physical checks wait for user availability; do not keep asking for hardware now.
4. Update this file, the relevant task/evidence entries and decisions after verification. Review ignore coverage and staged files, then use the existing authorization for a scoped public commit/push.

The remaining product documents describe the larger vision and evidence gates. Their aspirations are not current app capabilities; this file and linked measured evidence resolve that distinction.
