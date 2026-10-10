# Decision register

Status: initial register, v0.1 · 2026-10-07

Read this alongside the [PRD](PRD.md). "Accepted" means established by the conversation. "Provisional" means a working default chosen for initial documentation, subject to the named evidence gate.

## Accepted direction

| ID | Decision | Why |
|---|---|---|
| D-01 | One system with public and responder interfaces | User explicitly selected the dual-interface rescue concept |
| D-02 | C++ owns the shared engine and any project backend service | User requires C++ for backend work |
| D-03 | Swift iPhone/iPad interfaces are the preferred first clients | Matches user preference and the initial physical-device demonstration |
| D-04 | Initial deliverable is documents only | No product code or scaffolding was requested |
| D-05 | First workflow is an offline SOS and returning acknowledgment | Establishes the complete rescue communication loop |
| D-06 | Indoor floor estimation is a research priority | User expressed specific interest in the sensor paper |

## Provisional engineering and business defaults

| ID | Default | Alternative considered | Evidence that changes it |
|---|---|---|---|
| D-07 | Prepared, enrolled participants in a non-emergency drill | Open public launch first | Verified public onboarding and responder-discovery design, abuse tests, and partner readiness |
| D-08 | iOS/iPadOS 18 minimum for the baseline experiment; capability checks on physical devices | Require iOS 26 for Wi-Fi Aware | Transport matrix demonstrates a material benefit and partner device availability |
| D-09 | Foreground Network framework NW* adapter for the synthetic direct-path probe | BLE, Wi-Fi Aware, or local LAN as the sole baseline | Apple TN3213 supersedes the earlier MPC default; NET-01 still determines the production adapter |
| D-10 | Core is transport-independent C++20; thin C-compatible bridge | Large directly imported C++ surface | Bridge benchmark/review supports simpler ownership without lifecycle hazards |
| D-11 | Embedded transactional storage, with SQLite as the candidate | Files or cloud persistence | Storage recovery and integration review justify another solution |
| D-12 | One command authority per exercise; linear responder handling revisions | Distributed command editing from the start | Partner requires disconnected multiple-command use and conflict policy is designed |
| D-13 | U.S. organizations are the first discovery hypothesis | India or market-neutral launch | User preference or actual partner availability |
| D-14 | Department/training pilot before operational sales | Immediate operational hardware product | External validation, hardware suitability, and adopted workflow justify progression |
| D-15 | Optional laptop relay after the phone-to-iPad path | Cloud routing as a mandatory dependency | A measured local deployment need; cloud remains optional for later features |

The baseline transport is a test convenience, not a promise about production networking. Apple documents its background limitations [R03](RESEARCH.md#r03). Its newer networking guidance must be considered in NET-01.

## Decisions deliberately gated by research

| ID | Question | Owner role | Resolving task | Deadline / artifact |
|---|---|---|---|---|
| O-01 | Which radio transport and device matrix survive the intended drill? | Networking lead | NET-01 | Before M1 implementation; transport decision record |
| O-02 | Which reviewed envelope/library and provisioning design should be used? | Security lead | SEC-01 | Before sending private data; threat-model and dependency record |
| O-03 | What public enrollment model works beyond prepared exercises? | Product + security | DISC-03 | Before public distribution; deployment workflow |
| O-04 | Can floor estimates improve the task without harmful confidence? | Localization lead | LOC-04 | Before showing estimates to pilot users; evaluation report |
| O-05 | What organization, workflow, and budget owner benefit? | Product/business lead | DISC-01, BIZ-01 | Before a pilot agreement; interview synthesis |
| O-06 | What equipment and applicable reviews are needed for live deployment? | Partner + hardware/security leads | PILOT-04 | Before any operational-use proposal; intended-use review |
| O-07 | How should multiple command devices coordinate? | Systems lead | FUT-02 | Before adding multi-command writes; conflict specification |

These are bounded investigation tasks rather than blanks an implementer should guess. The initial docs are complete as a discovery baseline; they do not authorize bypassing these gates.

## Self-review of the initial direction

| Perspective | Risk identified | Revision adopted |
|---|---|---|
| Correctness | A relay receipt could be mistaken for rescue acceptance | Split delivery, human acknowledgment, and handling states |
| Simplicity | Too many systems in the MVP | Manual floor and direct round trip precede relays, sensors, and AI |
| Security/privacy | Any nearby device could impersonate a responder | Verified exercise authority; endpoint-private message bodies |
| Maintainability | Radio API assumptions could leak into routing | Swift transport adapters around a shared C++ engine |
| Testing | A simulator could conceal lifecycle failures | Physical-device/lifecycle checks gate the prototype |
| User experience | Narrowing the pilot could erase the public app | Both user journeys remain mandatory in M1 |

## Change policy

Append dated changes with evidence, the superseded decision ID, affected requirements, and task implications. Do not silently replace an accepted product audience or label a prototype target as a validated safety threshold.

## 2026-10-07 — first design checkpoint

The user approved proceeding with the first-milestone brief and sharing the five named documents with Claude Code. Its completed read-only review and the primary-agent assessment are recorded in [design review](DESIGN_REVIEW.md). The PRD, system design, privacy model, and validation now clarify return-message receipts, explicit reopening/withdrawal disposition, required transport permission readiness, and optional operator-label attribution. Coordinator setup is provisionally placed within the responder interface, subject to SEC-01; no third app is introduced. These clarify D-05/D-07/D-12 without changing D-01–D-03 or resolving NET-01/SEC-01. Figma team and physical endpoints remain unselected.

## 2026-10-07 — publication and Figma draft

The user selected Archit Jaiswal's team for Figma and explicitly authorized a public GitHub repo plus ongoing commits/pushes at verified checkpoints. Repository: [archiips/offline-rescue-network](https://github.com/archiips/offline-rescue-network); local default branch: main. The [Figma draft](https://www.figma.com/design/KfslxdEf2XarwLbSEDzbJS?node-id=4-333) and its current evidence/limitations are recorded in DESIGN_REVIEW.md. Figma MCP limits stopped further refinement; no engineering-completion or operational-use claim follows. Physical endpoints remain unconfirmed.

## 2026-10-07 — synthetic probe authorization and transport revision

User approved preparing a small iPhone/Mac synthetic probe while the iPad is unavailable. D-04 describes the original deliverable; this later authorization permits isolated experiment code, not bypassing NET-01/SEC-01. D-09 now favors older Network NW* APIs for the spike because current Apple TN3213 recommends Network framework and documents MPC deprecation in Xcode 27. This is source guidance, not a claim that the user installed iOS 27. D-08 remains provisional. The [probe record](NETWORK_PROBE.md) separates build/loopback evidence from physical radio measurements. [Protocol/security proposal](PROTOCOL_SECURITY_DRAFT.md) prepares SEC-01 but does not freeze cryptography. Both product audiences and C++ ownership remain unchanged.

## 2026-10-07 — device-independent workflow preparation

The user deferred physical testing and authorized continuing development. A [C++ workflow model](../experiments/workflow-model/README.md) now prepares both requester and responder state behavior with independent synthetic instances. This allows local development ahead of the physical transport gate without changing the product audience or claiming ENG-01–05 completion. Typed experiment events are not the frozen private wire protocol; fixture role checks are not authentication; in-memory acceptance is not durable commit. Physical NET-01, SEC-01 and production scaffolding gates remain open. [Plan/evidence](superpowers/plans/2026-10-07-workflow-model.md) records scope and validation.

## 2026-10-07 — portfolio-first native workflow checkpoint

The user prioritized a working, impressive résumé project and deferred commercialization. This changes development priority, not the two-audience product brief or eventual security requirements. A [native training demo](../experiments/rescue-demo/README.md) now connects SwiftUI public/responder views through a C ABI to independent instances of the existing C++ engine. Preset synthetic data and a visibly simulated in-process link allow native UX work before physical NET-01 testing. Role selection is not authentication; in-memory receipts are not durable commits. SEC-01 and physical/private-data gates remain open. The simulator milestone does not claim M1 completion, encrypted multi-hop operation or 20-device/5-second measurements. Actual test counts and evidence are recorded in its README. Next priority is durable recovery and real local exchange; sales and partner operations can wait.

## 2026-10-07 — saved training-session checkpoint

The user cannot physically test now and authorized continued building. The native demo now uses system SQLite through the C++ wrapper to persist both simulated endpoints, their acceptance-order histories and pending transfers in one local transaction. Commit precedes UI publication; failed writes/reset retain prior state, stale writers reject and reopen never delivers queued messages automatically. The domain Model remains unchanged and in memory. [Current evidence](../experiments/rescue-demo/README.md#saved-session-checkpoint--2026-10-07): 24 CTest checks in sanitizer/Release, 10 Swift tests, simulator build and iPhone/iPad force-quit recovery. This is synthetic single-process training storage, not a shared device database, encrypted storage or M1/ENG-04 completion. Next real-network work must split each endpoint’s transaction ownership and retain explicit delivery/human acknowledgment. Physical testing can wait for that integration; no sales or live-use claim follows.


## 2026-10-08 — real local sample exchange

The user authorized continuing while physical testing is unavailable. Local mode now gives each app/CLI endpoint one C++ Model and one role-tagged v2 SQLite outbox; the original two-model v1 training mode remains separate. A bounded binary packet and foreground Network-framework request/receipt transport carry preset sample messages. Receiver acceptance and its receipt commit together; sender confirmation and outbox removal commit together. Lost receipts are returned identically on retry. Reserved history slots ensure pending originals can still be confirmed near capacity. Canonical fixture IDs and strict saved outbox ordering fail closed.

Bonjour selection is manual, later actions use the selected peer while active, and a failed transfer clears that selection. Stop/background and restart retain queues without restarting networking automatically. Mode and role survive app restart. Fixed request IDs require coordinated endpoint reset. [Evidence](../experiments/rescue-demo/LOCAL_EXCHANGE.md) records separate Mac processes, native iPhone/iPad simulator-to-Mac exchange and restart recovery. Actual Claude Code supplied the limited Swift adapter implementation and read-only reviews; review findings were reproduced/fixed where applicable.

This advances the portfolio demo without closing NET-01, SEC-01, ENG-04 or M1. Plain packets, unverified identities and unencrypted sample storage remain explicit limits. Physical radio/range, older-device compatibility, privacy prompts, background operation, relay and private-message security remain separate work. No device-count or latency benchmark is inferred.


## 2026-10-08 — durable portfolio-first resume instructions

The user reaffirmed that documentation must follow the diversion to a working résumé project, with selling/organizational adoption deferred. [Current state](CURRENT_STATE.md) is now the repository resume entry point; AGENTS.md points future sessions there. TODO separates completed, verified portfolio checkpoints from the original gated product backlog. PRD and roadmap state the portfolio outcome as the immediate goal, FIRST_MILESTONE labels its old sequence historical, and business/discovery remains deferred. Existing physical/security acceptance criteria are preserved rather than falsely checked off. The next device-independent step is reproducible measurement/recovery evidence, followed by separately planned security/relay/priority work. This is documentation alignment; no new code or benchmark claim is introduced.


## 2026-10-08 — reproducible portfolio measurements

The next portfolio checkpoint now measures actual independent Swift/C++ Mac hosts with stdlib Python orchestration. No app, engine or protocol behavior changed. [Evidence](../experiments/rescue-demo/MEASUREMENTS.md) records 20 complete fresh-store trials, 80 confirmed original-message transfers, controlled refused connections/process death/duplicate correction/lost response and exact persisted recovery checks. Command-to-confirmation timings include host scheduling and SQLite commits; they exclude composition/manual response/startup/outage and establish no physical radio result. All raw trials and machine/source/executable provenance are retained; median/nearest-rank p95 are descriptive, not guarantees.14 Python checks supplement unchanged 30 CTest/33 Swift checks.

Actual Claude Code reviews used the user's explicit Opus 5.5/medium preference; follow-up metadata confirmed the model and reported no blockers. Reporting-error fencing and evidence-file safety issues were reproduced and corrected. The daemon interrupted one capture before output publication; a fresh completed 20-trial capture supplies the committed results. The next task is reviewed identity/encryption for the local synthetic demo, before relays/private data. Portfolio-first direction and original physical/security gates remain unchanged.

## 2026-10-08 — signed/encrypted portfolio endpoints

The bounded native demo now uses checked opposite-role public cards, CryptoKit RFC9180 HPKE encryption and separate Ed25519 signatures around unchanged C++ ORX1 events. C++ still owns role/action authority, saved outboxes, receipt transactions and state projections. This revises the security draft's portable C++ crypto preference for the Apple-only portfolio checkpoint; a portable library integration remains later work. TLS-only transport and shared-secret-only role authority were rejected for their mismatch with private relay envelopes and sender-specific role trust. No new production dependency was introduced.

Keys/pins persist in Keychain; every key epoch owns a separate UUID SQLite file. New-session reset/recovery clears trust and changes identity before starting a fresh store. Cached endpoints reject stale records, and paired keys with missing history fail rather than reusing fixed IDs. iOS has a stable app-scoped namespace across data-container moves. Mac command-line diagnostics intentionally use login Keychain after actual missing-entitlement failure from DP-Keychain; its accessibility is weaker. Simulator signing is scoped to the app target; physical development signing still needs the user's actual team.

[Secure evidence](../experiments/rescue-demo/SECURE_EXCHANGE.md) records 62 Swift checks, unchanged 30 sanitizer CTest/14 Python checks, real-Keychain independent-host death/duplicate/lost-response recovery and inspected signed iPhone/iPad simulator-to-Mac workflows. Claude calls used verified Opus 5.5/medium. The prior plain-loopback measurements remain valid only for that baseline. Manual trust does not verify an organization; SQLite is unencrypted, old sample files persist and physical/security audit/private-data gates remain open. Next is a separately designed bounded relay/urgent scheduling demonstration; both audiences and portfolio-first scope remain intact.

## 2026-10-08 — durable opaque relay foundation first

Choose C++/SQLite custody plus a real encrypted process-local contact scenario before a relay network adapter. A socket proxy needs simultaneous contacts; a full BPv7 stack adds unnecessary dependencies and routing/security scope. Preserve both native interfaces. Per-flow FIFO protects dependencies;3:1 priority applies across eligible heads. Local metadata is not authenticated network admission. Custody does not clear endpoint pending state or prove human acknowledgment. Full NET-03/ENG-07 stays open. After interruption cleared the temporary uncommitted worktree, use persistent ignored project-local worktree and local Git checkpoints; reconstruct and freshly verify rather than reusing lost test evidence.

SQLite can recover a hot rollback journal before the first format PRAGMA. A real fork/crash regression reproduced mutation of a foreign file during rejected open. Require this queue's complete header/version/application ID before opening; allow marked relay recovery before strict validation. Foreign fixture bytes/journal remain unchanged and owned interrupted writes recover. Reject incomplete unmarked initialization rather than automatic repair. Header markers are not authentication; no promise of byte preservation for damaged marked files or protection from external file replacement.

## 2026-10-08 — Signed single-relay process checkpoint

Adopt a bounded custom ORL1/ORA1 sample contract around existing ORS1 CryptoKit envelopes and the C++ queue. Pin both public cards at the relay; destination-signed acceptance admits the correlated encrypted reverse receipt before removing original custody. Untrusted ORC1 custody never confirms device delivery. Reject a simultaneous socket proxy because delayed contacts require durable custody; full BPv7 is deferred to avoid unrelated dependencies and scope. This is not an audited standard implementation.

Endpoint cache admission never prunes/reseals expired mappings. ORF1 signs the mapping and packet, ORG1 detects missing/mismatched cache files, and guards are read with fixed bounds. Explicit new-session recovery rotates identity and requires re-pairing while retaining prior stores. One active owner per root/role remains required; hostile local file deletion and same-user process isolation are outside the sample guarantee.

Separate Mac processes demonstrate sequential contacts rather than physical or firewall isolation. Eleven actual-process facts and43 CTest/89 Swift/13 relay Python checks pass; native app builds with signing. Both audiences remain required; native controls are the next checkpoint. Physical/private-data/commercial gates remain open. [Evidence](../experiments/rescue-demo/RELAY_NETWORK.md).


## Native relay controls and mixed-route receipts — 2026-10-08

Expose the existing signed relay adapter through shared manual controls for public iPhone and responder iPad. Keep one identity/history/outbox across route switches; stop and fence old callbacks, disable Bonjour/direct fallback in relay mode and upload one oldest cached event only. Custody is an untrusted transient hint, never device receipt or human acknowledgment. Host/port and route preferences persist; listeners do not auto-start. Cache loss/expiry/full recovery explicitly resets/re-pairs while preserving prior files.

A reproduced review finding showed a delayed relay receipt blocking replies after Direct had already confirmed its event. A read-only C++ bridge now resolves the original only for the exact receipt in committed history. The adapter still checks the mapping-bound signed outgoing cache and receipt correlation before acceptance. Disabling route switching was rejected because it would remove the preserved direct journey. No wire/store-format change or arbitrary duplicate bypass. Native controls/controller tests/build are verified; full native relay exercise awaits explicit attended pairing approval. [Evidence](../experiments/rescue-demo/NATIVE_RELAY.md).


## Native relay evidence boundary — 2026-10-09

Explicit pairing approval resolved the earlier action-time trust block. The attended native iPhone/iPad→Mac relay exercise now verifies SOS, separate device receipt/human acknowledgment, reply, correction, refused-upload retention, native background-stop and process restart recovery. Four events and four reverse receipts crossed eight successful flushes in one simulator walkthrough. This advances native integration evidence only: it does not establish physical radio, network isolation or a latency/reliability population. No code or protocol change was needed. [Observation record](../experiments/rescue-demo/native-relay-evidence.json).


## Signed-relay measurement populations — 2026-10-09

Reuse the verified three-process smoke scenario through a Python child-factory seam; leave the C++ engine, Swift adapters and both native interfaces unchanged. Reject duplicated scenario logic and production timestamp changes for this bounded evaluation. Use command-to-validated-STATE timing, event/receipt-ID-correlated source confirmation probes and separate initial/duplicate custody, initial/replay delivery, reverse receipts and injected failure populations. SOS fault recovery contains deliberate failures and restarts and cannot be compared to clean ack/reply cycles or earlier plain direct timings as a speed result.

[Report/raw evidence](../experiments/rescue-demo/RELAY_MEASUREMENTS.md): 20/20 actual-loopback trials, 60 original confirmations, all 11 recovery facts per trial and zero cleanup failures; 47 Python / 96 Swift / 43 fatal-UBSan CTest checks. Clean captured source and matching before/after source/binary hashes improve inspectability without attesting build provenance or a full toolchain. No physical, native-latency, background or operational reliability claim follows. Next optional portfolio asset is a native recording; product/privacy gates stay open.


## Presentation hierarchy and explanatory motion — 2026-10-09

Preserve both native audiences and all workflow actions, while moving technical mode/role/pairing/route/manual connection/reset into Setup. Keep queue, connection, persistence and error state visible. Device receipt, human acknowledgment and handling remain separate. Draft/review state belongs to the shell so layout changes do not discard it.

Choose isolated Remotion authoring for reproducible narrated diagrams and timed type/motion. Motion Canvas is a viable procedural alternative; Screen Studio is better suited to polishing future actual interactions. No video dependency enters the native app. Label workflow illustrations separately from actual captures, keep editorial timing separate from latency evidence, and retain the optional live-recording task. The earlier static cut failed to explain the story despite decoding correctly. [Research](RESEARCH.md#motion-and-demo-authoring--2026-10-09), [implementation ledger](superpowers/plans/2026-10-09-presentation-redesign.md).


## Dark console and actual product footage — 2026-10-09

The user rejected the diagram-heavy film and selected a dark operational-console interface. Replace the tall banner/card stacks with graphite surfaces, amber actions, crisp native type, compact status, conversational history and progressively disclosed secondary controls. Preserve both audiences and every workflow/manual transport action.

Use actual native interactions as the next demo's principal content. Apply Brag's product entry/action/result emphasis and purposeful camera framing; do not reconstruct the app in a web imitation. Record a separate fresh training simulator with a visible simulated-link label, preserving existing secure peer history. The final native visual checkpoint builds and passes 96 controller tests; fresh interaction capture is blocked by native computer-use startup. Neither prior film nor prepared composition is accepted live footage. [Research and limitations](superpowers/plans/2026-10-09-live-product-redesign.md).

## Optional dated device observation — 2026-10-09

Add opt-in one-shot Core Location capture to the public draft, alongside a manually reported place/floor. Capture never sends; SOS freezes the reviewed report, while a correction explicitly sends the displayed draft. Both audiences and message history show coordinates, reported accuracy, observation time, approximate authorization and “not live.” Keep manual-only sending available after denied/unavailable permission. No automatic floor/building inference or phone relay in this milestone.

Use validated `ORLOC1:` JSON inside the existing bounded C++ reported-location field, preserving ORX1/SQLite formats and the engine's workflow/delivery authority. Legacy strings display unchanged; malformed tagged content displays unavailable. Matched clients are required for structured rendering. Native adapter cancels on background, view/setup/mode/role changes and timeout, fencing old managers by identity. The prototype's existing unencrypted local history is disclosed before capture; validate synthetic coordinates only. [Research](RESEARCH.md#optional-device-location--2026-10-09), [plan](superpowers/plans/2026-10-09-location-capture.md).

## UW Seattle localization progression — 2026-10-09

Preserve automatic floor detection as an explicit future milestone. First investigate existing Wi-Fi/phone-sensor inputs; NFC rejected because tapping is required. Evaluate cooperative participating-phone proximity/UWB graphs against that baseline, with trusted reference observations, uncertainty and independent ground truth. Bluetooth anchors remain a measured fallback, with no purchase or installation decision. UW Seattle is the proposed first research setting, not a confirmed deployment. [Roadmap, sources and evaluation gates](UW_LOCALIZATION_ROADMAP.md). Resume controlled phone relay now; do not conflate location evidence with message reachability.

### 2026-10-09 — Independent foreground native relay workspace

Reuse the existing signed transport/RelayService/C++ queue from a separate Setup workspace, preserving endpoint workflow identities and histories. Bind queues deterministically to the two checked public cards; preserve old profile files and fail closed on damaged configuration. Manual contacts and one-packet forwarding keep custody distinct from destination receipt. Stop fences post-await mutation; exit/background stops networking. No new protocol, dependency, automatic mesh or background promise. [Verified scope and residuals](../experiments/rescue-demo/PHONE_RELAY.md).

### 2026-10-09 — Research floor estimates remain outside rescue payloads

Use a separate foreground feasibility workspace with optional Apple logical floor and C++-owned relative-altitude baseline. Require an explicit known reference, measured uniform spacing and stable calibration; reject stale/noisy/transitional data with Unknown. Show sources separately and no numeric confidence claims. Do not infer absolute floors from GPS altitude, assume UW Wi-Fi mapping, or overwrite reported location. Synthetic fixtures remain visibly distinct; stop clears reference. [Evidence and unverified physical inputs](../experiments/rescue-demo/FLOOR_RESEARCH.md).


## 2026-10-09 — Bothell-first cooperative localization evaluation

User approved Wi-Fi + participating-phone cooperative localization as the intended enhancement, retaining automatic floor research, public iPhone and responder iPad. Bothell is the regular first campus test site; Seattle is the later generalization site; Tacoma is excluded. First physical messaging tests happen in a controlled accessible location near home, not a campus-wide exercise. [Protocol](PHYSICAL_TEST_PLAN.md) defines separate LAN-without-WAN, no-common-AP and later three-device relay tests.

Existing Network-framework transport already opts into Apple peer-to-peer Wi-Fi and offers native nearby service selection; physical no-AP operation remains unverified. Reuse before replacing. Cooperative graph accuracy must beat matched sensor-only comparisons without hiding increased wrong-floor outputs. Connected SSID alone is not a localization anchor. No new hardware, infrastructure access, automatic mesh or accuracy claim follows from this choice. [Roadmap](UW_LOCALIZATION_ROADMAP.md) records missing evidence and the bounded next research milestone.


## 2026-10-09 — cooperative graph foundation

Use a bounded transparent difference-constraint graph before probabilistic/learned fusion. Contact does not create a floor relation; relative intervals need separate measurement evidence. Deduplicate original observations, reject contradictory reuse and retain Unknown for missing, ambiguous or inconsistent evidence. The first checkpoint is local synthetic replay only, with strict sensor/Wi-Fi/peer/combined comparisons. Hard logical-domain bounds and ten-second freshness are research defaults, not physical calibration. [Verified implementation and remaining adapter gates](../experiments/rescue-demo/COOPERATIVE_FLOOR_GRAPH.md).

## 2026-10-09 — bounded real cooperative input adapters

Keep permitted connected-network identifiers local until a surveyed-map design is validated. Use separate ephemeral, manually fingerprint-checked research identities and explicit encrypted challenge-bound pulls, with original sensor UUID/source and conservative age+round-trip bounds; never relay observations or feed graph outputs back as originals. Both local sensor references enter the C++ graph so disagreement is visible; nearby peer contact adds no floor constraint. Running sensor unavailability can be shared explicitly with no level. Active paired context is shown separately from editable draft. This checkpoint establishes adapters and failure behavior, not a UW floor classifier, radio range or physical accuracy. [Evidence](../experiments/rescue-demo/LIVE_COOPERATIVE_INPUTS.md).
