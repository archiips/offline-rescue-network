# Direct SOS design review

> Current execution status (2026-10-08): see [current state / resume](CURRENT_STATE.md) and [portfolio tasks](TODO.md#current-portfolio-tasks). This document retains its product requirements, proposal or dated evidence; it does not claim that all described capabilities are implemented.

Status: documentation review complete; Figma draft structurally and visually inspected · 2026-10-07

## Review method and scope

The user explicitly approved sharing README.md, PRD.md, SYSTEM_DESIGN.md, SECURITY_PRIVACY.md, and VALIDATION.md with Anthropic Claude Code. The authenticated CLI completed a read-only review using only its Read tool, with customizations and MCP servers disabled. No files were edited by Claude. Its review did not include FIRST_MILESTONE.md; existing content there was considered separately by the primary agent.

## Findings and disposition

| Finding | Primary-agent assessment | Applied change |
|---|---|---|
| Relay wording appears beside M1 requirements | Clarification needed: the PRD spans multiple milestones, not a contradiction in the product direction | PRD explicitly places relay statuses in M2; M1 shows direct delivery only |
| Return messages lack responder-side receipt wording | Accepted gap | PRD and system design specify requester-device receipts for each responder message; security limits issuer authority; validation covers both directions |
| Handling visibility, withdrawal disposition, and reopen need clearer semantics | Accepted gap | Public shows received command handling updates; command explicitly records withdrawal disposition; resolved-to-open requires a new revision and reason |
| Required transport permission readiness is underspecified | Accepted gap | Exercise entry includes supported capabilities, permission state, and foreground notice; validation distinguishes radio permission failure from optional location denial |
| Coordinator setup and optional operator attribution need a place | Partially accepted as a design default | Coordinator-only setup within responder entry; security implementation remains SEC-01-gated. Verified command identity and optional unverified operator label remain distinct |

No new transport, cryptographic library, operating-system support, or device compatibility was inferred from the review. The five findings are design judgments, not measured field evidence. Relay, sensor, AI, and operational-launch scope remains deferred.

## Current evidence

- Both public and responder screen families remain in FIRST_MILESTONE.md.
- The screen execution plan includes normal flows and failure variants.
- Development tool availability is recorded in DEVICE_INVENTORY.md; physical endpoint inventory remains incomplete.
- Figma draft: [Offline Rescue — Direct SOS](https://www.figma.com/design/KfslxdEf2XarwLbSEDzbJS?node-id=4-333), in the user-selected Archit Jaiswal's team. Exact identifiers and read-back evidence are stored in [the state ledger](design/figma-state.json).
- No engineering task has been marked complete by this review.

## Figma checkpoint evidence

- Eight screen families are represented by 35 editable screen/state snapshots: public frames 390 × 844, responder frames 1024 × 768. These are design canvases, not compatibility claims.
- Four prototype starting points exist: overview, public SOS, responder handling, and interrupted updates. Successful writes recorded 65 navigation links plus three back actions. Read-back validated 45 links inside product screen frames; the additional 20 links are in the explicitly separate demo overview/browser.
- All 35 screen frames are valid top-level destinations. Read-back found no screen-content overflow, no image-filled UI layers, and Inter as the single font family. All UI content is editable text, frames, and local component instances.
- Rendered inspection covered the public normal-flow composition, public compose and acknowledgment views, responder request detail, and late-update handling. It exposed text/label sizing and container-height defects, which were repaired; post-fix renders showed readable, uncut content in these reviewed views.
- Explicit links cover public compose/review/save, responder inbox/detail/acknowledge/reply, assignment/resolution, and acknowledged/disconnected correction/follow-up/withdrawal. These are declared-state walkthroughs; native input, persistence, transport, signing, and permission changes are not implemented or tested.

## Remaining limitations

- The Apple iOS/iPadOS library import was denied. This draft uses a small local Inter-based component set, not a verified Apple UI-kit implementation.
- Public update controls before acknowledgment and native settings/revalidation controls are visual-only. No browser presentation replay or native accessibility/device test was performed; graph validation is not evidence of runtime behavior.
- A further responder-side received-by-requester example was planned but not created: the Figma Starter MCP tool-call allowance was reached. The requester-facing acknowledgment/reply and responder return-message-waiting examples exist; fully refining the return-receipt view remains design work.
- Because these limitations remain, the full design acceptance checkpoint is not declared complete. NET-01, SEC-01, and M1 remain incomplete.


## Native presentation checkpoint — 2026-10-09

Implemented directly in SwiftUI; the earlier Figma draft is unchanged. Public request and responder workspace now use consistent navy/teal cards, semantic native type, clear action/history hierarchy and separate device/human/handling facts. Technical setup is in a sheet; connection/queue/save/error state stays on the primary surface. All prior workflow actions and manual transport controls remain available. No engine/security/store behavior changed.

Signed simulator build and 96 Swift checks pass. Existing paired iPhone 17 Pro and iPad Pro 11 M5 synthetic histories were inspected, networking stopped, with Setup/pairing/back/Done exercised without trust changes. Independent Claude Opus 5.5/medium review prompted clearer human acknowledgment wording and shell-owned public draft bindings across size-class changes. Final phone type fits without truncation. Dark mode, large accessibility sizes, empty state and runtime Split View remain unchecked; these are not claimed as verified. [Current captures](../README.md#two-interfaces-one-workflow), [plan and verification](superpowers/plans/2026-10-09-presentation-redesign.md).


## Dark operational-console revision — 2026-10-09

User rejected the prior UI and illustrated demo and explicitly selected a dark operational console. Current SwiftUI uses graphite surfaces, crisp SF typography, amber accents, a compact connection strip, thin-separated facts and conversational messages. Public update and responder handling controls use sheets/menus; main actions stay in bottom bars. Introductory delivery guidance is expandable. All workflow/controller actions remain in source; no engine/crypto/transport/store changes.

Parent signed build and 96 Swift tests pass. Final retained-history phone/tablet static captures inspected; full interactive navigation, new send/ack/reply, large text and Reduce Motion replay are blocked by native computer-use startup. Current screenshots establish rendering only. [Active execution ledger](superpowers/plans/2026-10-09-live-product-redesign.md) records the blocker and precise next capture steps. Earlier Figma and films are historical; no Figma write or new live video is claimed.
