# Offline Rescue Communication

**One project. Two interfaces. A person asks for help; a responder receives the request and replies—even when internet service is unavailable, provided a usable local communication path exists.**

Working description, not a selected brand. **Documentation and design prototypes; no product code exists yet.**

[Public GitHub repository](https://github.com/archiips/offline-rescue-network) · [Editable Figma draft](https://www.figma.com/design/KfslxdEf2XarwLbSEDzbJS?node-id=4-333)

## The product in plain language

| Public iPhone app | Responder iPad app |
|---|---|
| Send an SOS and describe the situation | Receive and manage assistance requests |
| Enter building, floor, room, or landmark | See reported locations and available estimates |
| Share available phone location information | See uncertainty and the age of each observation |
| See whether a responder received the request | Acknowledge, reply, and update handling status |

Nearby participating devices can later relay encrypted messages. A responder must become reachable. The app shows when a request is still waiting; a relay receipt does not mean help is dispatched.

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

No build/test commands exist yet. The first engineering setup task will establish them.
