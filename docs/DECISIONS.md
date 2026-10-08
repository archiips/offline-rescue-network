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
