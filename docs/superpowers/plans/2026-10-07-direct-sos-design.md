# Direct SOS Screen Design Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an editable Figma prototype covering the public SOS and responder acknowledgment/reply workflows, including interrupted exchange.

**Architecture:** Eight screen families share delivery terminology and exercise identity. Public phone screens and responder tablet screens remain separate. Prototype interactions simulate engine facts; they do not perform networking.

**Tech Stack:** Figma Design and its connected Plugin API tools; Markdown for evidence and handoff. No app dependencies or code in this checkpoint.

**Spec:** [First milestone](../../FIRST_MILESTONE.md), [PRD](../../PRD.md), and [system design](../../SYSTEM_DESIGN.md).

## Global constraints

- One product with both public iPhone and responder iPad interfaces; shared C++ engine in future implementation.
- Prepared exercise membership, synthetic data, manual location, one command authority.
- Separate delivery, human acknowledgment, and request handling. No dispatch or arrival implication.
- Track corrections, follow-ups, and withdrawals independently of the original message.
- Preserve reported location, source time, receive time, and clock uncertainty.
- No relays, sensors, AI, real-time map, public release, or product scaffolding in this checkpoint.

## Review focus

1. No responder reachable: sending leaves a durable waiting request, not a success implying receipt.
2. Storage commit fails: retain input and show failure, never a queued state.
3. Connection lost after acknowledgment: retained facts remain visible while new messages wait.
4. Old location or unknown floor/time: show uncertainty without fabricated coordinates or freshness.
5. Late correction or withdrawal after resolution: retain the update and require explicit responder disposition.

## Affected artifacts and execution

Figma file: **Offline Rescue — Direct SOS**, in the user-selected team. Screens, state variants, and prototype links are contained in that file. Local evidence is recorded in `docs/DESIGN_REVIEW.md`; the verified file URL will be added to `docs/FIRST_MILESTONE.md`. Do not create a second file when retrying a partially successful creation.

### Task 1: Establish the design file and shared conventions

**Consumes:** selected Figma team and approved first-milestone brief. **Produces:** file key, page ID, verified font choices, and layout conventions.

- [x] Resolve the user-selected team using the Figma creation skill; create one Design file.
- [x] Inspect its pages and existing contents before writing nodes; retain returned identifiers.
- [x] Use public 390 × 844 and responder 1024 × 768 frames as draft design canvases, not supported-device claims. Choose an available readable font, neutral backgrounds, dark text, and one accent; status must include text.
- [x] Record all created/mutated IDs and reuse them for later changes.

### Task 2: Create both direct-exchange journeys

**Consumes:** file/page IDs and conventions. **Produces:** eight screen families and linked normal-flow transitions.

- [x] Build exercise entry, public describe/review/conversation/update screens, and responder inbox/detail/handling screens from the spec's inventory.
- [x] Use one synthetic exercise and one consistent request throughout: Training Hall, reported Floor 2, Room 204, two people, no automatic estimate.
- [ ] Link send to waiting; demonstrate verified device receipt as a separate state; link explicit responder acknowledgment and reply to the corresponding public views.
- [x] Include correction, withdrawal, assignment, resolution, and explicit reopen actions. Mark the prototype's transitions as simulated in its overview.
- [x] Inspect a rendered composition of the public and responder flows; fix clipped text, crowding, or ambiguous hierarchy with targeted changes.

### Task 3: Create failure variants and review

**Consumes:** completed screen IDs. **Produces:** reviewed state variants and handoff evidence.

- [ ] Add each review-focus scenario to its owning screen, plus empty inbox, denied location permission, blocked transport permission, disconnected inbox, follow-up waiting, and responder-to-requester delivery variants.
- [ ] Replay the public send/correct/withdraw and responder acknowledge/reply/assign/resolve flows. Check that the original acknowledgment never labels a new message as acknowledged.
- [ ] Verify unknown floor remains allowed, receive time does not replace observation time, and public users cannot create verified responder authority.
- [ ] Inspect the rendered failure variants and confirm statuses remain understandable without color. Native large-text and VoiceOver checks belong to M1.
- [x] Record the file URL, screen IDs, interactions checked, rendered inspection, remaining issues, and simulated-network limitation in `docs/DESIGN_REVIEW.md`.

Checkpoint evidence (2026-10-07): see [design review](../../DESIGN_REVIEW.md) and [state ledger](../../design/figma-state.json). Unchecked steps remain incomplete: the draft has separate declared-state examples and valid links, but not a replayed complete cross-device workflow or complete return-receipt variants. The Starter MCP tool-call limit stopped further refinement. No engineering task was completed.

## Self-review and next gate

All eight screen families and required states have an owning task. Local link checks validate this plan's references; Figma evidence must validate the actual artifact. This plan cannot complete DISC-02, NET-01, SEC-01, or M1. After device inventory is confirmed, execute the synthetic transport investigation before choosing the production adapter or scaffolding the apps.
