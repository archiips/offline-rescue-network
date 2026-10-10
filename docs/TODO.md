# Detailed task backlog

Status: product backlog with portfolio execution status · updated 2026-10-10

Start with [current state and resume instructions](CURRENT_STATE.md). The sections below retain the full product/pilot requirements; their unchecked boxes do not mean the bounded demo has no implementation. Owner labels are roles, not assigned people. Do not close a production task from synthetic or simulator evidence alone.

## Current portfolio tasks

The user prioritized a working résumé project and deferred commercialization and physical testing. One project retains public and responder interfaces, a C++ engine and Swift native adapters. These checkpoints are separate from the broader gated tasks below.

- [x] Shared C++ workflow with independent public/responder state, delivery versus human acknowledgment, location correction and handling actions. Evidence: [workflow model](../experiments/workflow-model/README.md).
- [x] Runnable native public/responder training UI. Evidence: [native demo](../experiments/rescue-demo/README.md), inspected phone/tablet simulator layouts.
- [x] Durable training session and queued-transfer recovery. Evidence: [saved-session checkpoint](../experiments/rescue-demo/README.md#saved-session-checkpoint--2026-10-07).
- [x] Independently saved local endpoints, bounded packet codec, Bonjour/socket adapter, native local mode and Mac host. Evidence: [local exchange](../experiments/rescue-demo/LOCAL_EXCHANGE.md), 30 CTest / 33 Swift checks, separate processes and simulator-to-Mac exchange; code checkpoint `60cbf99` published.
- [x] Reproducible synthetic measurement/recovery harness around existing independent endpoints. Evidence: [measurement report](../experiments/rescue-demo/MEASUREMENTS.md), 20/20 completed actual-loopback trials, 80 confirmed original-message transfers, 14/14 Python checks and exact database/receipt invariants. Raw timings, environment, hashes and all outcomes are committed; no physical radio claim.
- [ ] Physical direct-exchange matrix when the user can test: signing/install, Local Network permission allow/deny, exact OS/device versions, no-internet and no-common-access-point variants, disconnect/reconnect and lifecycle limits. Depends on physical availability; NET-01 remains open.
  - 2026-10-10: iPad no longer available; user deferred retesting until a later updated version. Do not block registration/trusted-discovery design on hardware. Automatic direct exchange is locally verified at `61a191e`, not installed/physically retested. When hardware returns, install the latest verified build and test automatic delivery without Transfer, then no-internet/recovery and separate no-common-access-point conditions. Earlier screenshots prove only a functional round trip on internet-connected Wi-Fi.
- [x] Reviewed identity/encryption design and bounded encrypted local sample exchange. Evidence: [secure exchange](../experiments/rescue-demo/SECURE_EXCHANGE.md),62 Swift checks, real-Keychain independent Mac process recovery, signed native iPhone/iPad pairing/SOS/ack/reply and missing-history/stale-epoch regression fixes. C++ owns business state and persistence; Swift CryptoKit supplies Apple-only crypto. Manual trust is not agency enrollment; SQLite remains unencrypted. SEC-01/ENG-05 and private-data gates remain open.
- [x] Durable opaque relay custody foundation, priority/FIFO scheduling and encrypted process-local delayed-contact scenario. Evidence: [relay walkthrough](../experiments/rescue-demo/RELAY_QUEUE.md), 41 sanitizer CTest / 67 Swift / 14 Python checks, 10 encrypted CLI facts and signed native build. Trusted local metadata only; no relay listener or native relay controls.
- [x] Signed separate-Mac-process relay exchange with exact encrypted retries, durable mapping-bound cache and delayed reverse receipts. Evidence: [relay network](../experiments/rescue-demo/RELAY_NETWORK.md),43 sanitizer CTest /89 Swift /13 relay Python checks,11 actual-process facts,14 retained measurement-harness checks and signed native build. Sequential loopback contacts only; physical/OS isolation and full NET-03/ENG-07 remain open.
- [x] Explicit native relay controls for both audiences: manual route/address/listen/upload, truthful custody/device/human states, saved-session recovery and stale-result fencing. Evidence: [native relay](../experiments/rescue-demo/NATIVE_RELAY.md),96 Swift /43 fatal-UBSan CTest /13 relay Python /14 measurement checks and signed native build. Phone/tablet controls inspected; controller tests use test record stores, not iOS Keychain.
- [x] Controlled foreground native relay host: checked public cards, pair-bound saved custody, manual forwarding, stop fences and restart/background behavior. Evidence: [phone relay](../experiments/rescue-demo/PHONE_RELAY.md),106 Swift Testing +4 XCTest /43 sanitizer CTest / signed simulator build and attended native-host SOS/receipt/ack/reply with held-reply restart recovery. Simulator/Mac loopback only; arbitrary mesh and physical gates remain open.
- [x] Attended native iPhone/iPad-to-Mac relay SOS/device receipt/human acknowledgment/reply/correction, native restart/background-stop checks and rendered conversation inspection. Explicit user approval received; normal UI pairing completed on both sides. Four events/eight successful forwards, refused-upload retention, queued correction recovery and drained queues observed. Evidence: [native walkthrough](../experiments/rescue-demo/NATIVE_RELAY.md) and [manual observation record](../experiments/rescue-demo/native-relay-evidence.json). Simulator loopback only; physical/product gates stay open. Follow [resume instructions](CURRENT_STATE.md#exact-next-action) for the next bounded portfolio checkpoint.
- [x] Package a short reproducible recruiter-facing demo from the verified native walkthrough. Evidence: [three-minute demo package](PORTFOLIO_DEMO.md), setup/command references, recovery extension, claim boundaries and résumé wording. Documentation checkpoint only; no new native run or performance measurement.
- [x] Design and run a measured signed-relay evaluation with explicit timing populations, failure cases, raw evidence and scope limits. Evidence: [signed-relay report](../experiments/rescue-demo/RELAY_MEASUREMENTS.md),20/20 complete trials, 60 ID-correlated original confirmations, 47 Python /96 Swift /43 fatal-UBSan CTest checks. First/duplicate custody and first/repeat forwarding are separate; plain direct timings remain separate.
- [ ] Optional short native screen recording from the [portfolio script](PORTFOLIO_DEMO.md), preserving both audiences and showing custody versus device receipt versus human acknowledgment. Use existing approved synthetic peers or explicitly reset/re-pair for a fresh exercise; no physical-radio claim.
  - A [30-second saved-session review](../experiments/rescue-demo/evidence/2026-10-09-native-history-review.mp4) is captured and verified: both native audiences, saved acknowledgment/receipt facts and reported-floor provenance, networking stopped. Full live custody/device/human transitions are not recorded in this cut, so this entry remains open.
  - 2026-10-09: [64-second narrated motion explainer](media/rescue-story.mp4), [source](../tools/demo-video/README.md), native UI hierarchy redesign and visual README implemented; user subsequently rejected this visual treatment/film. Illustrations explain transitions but do not satisfy the optional live-recording criterion.
  - Later 2026-10-09: user selected dark operational console. Revised native UI signed-build/96-controller/static screenshot checks pass. [Actual-footage capture plan](../tools/demo-video/LIVE_CAPTURE.md) is prepared; native computer-use startup failure blocks interaction recording. No replacement video produced; entry stays open.
  - 2026-10-09 motion edit: [44-second actual native demo](media/rescue-live.mp4) rendered with eased camera framing and captions; review/send → queue → simulated-link restore → device receipt → acknowledgment/reply. TypeScript/render/full decode and sampled-frame review pass. Full export playback still blocked by Computer Use player errors. Training footage does not prove actual relay custody; broader optional entry remains open.
- [x] Bounded live cooperative input adapters: local connected-network context, original foreground sensor readings, independently paired encrypted explicit phone pulls and live contact-only graph. [Evidence](../experiments/rescue-demo/LIVE_COOPERATIVE_INPUTS.md):153 Swift Testing +6 XCTest /53 sanitizer checks /signed Simulator build and rendered UI review. UW reference mapping, physical accuracy and LOC-01 remain open.
- [x] Cooperative floor graph foundation: bounded C++ constraints/provenance/expiry, Swift matched synthetic replay and shared native research screen. [Evidence](../experiments/rescue-demo/COOPERATIVE_FLOOR_GRAPH.md):53 sanitizer CTest /119 Swift Testing +6 XCTest /6 Release graph checks /signed build and native fixture review. Live Wi-Fi/phone inputs, physical accuracy and LOC-01 remain open.
- [x] Automatic floor research prototype: foreground Apple-floor capture, bounded C++ anchored-relative inference, stable calibration/Unknown behavior and isolated synthetic fixtures. Evidence: [floor research](../experiments/rescue-demo/FLOOR_RESEARCH.md),111 Swift Testing +6 XCTest /47 sanitizer CTest /signed build and native lifecycle/source checks. Real sensor/floor accuracy, UW Wi-Fi and LOC-01 remain open.
- [ ] Optional on-device translation/summarization after message fidelity and measured local inference. Automatic floor detection is an explicit planned research milestone; see [UW localization progression](UW_LOCALIZATION_ROADMAP.md).
- [ ] Commercial/partner discovery, sales, public distribution and operational use are deferred. Outreach needs explicit authorization.

Read [PRD](PRD.md), [decisions](DECISIONS.md) and [validation](VALIDATION.md) for the longer-term requirements. Experimental build commands are established in the linked experiment READMEs; production packaging/lint and physical/private-data gates are not complete. Preserve the original task definitions and dependencies below.

## M0 — documentation and discovery

### DOC-01 — Initial documentation package

- [x] **Owner:** project lead · **Priority:** P0 · **Dependencies:** none.
- **Work:** write the overview, product requirements, architecture, system design, localization experiments, business hypotheses, security/privacy, validation, roadmap, source register, decision register, and this backlog.
- **Deliverable:** linked Markdown package plus project operating instructions.
- **Done when:** local links resolve; product scope is consistent; sourced claims and assumptions are distinguished; no product code exists; review against the user's requested areas is recorded.
- **Evidence (2026-10-07):** inline Python documentation audit passed for 13 Markdown files, 45 local links/anchors, 40 defined tasks with an acyclic dependency graph and completion criteria, and 19 source entries. Scope review covered PRD, architecture/design, detailed tasks, research, business/adoption, privacy, pilot validation, and the accepted dual-interface workflow. Only Markdown files exist; no application tests were run because there is no implementation. All other tasks remain unchecked.

### DISC-01 — Observe the operator problem

- [ ] **Owner:** product/business lead · **Priority:** P0 · **Dependencies:** DOC-01.
- **Work:** with explicit outreach authorization, conduct the discovery conversations in BUSINESS.md; include public-role users, responders, training officers, and budget stakeholders. Ask about actual situations and alternatives.
- **Deliverable:** redacted interview synthesis with supporting and contradictory evidence.
- **Done when:** a specific workflow, operator, and current workaround are identified; assumptions requiring further investigation are named; no adoption claims rely only on enthusiasm.

### DISC-02 — Inventory physical devices and environment

- [ ] **Owner:** engineering lead · **Priority:** P0 · **Dependencies:** DOC-01.
- **Work:** list available iPhone/iPad/laptop models, OS versions, sensor/radio capabilities, provisioning access, test-building permission, and acquisition constraints.
- **Deliverable:** device/environment matrix and test inventory.
- **Done when:** at least the proposed two-endpoint drill can be tested on physical devices; missing equipment is explicitly recorded rather than assumed.

### DISC-03 — Public readiness and responder reachability

- [ ] **Owner:** product + networking + security · **Priority:** P0 · **Dependencies:** DISC-01, DISC-02.
- **Work:** map installation, exercise enrollment, verified responder discovery, local topology, return paths, and people responsible for handling requests.
- **Deliverable:** deployment journey for both audiences and a gap register for open public use.
- **Done when:** the controlled drill has a reachable enrolled responder and a tested enrollment process; no arbitrary nearby department or universal public onboarding is presumed.

### NET-01 — Select the baseline local transport

- [ ] **Owner:** networking lead · **Priority:** P0 · **Dependencies:** DISC-02.
- **Work:** review current Apple guidance; compare foreground Multipeer Connectivity, appropriate Network/Wi-Fi Aware options, BLE, and optional LAN. Use a minimal synthetic-data probe; record discovery, direct transfer, reconnection, lock/background, pairing, and no-internet behavior.
- **Deliverable:** physical evidence matrix and a decision record with chosen adapter, OS/device support, limitations, and fallback.
- **Done when:** a direct no-internet round trip works on the target devices and constraints are documented; revise D-08/D-09 if necessary before M1 implementation.

### SEC-01 — Freeze identity and private-envelope design

- [ ] **Owner:** security + systems lead · **Priority:** P0 · **Dependencies:** DOC-01, NET-01.
- **Work:** choose reviewed libraries/constructions; document role provisioning, command/public reply keys, authenticated metadata, storage protection, replay behavior, dependency/license/version, revocation limits, and failure handling.
- **Deliverable:** security design record, review notes, interoperability/test-vector requirements.
- **Done when:** every trusted-state mutation has an authority check; relays cannot read private bodies; no invented cryptographic primitive is required. Gate private data until complete.

## M1 — complete direct SOS and acknowledgment loop

### ENG-01 — Establish the actual project toolchain

- [ ] **Owner:** engineering lead · **Priority:** P0 · **Dependencies:** NET-01, SEC-01.
- **Work:** create the smallest C++20 library, Apple client workspace, and test configuration during implementation; choose compiler/Xcode/dependencies; record real build, tests, lint, and packaging commands. Establish ignore coverage before any commit.
- **Deliverable:** reproducible local development setup and command documentation.
- **Done when:** an independent clean setup builds both client shells and the shared core; checks use manifests rather than guessed commands; no unrelated infrastructure is introduced.

### ENG-02 — Version the protocol and fixtures

- [ ] **Owner:** systems lead · **Priority:** P0 · **Dependencies:** SEC-01, ENG-01.
- **Work:** freeze schema/serialization, IDs, event kinds, sequence/epoch rules, role binding, message-to-request references, limits, version rejection, units, timestamp quality, and malformed-input behavior from SYSTEM_DESIGN.md.
- **Deliverable:** versioned interface/wire specification and golden fixtures.
- **Done when:** encode/decode interoperability, unsupported-version, same-ID conflict, oversized-input, and missing-required-field checks are defined and passing; fixtures contain synthetic data only.

### ENG-03 — Prove the Swift/C++ boundary

- [ ] **Owner:** client + core lead · **Priority:** P0 · **Dependencies:** ENG-01, ENG-02.
- **Work:** implement the thin bridge with explicit ownership, asynchronous engine executor, cancellation, and immutable UI snapshots.
- **Deliverable:** shared core callable from both app interfaces.
- **Done when:** concurrency/lifetime tests cover teardown during callbacks; the UI remains responsive; native adapter code does not duplicate engine business state.

### ENG-04 — Implement durable events and delivery facts

- [ ] **Owner:** core lead · **Priority:** P0 · **Dependencies:** ENG-02, ENG-03.
- **Work:** implement transactional submission/inbound commit, outbox recovery, event union/deduplication, and separate delivery/handling projections.
- **Deliverable:** recoverable engine store and state reducer.
- **Done when:** restart, duplicate, out-of-order, missing-predecessor, same-ID conflict, storage-full, and newer-follow-up cases pass; no receipt is sent before commit.

### ENG-05 — Implement endpoint security and enrollment

- [ ] **Owner:** security + client lead · **Priority:** P0 · **Dependencies:** SEC-01, ENG-03, ENG-04.
- **Work:** implement provisioning and role checks, key storage, reviewed envelope operations, authenticated receipts, exercise isolation, local exercise closure, and the documented retention/deletion policy.
- **Deliverable:** enrolled identities and endpoint-private exchange.
- **Done when:** unknown/wrong-role/wrong-exercise/forged/replayed events cannot create trusted statuses; plaintext key/body leakage checks and V-15 pass; error messages preserve the manual workflow.

### ENG-06 — Implement direct local exchange

- [ ] **Owner:** networking lead · **Priority:** P0 · **Dependencies:** NET-01, ENG-02, ENG-04, ENG-05.
- **Work:** implement the chosen adapter's discovery/session lifecycle, bounded transfer, reconnect, engine callbacks, and exact-message device receipts.
- **Deliverable:** direct device-to-device event exchange.
- **Done when:** no-internet request and receipt traverse physical devices; send completion is not treated as endpoint delivery; permission/session failures are visible.

### APP-01 — Build the public request journey

- [ ] **Owner:** Swift/client lead · **Priority:** P0 · **Dependencies:** ENG-03, ENG-04, ENG-05.
- **Work:** implement verified exercise join, manual request/review/send, optional location permission, delivery facts, replies, correction, withdrawal, and disconnected/error states.
- **Deliverable:** usable public iPhone interface.
- **Done when:** the complete journey works without sensor permission; an uncommitted request is not shown as queued; no receipt fabricates help dispatch; large text/VoiceOver semantics are checked.

### APP-02 — Build the responder handling journey

- [ ] **Owner:** Swift/client lead · **Priority:** P0 · **Dependencies:** ENG-03, ENG-04, ENG-05.
- **Work:** implement authorized exercise access, list/detail, reported location/provenance, device receipt versus human action, acknowledgment/reply, assignment, resolution, late updates, and coordinator-authorized local drill closure.
- **Deliverable:** usable responder iPad interface.
- **Done when:** a public/relay role cannot perform responder actions; users can distinguish reported versus estimated/unknown location and acknowledgment versus assignment.

### APP-03 — Join both interfaces in a direct drill

- [ ] **Owner:** integration lead · **Priority:** P0 · **Dependencies:** ENG-06, APP-01, APP-02.
- **Work:** connect the full local workflow; exercise correction/withdrawal and returning human acknowledgment/reply; inspect physical rendered states.
- **Deliverable:** first end-to-end public/responder demonstration.
- **Done when:** V-01, V-02, V-03, V-05, and V-07 pass physically with the original request preserved across both interfaces.

### UX-01 — Validate comprehension of statuses

- [ ] **Owner:** product/design lead · **Priority:** P0 · **Dependencies:** APP-03.
- **Work:** run formative tasks with public and responder participants; test large text and VoiceOver; ask what each delivery/handling state means.
- **Deliverable:** interaction findings and revised copy/screens where needed.
- **Done when:** no observed UI wording falsely implies responder receipt or dispatched help; unresolved confusions are either corrected and retested or block the drill release.

### QA-01 — Verify the M1 milestone

- [ ] **Owner:** validation lead · **Priority:** P0 · **Dependencies:** APP-03, UX-01.
- **Work:** run the 20-round-trip target and all M1 scenarios from VALIDATION.md; review final diff and secret/diagnostic exposure.
- **Deliverable:** evidence bundle with exact checks, device matrix, results, and unsupported conditions.
- **Done when:** mandatory M1 scenarios pass and the measured target is honestly reported; all failed cases are preserved; no app build alone is substituted for interaction checks.

## M2 — interrupted connections and relays

### NET-02 — Implement bounded synchronization

- [ ] **Owner:** core/networking lead · **Priority:** P1 · **Dependencies:** QA-01.
- **Work:** exchange authenticated eligible inventories, request missing envelopes, apply byte/frame/queue limits, and persist transfer state as needed.
- **Deliverable:** resumable bounded synchronization.
- **Done when:** interruption, duplicate inventories, oversized frames, capacity exhaustion, and restart do not lose accepted endpoint work or grow unbounded memory.

### NET-03 — Prove store-carry-forward and the return path

- [ ] **Owner:** networking lead · **Priority:** P1 · **Dependencies:** NET-02.
- **Work:** implement opaque relay custody, hop/per-node forwarding limits, and isolated A→B then B→C contacts; exercise delayed reverse acknowledgment.
- **Deliverable:** measured three-node relay demonstration.
- **Done when:** V-12, V-13, and V-14 pass without direct A→C connectivity; custody receipts remain distinct from responder acknowledgment; the relay cannot decrypt bodies.

### NET-04 — Characterize runtime and laptop participation

- [ ] **Owner:** platform/networking lead · **Priority:** P1 · **Dependencies:** NET-03.
- **Work:** test lock/background/force-quit/reopen across the device matrix; evaluate an optional C++ laptop LAN adapter independently and test actual interoperability.
- **Deliverable:** supported-runtime matrix and deployment recommendation.
- **Done when:** unsupported conditions are visible in UI/docs; V-10 recovery is checked; V-18 passes before any laptop compatibility claim. A negative laptop result is recorded, not hidden.

### ENG-07 — Add freshness-aware scheduling and scenarios

- [ ] **Owner:** core lead · **Priority:** P1 · **Dependencies:** NET-02.
- **Work:** implement configured retry, control/assistance budget, ordinary-message fairness, location coalescing, redacted metrics, and a deterministic C++ scenario runner.
- **Deliverable:** scheduler plus replayable contact/failure scenarios.
- **Done when:** assistance events are never coalesced away; bytes/control overhead and sender fairness are measured against equivalent baselines; no superiority claim lacks data.

### QA-02 — Verify M2 under failures and load

- [ ] **Owner:** validation lead · **Priority:** P1 · **Dependencies:** NET-03, NET-04, ENG-07.
- **Work:** run M2 scenarios and equivalent offered-load comparisons; inspect persistence, queues, clock uncertainty, one-way paths, duplicates, and reconnection storms.
- **Deliverable:** network evaluation report and supported topology/runtime scope.
- **Done when:** all required relay/recovery cases pass within that scope; results include undelivered messages, latency distribution, overhead, and limits.

## M3 — indoor-location research

### LOC-01 — Prepare consent, labels, and sensor capture

- [ ] **Owner:** localization + privacy lead · **Priority:** P1 · **Dependencies:** DISC-02, ENG-03, ENG-05.
- **Work:** define collection consent, device/placement metadata, ground-truth annotations, unit conversion, actual cadence/gap recording, reference events, and protected export.
- **Deliverable:** supported sensor capture and labeling workflow.
- **Done when:** known fixtures verify units/time/reference reset; permission denial and missing hardware are explicit; no real data is collected without authorization/consent.

### LOC-02 — Collect the feasibility dataset

- [ ] **Owner:** localization lead · **Priority:** P1 · **Dependencies:** LOC-01.
- **Work:** collect the proposed building/device/day/transition coverage in LOCALIZATION.md, including stationary and no-reference cohorts. Record deviations and annotation uncertainty.
- **Deliverable:** consented dataset manifest, labels, splits, and collection report.
- **Done when:** coverage is accounted for; train/test session leakage is prevented; missing cohorts are labeled unsupported; dataset access/retention is documented.

### LOC-03 — Evaluate simple baselines

- [ ] **Owner:** localization lead · **Priority:** P1 · **Dependencies:** LOC-02.
- **Work:** evaluate relative altitude, pressure/reference, and building-aware baselines; compare manual workflow separately; test missing reference and floor numbering differences.
- **Deliverable:** baseline report and reproducible configurations.
- **Done when:** error, delay, availability, and strata are reported; an unavailable baseline never becomes a invented labeled floor; held-out test data remains untouched during tuning.

### LOC-04 — Evaluate fusion and uncertainty

- [ ] **Owner:** localization lead · **Priority:** P1 · **Dependencies:** LOC-03.
- **Work:** choose the simplest justified fusion/transition model, evaluate held-out buildings/devices, calibrate or abstain from numerical confidence, measure energy/runtime, and inspect confident failures.
- **Deliverable:** research decision and failure/coverage report.
- **Done when:** a model is promoted only with task benefit and defensible uncertainty; otherwise document the negative result and retain simpler/manual behavior.

### LOC-05 — Present estimates in the rescue workflow

- [ ] **Owner:** client + localization lead · **Priority:** P1 · **Dependencies:** LOC-04, QA-02.
- **Work:** integrate only supported experimental output; preserve reported floor and source times; show unavailable/conflicting/time-uncertain states; no fabricated precise room pin.
- **Deliverable:** estimate presentation in both interfaces.
- **Done when:** V-11/V-16 and user comprehension checks pass; relaying does not reset source age; unavailable estimates leave the manual request/reply functional.

### QA-03 — Review localization evidence

- [ ] **Owner:** validation lead · **Priority:** P1 · **Dependencies:** LOC-05.
- **Work:** reproduce final test results from fixed artifacts, inspect splits/labels, replay worst cases, and compare phone estimate versus responder-displayed information.
- **Deliverable:** M3 evidence bundle and explicit supported conditions.
- **Done when:** coverage and failures are included; no prototype result is described as structural-fire validation or universal accuracy.

## M4 — business discovery and supervised partner pilot

### BIZ-01 — Validate the customer and alternative

- [ ] **Owner:** business lead · **Priority:** P1 · **Dependencies:** DISC-01, DISC-03.
- **Work:** compare equivalent current competitor workflows; interview the actual budget owner; identify a repeat task and adoption barriers.
- **Deliverable:** dated customer/competitor evidence and preferred initial segment.
- **Done when:** the proposed advantage is supported or explicitly rejected; no invented TAM, pricing, performance superiority, or purchase commitment appears.

### PILOT-01 — Prepare replay and exercise export

- [ ] **Owner:** core/client lead · **Priority:** P1 · **Dependencies:** QA-02.
- **Work:** add explicit coordinator export and replay of request/delivery/contact events; optionally include separately consented location data.
- **Deliverable:** privacy-labeled exercise report/replay workflow.
- **Done when:** V-19 covers redaction, access, timestamps, missing events, retention, and deletion; exported copies are not falsely claimed to be revoked.

### PILOT-02 — Draft a bounded pilot package

- [ ] **Owner:** product + partner coordinator · **Priority:** P1 · **Dependencies:** BIZ-01, QA-02, PILOT-01.
- **Work:** draft purpose, enrolled roles, supported matrix, synthetic/consented data, normal procedures, setup, scenarios, stop conditions, support, results format, and donated/paid terms.
- **Deliverable:** concrete pilot proposal for review; no automatic outreach.
- **Done when:** a named partner and coordinator approve the exact exercise before it runs; optional M3 estimates require QA-03 and explicit inclusion.

### PILOT-03 — Run and evaluate the partner drill

- [ ] **Owner:** validation + partner coordinator · **Priority:** P1 · **Dependencies:** PILOT-02.
- **Work:** execute approved setup/exchange/outage/update/replay scenarios; compare the current workflow; record failures, user confusion, setup effort, and support time.
- **Deliverable:** partner-reviewed evaluation report and progression recommendation.
- **Done when:** results support continue/revise/stop with limitations; any incident or stop condition is documented; the drill is not marketed as operational certification.

### BIZ-02 — Estimate delivery costs and pricing hypotheses

- [ ] **Owner:** business lead · **Priority:** P1 · **Dependencies:** BIZ-01, PILOT-03.
- **Work:** populate the cost worksheet with actual quotes/time logs; interview buyers about package/contract structure; distinguish research investment from engagement costs.
- **Deliverable:** low/base/high package economics with sources and assumptions.
- **Done when:** hypothetical prices are labeled; support/hardware/replacement/validation effort is included; no commercial viability claim depends on unverified savings.

### BIZ-03 — Choose a sustainable adoption route

- [ ] **Owner:** business + product lead · **Priority:** P1 · **Dependencies:** PILOT-03, BIZ-02.
- **Work:** compare software/support, exercise rental, sponsored public deployment, and SDK partnership using operator and budget evidence.
- **Deliverable:** chosen next offering or an explicit research-only decision.
- **Done when:** buyer, repeat need, delivery responsibility, alternative, cost assumptions, and purchasing path are identified; further outreach remains authorized separately.

### PILOT-04 — Review any operational-use proposal

- [ ] **Owner:** partner + hardware/security leads · **Priority:** P1 · **Dependencies:** PILOT-03, BIZ-03.
- **Work:** specify intended environment and use; identify applicable equipment/security/privacy/accessibility/procurement/integration reviews and independent validation; review support and failure procedures.
- **Deliverable:** intended-use evidence plan or decision to remain training-only.
- **Done when:** no live-incident use is proposed from an ordinary-phone demo alone; unresolved requirements have owners and gates before deployment.

## Later capabilities — scope only after evidence

### FUT-01 — Continuous firefighter tracking

- [ ] **Owner:** product + localization + hardware · **Priority:** P2 · **Dependencies:** QA-03, PILOT-03.
- **Work:** validate a partner need; choose mounting/reference/hardware; evaluate longer trajectories, crawling/climbing, and communication age.
- **Done when:** a separate extension spec and intended-use test plan preserve the public SOS journey and name supported conditions.

### FUT-02 — Multiple command authorities

- [ ] **Owner:** systems + security · **Priority:** P2 · **Dependencies:** PILOT-03.
- **Work:** define request ownership, concurrent assignments, revisions, disconnected editing, handoff, and authority revocation.
- **Done when:** conflicting command actions have an explicit resolution workflow and tested reconnect behavior; no generic last-write-wins rule is guessed.

### FUT-03 — On-device translation and summarization

- [ ] **Owner:** product + ML · **Priority:** P2 · **Dependencies:** PILOT-03.
- **Work:** establish a language/reporting need; compare templates/extractive and model-based approaches; measure critical-fact preservation, bytes, latency, energy, and supported languages.
- **Done when:** originals remain available; transformations occur at endpoints; names/numbers/negation are tested; AI cannot change authority, location, or delivery facts.

### FUT-04 — Public discovery and institutional integrations

- [ ] **Owner:** product + integration + security · **Priority:** P2 · **Dependencies:** BIZ-03, PILOT-04.
- **Work:** design public readiness/trusted responder discovery; consider a gateway or authorized emergency-center/CAD integration only with a named partner.
- **Done when:** topology, abuse model, onboarding, jurisdictional workflow, and integration-delivery semantics are documented before launch; no automatic 911 connection is implied.

### FUT-05 — Additional platforms and relay hardware

- [ ] **Owner:** platform + hardware · **Priority:** P2 · **Dependencies:** NET-04, PILOT-03.
- **Work:** evaluate Android, BLE/Wi-Fi Aware, dedicated radios, or rugged wearables according to partner equipment evidence.
- **Done when:** interoperation and intended-use suitability are physically measured; adding a platform does not fork message/status semantics.

## Task update rule

For completed work, retain the task ID and add dated evidence links/check outcomes below its checkbox. Do not check all tasks for a milestone based on one demo. When evidence changes scope, update the decision register and the affected requirements before editing this backlog.


### Public emergency onboarding gate — accepted 2026-10-10

- [ ] Design and verify SOS from a previously unpaired public app without emergency-time card copying, fingerprint comparison, QR scanning or manual peer selection. Prepare authorized responder credentials beforehand; define offline verification/lifecycle, abuse controls and encrypted replies before building. Validate an internet-unavailable SOS/device-receipt/human-acknowledgment/reply round trip and rejection of forged responder authority. See [PRD](PRD.md#emergency-onboarding-requirement--accepted-2026-10-10). Current manual pairing is a controlled-test mechanism; automatic discovery of organization-verified responders and campus enrollment remain unimplemented; automatic exchange between manually pinned test endpoints is a separate checkpoint.
