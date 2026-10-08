# First milestone: screen design and transport proof

Status: screen brief approved; execution preparation in progress · 2026-10-07

**One product: a person sends an SOS; a firefighter receives it, acknowledges it, and replies. Both interfaces use the same C++ engine.**

This brief translates the [PRD](PRD.md) into the first design work. It does not replace the [task backlog](TODO.md), choose a radio API, or claim that an app exists.

## What we do next

1. Review this screen brief and turn it into editable Figma designs for the public iPhone and responder iPad flows.
2. Record available physical devices and development/provisioning access (DISC-02).
3. Run the synthetic direct transport experiment (NET-01). Compare feasible adapters on that hardware; record foreground, disconnect/reconnect, lock, and background behavior.
4. Complete the identity/envelope decision (SEC-01), then establish the Swift/C++ toolchain and build M1.

Design work can proceed while we gather hardware details. Product scaffolding follows the transport and security gates. The design uses manual location, prepared exercise membership, one command authority, and synthetic participant data. Relays, automatic floor estimates, AI, and public release follow later milestones.

## First Figma package

Working title: **Offline Rescue — Direct SOS**. Use a neutral, readable visual style, large text and controls, text labels for status, and a visible exercise identifier. A location map is not required.

| Screen | Contents and actions |
|---|---|
| 1. Prepared exercise entry | Exercise name, verified membership and role, required transport permissions/capabilities, local connection state, and foreground notice. Public and responder variants; coordinator-only setup lives within the responder variant. Unverified membership cannot open a trusted responder session. Provisioning mechanics remain subject to SEC-01. |
| 2. Public: describe request | Situation; building/landmark; floor and room if known; people count if known; optional location sharing. Permit unknown floor and denied permissions. Continue to review. |
| 3. Public: review and send | Show entered information and its source. Edit or explicitly send. Unsent form data is a draft; sending must commit locally before showing a waiting state. |
| 4. Public: request and conversation | Request summary, delivery facts, handling status, acknowledgment, replies, and local connection state. Send follow-up, correct location, or request withdrawal. Track each outgoing update separately. |
| 5. Public: correction/withdrawal | Sheet variants linked to the original request. Preview the correction before sending; explain that requesting withdrawal does not mean the responder received it or resolved the request. Keep the conversation available. |
| 6. Responder: inbox | Requests with reported location, observed/received timing, acknowledgment and handling status, unread updates, and connection state. Empty and disconnected variants. Do not invent AI urgency scores. |
| 7. Responder: request and conversation | Reported location and source/time; original and updated content; acknowledgment action; reply composer. Distinguish acknowledgment of the initial request from later updates. Receipt alone never triggers acknowledgment. |
| 8. Responder: handling sheet | Explicit assignment details, resolution with reason, withdrawal disposition, and reopen for late updates. A saved local action can still be waiting to reach the public device. |

Figma interactions cover send → waiting → received → acknowledgment → reply, plus correction and withdrawal. These are simulated transitions for reviewing the design; they do not demonstrate networking.

## Required state variants

- **No responder reachable:** “Waiting to send.” Preserve the request and disclose that no responder receipt is available.
- **Device received, no human action:** “Received by responder device.” Keep acknowledgment separate.
- **Human acknowledgment:** “Acknowledged by responder.” Do not imply dispatch or arrival.
- **Disconnected after receipt:** retain received/acknowledged facts; show the current connection problem separately.
- **Follow-up pending:** the original acknowledgment remains, but the new correction, message, or withdrawal shows its own waiting status.
- **Storage full or commit failure:** “Could not save your request.” Retain editable input where possible and offer retry; never show a queued success.
- **Time uncertain:** show observation time uncertainty separately from time received on this device. Reconnection does not make old location fresh.
- **Late update after resolution:** flag new information for responder review; do not silently reopen or discard it.
- **Responder return message pending:** show “Waiting to send to requester” until its verified destination receipt arrives. “Received by requester device” never implies the person read it.
- **Required transport permission denied:** show blocked exchange with a settings/setup action; manual location entry still works but cannot restore the radio link.

## Choices and self-review

We choose a text-first inbox and conversation over a map-first dashboard: manual location supports the initial workflow without suggesting measured tracking. Separate status labels are simpler and more accurate than one progress bar, because delivery and handling can advance independently. A shared exercise-entry design preserves two distinct role interfaces; it does not permit public users to grant themselves responder authority.

Correctness review checks per-message receipts and update handling. Privacy review keeps synthetic data in mockups and leaves keys/enrollment to the security gate. Maintainability review maps labels to engine facts rather than separate UI logic. Accessibility review requires readable text and status comprehension without color. Simplicity review defers maps, sensors, and AI while retaining correction, withdrawal, assignment, and resolution from M1.

## Acceptance and handoff

The design checkpoint is complete only when both flows and required variants exist in Figma, the interactions work, rendered screens have been inspected for clipping/readability, and status wording agrees with PRD section 6 and SYSTEM_DESIGN sections 3–7. Check large-text and VoiceOver behavior on real devices during M1; mockups cannot establish native accessibility.

NET-01 remains incomplete until there is recorded physical-device evidence. M1 remains incomplete until the mandatory scenarios in [validation](VALIDATION.md) pass. A designed screen or a written experiment is not an engineering completion.

The user approved this direction and sharing the five named project documents with Claude Code on 2026-10-07. The read-only review completed; [review notes](DESIGN_REVIEW.md) record findings and their disposition. The [design execution plan](superpowers/plans/2026-10-07-direct-sos-design.md) covers the Figma checkpoint; the [device inventory](DEVICE_INVENTORY.md) records verified development tools.

Open inputs: physical endpoint device/OS inventory and Figma team selection. These are configuration choices, not requests to reauthorize the project.
