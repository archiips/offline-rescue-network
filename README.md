# Offline Rescue Communication

**One project. Two interfaces. A person asks for help; a responder receives the request and replies—even when internet service is unavailable, provided a usable local communication path exists.**

Working description, not a selected brand. **A runnable SwiftUI rescue demo with local messaging between independently saved C++ endpoints, plus training mode, docs and a Figma draft. Simulator-to-Mac rescue exchange and restart recovery are verified; physical offline exchange and private-message security remain unfinished.**

[Public GitHub repository](https://github.com/archiips/offline-rescue-network) · [Editable Figma draft](https://www.figma.com/design/KfslxdEf2XarwLbSEDzbJS?node-id=4-333)

## The product in plain language

| Public iPhone app | Responder iPad app |
|---|---|
| Send an SOS and describe the situation | Receive and manage assistance requests |
| Enter building, floor, room, or landmark | See reported locations and available estimates |
| Share available phone location information | See uncertainty and the age of each observation |
| See whether a responder received the request | Acknowledge, reply, and update handling status |

The Mac demonstration relays encrypted messages between participating endpoints. [Native relay controls](experiments/rescue-demo/NATIVE_RELAY.md) are verified in an attended iPhone/iPad simulator-to-Mac relay journey with SOS, acknowledgment, reply and restart recovery. A responder must become reachable. The app shows when a request is still waiting; a relay receipt does not mean help is dispatched.

## What works today

- [Connection probe](experiments/network-probe/README.md): iPhone test screen and Mac host; synthetic simulator-to-Mac exchange verified.
- [C++ workflow model](experiments/workflow-model/README.md): separate requester/responder models, complete synthetic SOS/reply/update/handling walkthrough and failure tests.
- [Native rescue demo](experiments/rescue-demo/README.md): public/responder SwiftUI views with SOS, acknowledgment, replies, location corrections and handling actions. Training mode uses a simulated link; Secure exchange sends signed/encrypted packets between independently saved, manually paired endpoints.
- [Local exchange walkthrough](experiments/rescue-demo/LOCAL_EXCHANGE.md): Bonjour discovery, Mac endpoint CLI, separate-process recovery checks and native simulator evidence. C++ SQLite commits precede device receipts; queued messages survive restart.
- [Reproducible measurements](experiments/rescue-demo/MEASUREMENTS.md): repeated independent-process exchange, deliberately lost receipts, duplicate checks and inspectable loopback timings.
- [Secure exchange](experiments/rescue-demo/SECURE_EXCHANGE.md): checked pairing cards, CryptoKit HPKE/signatures, Keychain identity recovery and retained C++ durable receipts. Plain diagnostics remain separate.
- [Relay queue foundation](experiments/rescue-demo/RELAY_QUEUE.md): durable C++ ciphertext custody, FIFO-safe urgent scheduling and a reproducible encrypted delayed-contact scenario. Historical process-local evidence; see the separate-process checkpoint below.
- Preset sample data only: message storage remains unencrypted. Physical radio, agency enrollment and independent security audit remain unfinished.

- [Signed relay network](experiments/rescue-demo/RELAY_NETWORK.md): separate Mac processes, nonoverlapping contacts, restart/lost-response recovery and delayed encrypted receipts; 11 reproducible facts.

## Current focus

Build an impressive, measurable portfolio project first. Native workflow, durable secure direct exchange and opaque relay custody are available locally. Signed separate-process relay contacts are verified. Both audiences have manual native relay controls. The attended native relay round trip and restart recovery are verified. Next: package the portfolio walkthrough and choose measured secure-relay evaluation; physical checks follow when devices are available. Commercial adoption is deferred; both audiences remain part of one app system. The simulator demo can be developed and shown while physical testing waits.

## First milestone

A controlled building drill: a person sends an SOS with a confirmed floor; a responder receives it on an iPad without internet; an acknowledgment comes back. Start with direct exchange, then test a relay and interruptions. Prepared exercise participants are the first testers; both public and responder interfaces are required.

## Larger vision

Later, evaluate broader network scheduling, indoor floor estimates, firefighter tracking, training replay, and on-device translation/summaries. These are stages of the same project.

**Preferred stack:** Swift/SwiftUI interfaces and native Apple adapters, a shared C++ engine, and an optional C++ relay service on a laptop. The essential local exchange must not require a cloud server.

## Resume work

[Current state and exact next task](docs/CURRENT_STATE.md) is the entry point for “continue from where we left off.” The [task backlog](docs/TODO.md) separates verified portfolio checkpoints from remaining physical/security/product work.

## Read the docs

| Document | Purpose |
|---|---|
| [First milestone](docs/FIRST_MILESTONE.md) | Immediate screen designs, device experiment, and acceptance checks |
| [Design review](docs/DESIGN_REVIEW.md) | Claude findings, Figma evidence, and prototype limitations |
| [Device inventory](docs/DEVICE_INVENTORY.md) | Verified development tools and missing physical-test inputs |
| [Product requirements](docs/PRD.md) | Users, workflows, requirements, and first-release boundaries |
| [System architecture](docs/ARCHITECTURE.md) | Components, ownership, deployment, and trust boundaries |
| [System design](docs/SYSTEM_DESIGN.md) | Data contracts, delivery semantics, persistence, and failure handling |
| [Indoor localization research](docs/LOCALIZATION.md) | Sensor experiments, baselines, uncertainty, and evaluation |
| [Security and privacy](docs/SECURITY_PRIVACY.md) | Enrollment, responder authority, encryption, abuse, and retention |
| [Validation and pilot](docs/VALIDATION.md) | Tests, drill protocol, evidence, and progression gates |
| [Business and adoption](docs/BUSINESS.md) | Buyers, competitors, discovery, business hypotheses, and costs |
| [Roadmap](docs/ROADMAP.md) | Milestones and decisions that unlock each stage |
| [Detailed tasks](docs/TODO.md) | Ordered work with dependencies and definitions of done |
| [Research and sources](docs/RESEARCH.md) | Primary sources, limitations, and unresolved feasibility questions |
| [Decision register](docs/DECISIONS.md) | Accepted direction, provisional defaults, and open decisions |

Read current state for the immediate next task; the first milestone retains the original product gates. The PRD and roadmap explain the full scope.

## Current assumptions

- Baseline: **2026-10-07**, version **0.1**.
- Initial business assumption: U.S. organizations, subject to discovery.
- First exercises: installed apps, enrolled devices, foreground operation, synthetic requests.
- Manual location comes first; automatic estimates remain experimental.
- Live-incident use, 911 integration, and pricing need separate evidence.

## Repository state

The [synthetic networking probe](experiments/network-probe/README.md) has verified build/test commands. Production toolchain setup, physical transport validation and private-message security remain gated. See [probe plan/evidence](docs/NETWORK_PROBE.md) and [protocol/security proposal](docs/PROTOCOL_SECURITY_DRAFT.md).
