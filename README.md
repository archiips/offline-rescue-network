# Offline Rescue Communication

**One project. Two interfaces. A person asks for help; a responder receives the request and replies—even when internet service is unavailable, provided a usable local communication path exists.**

Working description, not a selected brand. **A runnable native SwiftUI training demo, shared C++ workflow engine, synthetic networking probe, docs and a Figma draft. Physical offline exchange and durable secure messaging remain unfinished.**

[Public GitHub repository](https://github.com/archiips/offline-rescue-network) · [Editable Figma draft](https://www.figma.com/design/KfslxdEf2XarwLbSEDzbJS?node-id=4-333)

## The product in plain language

| Public iPhone app | Responder iPad app |
|---|---|
| Send an SOS and describe the situation | Receive and manage assistance requests |
| Enter building, floor, room, or landmark | See reported locations and available estimates |
| Share available phone location information | See uncertainty and the age of each observation |
| See whether a responder received the request | Acknowledge, reply, and update handling status |

Nearby participating devices can later relay encrypted messages. A responder must become reachable. The app shows when a request is still waiting; a relay receipt does not mean help is dispatched.

## What works today

- [Connection probe](experiments/network-probe/README.md): iPhone test screen and Mac host; synthetic simulator-to-Mac exchange verified.
- [C++ workflow model](experiments/workflow-model/README.md): separate requester/responder models, complete synthetic SOS/reply/update/handling walkthrough and failure tests.
- [Native workflow demo](experiments/rescue-demo/README.md): public/responder SwiftUI views connected to independent C++ models, with SOS, acknowledgments, replies, queued updates and handling actions.
- These remain experiments: the native demo uses a simulated link; physical networking, endpoint cryptography and durable storage remain unfinished.

## Current focus

Build an impressive, measurable portfolio project first. The immediate sequence is native workflow → durable recovery → real local exchange → relay demonstration and measured results. Commercial adoption is deferred; both audiences remain part of one app system. The simulator demo can be developed and shown while physical testing waits.

## First milestone

A controlled building drill: a person sends an SOS with a confirmed floor; a responder receives it on an iPad without internet; an acknowledgment comes back. Start with direct exchange, then test a relay and interruptions. Prepared exercise participants are the first testers; both public and responder interfaces are required.

## Larger vision

Later, evaluate indoor floor estimates, urgent-message scheduling, firefighter tracking, training replay, and on-device translation/summaries. These are stages of the same project.

**Preferred stack:** Swift/SwiftUI interfaces and native Apple adapters, a shared C++ engine, and an optional C++ relay service on a laptop. The essential local exchange must not require a cloud server.

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

Read the first milestone for the immediate next steps. The PRD and roadmap explain the full scope.

## Current assumptions

- Baseline: **2026-10-07**, version **0.1**.
- Initial business assumption: U.S. organizations, subject to discovery.
- First exercises: installed apps, enrolled devices, foreground operation, synthetic requests.
- Manual location comes first; automatic estimates remain experimental.
- Live-incident use, 911 integration, and pricing need separate evidence.

## Repository state

The [synthetic networking probe](experiments/network-probe/README.md) has verified build/test commands. Production toolchain setup, physical transport validation and private-message security remain gated. See [probe plan/evidence](docs/NETWORK_PROBE.md) and [protocol/security proposal](docs/PROTOCOL_SECURITY_DRAFT.md).
