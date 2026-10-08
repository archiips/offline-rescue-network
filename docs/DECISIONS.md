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
