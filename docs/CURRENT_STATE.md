# Current state and resume instructions

Updated 2026-10-09. This is the entry point for **“continue tasks from where we left off.”** Read it with repository-root AGENTS.md and the current Git state before choosing work. Durable repo files are authoritative; temporary tool sessions and chat memory are not required.

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

## Secure-exchange checkpoint

Native Secure exchange now pins one manually checked opposite-role public card and carries signed/encrypted CryptoKit HPKE envelopes. C++ retains ORX1 parsing, role/action authority, SQLite transactions, delivery facts and dedupe. Each key epoch has a separate UUID-named v2 store; keys and pinned cards persist in Keychain. Training and the explicit plain diagnostic remain separate. No plaintext fallback in secure mode.

[Walkthrough/evidence](../experiments/rescue-demo/SECURE_EXCHANGE.md) records 62/62 Swift checks, unchanged 30/30 sanitizer CTest and 14/14 Python harness checks, a reproducible real-Keychain/two-Mac-process loss/retry smoke scenario and signed native iPhone/iPad simulator-to-Mac workflows. Pairing, queued correction and explicit acknowledgment survive force-quit/reinstall and Mac restart without automatic networking. Reviews exposed/corrected unstable identity paths, stale cached packets and surviving keys with missing history. Missing keys/history fails closed; explicit new-session recovery rotates identity and requires re-pairing. All Claude calls used verified Opus 5.5/medium.

iOS keys use a stable app-scoped data-protection Keychain namespace, non-synchronizing WhenUnlockedThisDeviceOnly. Mac diagnostics deliberately use login Keychain, with weaker accessibility semantics, rather than silently falling back from a failed DP lookup. Simulator-only signing entitlements are configured; **do not disable signing** for native Keychain checks. Physical device signing needs the real development team. See the secure specification and ledger for platform/security decisions and remaining limits. One active owner per role/root; no cross-process Keychain CAS.

Preset synthetic data only. Saved bodies/old sample files are unencrypted; agency verification, encrypted storage, independent audit, physical lock/radio/older OS compatibility and forward secrecy remain unestablished. Existing measured loopback timings describe the plain baseline, not secure exchange.

## Relay foundation checkpoint — 2026-10-08

Reconstructed implementation was saved in Git at code checkpoint `c6da60b`, followed by reviewed file-safety hardening and the documentation checkpoint. Recovery used a persistent ignored project-local worktree and local Git checkpoints; design/recovery context is committed. The lost prototype's counts are historical. Fresh reconstructed verification:41/41 sanitizer CTest with fatal UBSan,67/67 Swift,14/14 Python harness,10 named encrypted CLI facts and signed native simulator build. Review found/reproduced a malformed-order counter overflow; comparison validation now rejects it safely. Failed-open descriptor lifetime, ordinary-prerequisite/urgent-follow-up and real crash-journal regressions pass. Claude review used verified Opus 5.5/medium; its file-safety finding was regraded and fixed. Minor follow-ups are recorded in the implementation plan.

[Relay walkthrough](../experiments/rescue-demo/RELAY_QUEUE.md) and [specification](superpowers/specs/2026-10-08-relay-queue.md) define the exact boundary. C++ owns separate SQLite custody,64 retained181...4276-byte items, eight-attempt budget, per-flow FIFO and persisted three-urgent/one-ordinary fairness. Swift copies/free bridge buffers. Queue accepts local trusted metadata and has no keys; runtime endpoint identities use actual CryptoKit and C++ endpoint stores in a process-local delayed-contact/reopen/lost-receipt/reverse-receipt scenario. It is not a relay listener, radio/network-isolation proof or native relay mode. Current Secure exchange/Training and both interfaces retain their existing behavior. Admission/deletion authentication, persistent stable-ID/sealed-retry mapping, routing and physical/private-data gates remain open. Logical `now` is signed64; expiry must be positive and later than now, with no accurate-clock guarantee.

## Signed relay network checkpoint — 2026-10-08

[Reproducible walkthrough](../experiments/rescue-demo/RELAY_NETWORK.md) establishes separate public, relay and responder Mac processes over explicit loopback sockets, with nonoverlapping endpoint contacts and no direct-send command. Eleven named facts cover refusal, killed-process restart, stable ciphertext/ID, lost response, one saved SOS, delayed reverse receipt, distinct human acknowledgment/reply and drained outboxes/custody. This is a sequential process topology on one Mac, not physical radio or OS firewall isolation.

C++ owns durable bounded custody, append-only endpoint cache and workflow state. Swift signs ORL1 routing/priority/expiry metadata, verifies ORA1 destination acceptance and correlates encrypted reverse receipts. The relay receives pinned public cards, not endpoint keys. ORC1 upload custody is untrusted and never clears the originating outbox. Mapping-bound ORF1 records prevent intact cache substitution; public ORG1 guards fail closed on cache loss. Expired/full caches require explicit new-session recovery and re-pairing, without deleting historical stores.

Fresh verification:43/43 sanitizer CTest with fatal UBSan,89/89 Swift tests,13/13 relay Python checks including actual hosts/11 facts and14/14 existing measurement-harness checks. Signed native simulator build passed. Updated iPad responder app retains its saved Secure exchange history with networking stopped. Native relay controls are not implemented yet; direct Secure exchange and Training remain available.

Claude Code used verified Opus 5.5 with explicit medium effort, implemented the core and fixed parent-reproduced integrity failures, then reached its session quota. The parent completed host/harness and hardening locally; independent read-only review found no remaining Critical/Important/Minor findings after fixes. No fallback model was configured. The committed spec and execution ledger retain the design and verification history; inspect Git before resuming.

## Native relay controls checkpoint — 2026-10-08

Both audiences now have a Direct/Via relay selector and shared manual host/port, listen, oldest-message upload and stop controls. The same secure identity/history/outbox survives route changes. Relay custody never advances delivery, actions never auto-upload, callbacks are fenced after stop/route/reset/reopen/role changes and networking never auto-starts. Cache recovery explicitly rotates/re-pairs and retains historical files. [Walkthrough and evidence](../experiments/rescue-demo/NATIVE_RELAY.md).

Fresh verification:96/96 Swift tests,43/43 fatal-UBSan CTest,13/13 relay Python checks with11 actual-process facts,14/14 measurement-harness checks and signed simulator app build. Tests use real C++ stores/crypto/sockets with test record stores. Read-only Claude review ran on verified claude-opus-5-5 with explicit medium effort. Its mixed-route delayed-receipt finding was reproduced, then fixed: an exact already-committed receipt can resolve its original through a read-only C++ lookup, still requiring the signed cached relay event and correct correlation. No wire/store format change or trust bypass.

At publication of8c41c82 the native trust exercise was pending. The user subsequently gave explicit approval; the attended native relay checkpoint below supersedes that blocker.

## Attended native relay checkpoint — 2026-10-08/09

On source8c41c82, compared full public fingerprints and paired the synthetic iPhone17 Pro public and iPad Pro11 M5 responder (iOS26.4) through normal UI. Four events (SOS, human acknowledgment, reply and Floor4 correction) and their four signed reverse receipts crossed the Mac relay in eight successful flushes. Observed public waiting after custody/forwarding, device-received only after reverse receipt, separate human acknowledgment and preserved conversations/location provenance. [Walkthrough](../experiments/rescue-demo/NATIVE_RELAY.md) and [structured manual evidence](../experiments/rescue-demo/native-relay-evidence.json).

Responder Home/return stopped listening and preserved history/trust. Public process restart with pending correction retained pairing/route/host/port/location/pending1 and stopped networking. An upload with relay absent failed without removing the original. Reopening the same Mac relay database with current endpoint ports allowed delivery/receipt recovery. Responder process restart retained the complete conversation and corrected location, networking stopped. Both app queues and relay custody ended zero. No code changes were needed. Existing automated/build counts above belong to the Oct8 code checkpoint, not a new benchmark.

Final local state: both project simulators remain open, paired, in Via relay, with synthetic history retained and networking stopped. The task's Mac relay was quit normally. Historical sample files were retained. No active task worktree or relay process is needed to resume; read Git rather than assuming a temporary binary/log still exists. Physical radio, OS isolation, background delivery and private-data gates remain unverified.

## Portfolio demo package — 2026-10-09

[Three-minute recruiter demo](PORTFOLIO_DEMO.md) packages the verified native workflow with signed-build/relay setup, a timed speaking script, optional refused-upload recovery, evidence links and scoped résumé wording. README links it directly. This is documentation derived from the existing evidence; no new native exercise or timing run is claimed.

## Signed-relay evaluation checkpoint — 2026-10-09

[Measured signed-relay evaluation](../experiments/rescue-demo/RELAY_MEASUREMENTS.md) and [raw evidence](../experiments/rescue-demo/evidence/2026-10-09-signed-relay-20-trials.json) record 20/20 complete actual-loopback scenarios,60 confirmed original SOS/ack/reply events and all 11 recovery facts in every trial. No failed/interrupted/not-run trials or cleanup failures. First versus duplicate custody and first versus repeated delivery are separate timing populations. SOS fault-recovery cycle median 353.823 ms includes deliberate failures, process restarts and scripted contact gaps; it is not radio/native latency or comparable to the plain direct baseline.

Python orchestration adds a child-factory seam to the existing smoke scenario; no Swift/C++/UI/protocol change. Fresh checks: 47/47 Python (no skips: 20 new + 13 relay + 14 plain), 96/96 Swift, 43/43 fatal-UBSan CTest. A separate independent audit reconstructed all summaries and 60 event/receipt-correlated intervals and matched 30 source hashes. Captured from clean source 5152edb; host/source hashes before/after match. Actual Claude Opus 5.5 with explicit medium effort reviewed design/code/fixes; follow-up found no remaining Critical/Important findings. Residual capture/cleanup/provenance limitations are in the report/ledger. Simulator GUI was absent during capture; no native rerun was needed or claimed.

## Presentation redesign checkpoint — 2026-10-09

The rejected two-picture history cut is superseded by the [64-second narrated explanatory demo](media/rescue-story.mp4), [editable Remotion source](../tools/demo-video/README.md), a visual README and redesigned native interfaces. Eight animated scenes explain the outage, SOS, opaque custody, delayed device receipt, explicit human acknowledgment/reply, retry/restart and measured scope. Scenes 1–7 are labeled workflow illustrations; scene 8 contains actual native simulator captures. Editorial timing is not measured latency. Manrope font/OFL and local Apple narration are bundled; no native production dependency was added.

Public request and responder workspace actions now have clearer cards, history and status hierarchy. Setup contains mode/role/pairing/route/manual connection/reset; connection, pending count, saved status and errors remain visible. Both audiences and workflow actions are retained. No transport, crypto, store or controller behavior changed; no automatic listening/upload/acknowledgment was introduced. Existing paired synthetic history survives installation/restart with networking stopped.

Fresh verification: signed simulator build succeeded; 96/96 Swift tests passed after final changes; video TypeScript check passed. Existing phone/tablet screens were visually inspected, and Setup → pairing → back → Done exercised without trust changes. Independent actual Claude Opus 5.5/medium review found ambiguous acknowledgment wording and draft loss on size-class changes; both were corrected, with draft bindings lifted to the shell. Dark mode, accessibility text sizes, empty state and runtime Split View were not exercised in this pass. Figma's earlier draft was not updated; implemented SwiftUI and current captures are the presentation checkpoint.

[Design/research and execution ledger](superpowers/plans/2026-10-09-presentation-redesign.md) records ownership and acceptance. Final media/link verification is recorded there. Inspect current Git state on resume; do not redo completed UI, networking or measurements.

## Active reference-led revision — 2026-10-09

The user rejected the published UI and 64-second slide/diagram film as well. Do not treat either as an accepted final presentation. Requested direction: inspect Appshots, Mobbin, Reprise, Dribbble SwiftUI, swiftui.design and latent-spaces/brag plus YouTube/Reddit; deliver polished native UI and a live product demo with purposeful motion. [Active plan and research](superpowers/plans/2026-10-09-live-product-redesign.md).

Claude CLI Opus 5.5/medium is revising only the three iOS view files; parent owns research/docs/video. CLI prompt/result live in ignored local-artifacts/live-redesign. Check process/result/modelUsage before starting another delegation. The user explicitly selected **Dark operational console**. Initial Claude prompt preceded that response; apply the dark-console follow-up before verification/publication. Preserve both audiences, all workflow actions and existing secure sessions. The app's transport/crypto/store layer is unchanged.

Capture blocker at task start: computer-use Chrome and IAB unavailable; native Simulator getApp failed with “Sky Computer Use native pipe startup failed.” simctl still lists both project simulators booted. Continue independent source/build/screenshot work; do not replace requested footage with another diagram film or fake delivery. Record fresh training interactions in a separate simulator when native control returns, explicitly label the simulated link and preserve existing secure peer history.

## Exact next action

The user reports owning an iPhone 17 and an iPad; the tablet model/OS and current physical availability remain unconfirmed. Prepare physical testing once both devices are available and their OS versions are known. The deployment target is iOS/iPadOS 18.0. First bounded checkpoint: signed synthetic direct SOS/device receipt/human acknowledgment/reply on a local network without internet, followed by disconnect/restart and lifecycle observations. Use the existing native setup instructions and record the physical evidence separately. No-shared-access-point transport requires a separate capability decision and physical check. Do not keep asking for hardware while it is unavailable.

An optional recording of actual live custody/device/human transitions remains distinct from the explanatory animation; see [portfolio script](PORTFOLIO_DEMO.md). Existing saved histories can be reviewed without reset. A fresh exercise requires coordinated explicit reset/re-pairing. Do not mark this live-recording task complete from animated illustrations.

Full physical, encrypted-storage, enrollment, independent-audit, device-compatibility and private-data gates remain open. AI, sensors and selling to agencies are deferred.

## Resume checklist

1. Read AGENTS.md, this file, current TODO portfolio section and latest decisions. Check branch, worktree status and recent commits; preserve user changes.
2. Confirm the current baseline with proportionate tests. Choose the next uncompleted portfolio task; do not rebuild completed milestones or treat old plans as fresh tasks.
3. Carry out the required pre-build loop, implement and verify the next coherent checkpoint. Physical checks wait for user availability; do not keep asking for hardware now.
4. Update this file, the relevant task/evidence entries and decisions after verification. Review ignore coverage and staged files, then use the existing authorization for a scoped public commit/push.

The remaining product documents describe the larger vision and evidence gates. Their aspirations are not current app capabilities; this file and linked measured evidence resolve that distinction.
