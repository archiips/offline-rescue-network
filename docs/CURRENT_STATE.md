# Current state and resume instructions

Updated 2026-10-08. This is the entry point for **“continue tasks from where we left off.”** Read it with repository-root AGENTS.md and the current Git state before choosing work. Durable repo files are authoritative; temporary tool sessions and chat memory are not required.

## Goal and constraints

Build one impressive, working portfolio project: a public person sends an SOS and a responder receives, acknowledges and replies over an available local connection. Shared engine/backend logic stays C++20; native Apple UI and networking use Swift/SwiftUI. Retain both audiences. Commercialization is deferred. Use real measured results on the résumé; earlier estimates are not verification evidence.

The user cannot physically test now and authorized continued local development. iPhone 17 with approximately iOS 26 is reported; the older iPad is unavailable and its model/OS remain unknown. Simulator device names do not establish physical device ownership or compatibility. Figma draft is in Archit Jaiswal's team; recorded MCP quota prevented further refinement. Actual Claude Code CLI implementation/review is authorized, as are scoped commits/pushes to `archiips/offline-rescue-network`. No outreach, live deployment or private-data use follows from this authorization.

## Last completed code milestone

Published code checkpoint: `60cbf99a124dc92d9d9628f30039083750a46061` — independently saved local rescue endpoints and native exchange. Main was clean and remote matched after publication; check again on resume rather than assuming it remains unchanged. The task-created feature worktree/branch was removed after merge and push.

- Training mode: original two independent C++ models, simulated link, v1 SQLite saved session.
- Local exchange: one selected role/model and v2 SQLite outbox per app/CLI instance; real foreground sockets and Bonjour discovery.
- Receiver commits event + device receipt before returning success. Sender commits receipt + pending-original removal. Lost receipts retry idempotently; history reserves capacity for pending confirmations.
- Both interfaces support SOS, explicit acknowledgment/reply, correction and request handling. Mode/role/history survive restart; networking stays stopped. Background/stop invalidates callbacks and retains queues.
- Preset synthetic data, one fixed exercise/request, coordinated reset on both endpoints. Plain unauthenticated packets and unencrypted storage. No physical radio, encryption, background delivery, relay, AI or sensor estimate is established.

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
  -derivedDataPath /private/tmp/rescue-resume-derived CODE_SIGNING_ALLOWED=NO build
```

The separate-process harness and host commands are in the walkthrough. Read actual manifests before changing commands. Temporary databases/logs/screenshots are not required to resume; fixtures/tests reproduce the evidence. No benchmark numbers have been established.

## Exact next action

Continue the **device-independent measurement/recovery harness** entry at the top of [TODO](TODO.md). Inspect existing `tests/process_exchange.py`, endpoint tests, Swift transport tests and current docs first. Define a short plan and acceptance checks before implementation: repeated isolated sample trials, real local sockets, monotonic timing boundaries, controlled interruption/retry, duplicate checks and an export containing environment/trial counts/failures. Retain the current protocol/UI unless evidence requires a scoped fix. Synthetic results must identify their environment and cannot establish physical performance.

This is the next task, not an approved new architecture or completed harness. Decide details through the repository's Discover → Research → Plan → critique process. Use local code first, current official sources for material API/security uncertainty and the smallest coherent checkpoint. Physical testing need not block this work.

After that, plan security and relay/urgent scheduling as separate checkpoints. Do not jump to sales, AI, localization or broad infrastructure. NET-01, SEC-01, ENG-04 and M1 remain open because their full physical/private-product criteria exceed this demo. Keep original backlog criteria intact.

## Resume checklist

1. Read AGENTS.md, this file, current TODO portfolio section and latest decisions. Check branch, worktree status and recent commits; preserve user changes.
2. Confirm the current baseline with proportionate tests. Choose the next uncompleted portfolio task; do not rebuild completed milestones or treat old plans as fresh tasks.
3. Carry out the required pre-build loop, implement and verify the next coherent checkpoint. Physical checks wait for user availability; do not keep asking for hardware now.
4. Update this file, the relevant task/evidence entries and decisions after verification. Review ignore coverage and staged files, then use the existing authorization for a scoped public commit/push.

The remaining product documents describe the larger vision and evidence gates. Their aspirations are not current app capabilities; this file and linked measured evidence resolve that distinction.
