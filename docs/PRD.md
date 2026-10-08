# Product requirements

> Bounded portfolio checkpoint (2026-10-08): [secure exchange evidence](../experiments/rescue-demo/SECURE_EXCHANGE.md) now establishes manually paired signed/encrypted Apple endpoints with C++ durable state. Full-product enrollment, private storage and physical gates remain open; CryptoKit is an Apple adapter, not portable C++ cryptography.

> Current execution status (2026-10-08): see [current state / resume](CURRENT_STATE.md) and [portfolio tasks](TODO.md#current-portfolio-tasks). This document retains its product requirements, proposal or dated evidence; it does not claim that all described capabilities are implemented.

Status: portfolio-first scope with retained long-term product requirements · updated 2026-10-08

## 1. Outcome

Enable a person to submit a location-bearing assistance request and exchange replies with an enrolled responder over an available local device network when internet or cellular service is unreliable. Show the true delivery state and the limitations of location information.

This is one project with public and responder interfaces. **The current deliverable is a working, demonstrable résumé project**, not an organizational pilot or sale. Prioritize reliable local messaging, durable recovery, understandable native UI and reproducible measured evidence. A controlled physical demonstration follows when devices are available. Commercial discovery and partner deployment are deferred. See [current state](CURRENT_STATE.md) for implemented capabilities and the next task, [decisions](DECISIONS.md) for the scope change and [research](RESEARCH.md) for supporting evidence.

## 2. Problem and audience

Two problems intersect: communication may fail, and indoor location may be ambiguous. Improving only one does not solve the complete rescue exchange. Nearby relays help only if a useful contact path eventually reaches a responder.

| Persona | Need | First exercise behavior |
|---|---|---|
| Person seeking assistance | Explain the situation, provide location, know whether anyone received it | Enrolled volunteer plays the public role |
| Responder | Read requests, assess provenance, acknowledge and reply | Enrolled exercise responder uses an iPad |
| Exercise coordinator | Set up devices and incident membership, observe failures | Creates the exercise and verifies identities |
| Relay participant | Forward without reading private requests | Opts in to an enrolled relay role |
| Training officer / potential buyer | Evaluate usefulness and deployment effort | Observes drills and reviews evidence |

The eventual public user must not need a fire-department employee account. Open public onboarding is a later design question; controlled enrollment in the prototype does not establish a scalable public deployment.

## 3. Current delivery scope and longer-term stages

For the portfolio version, success means both interfaces run, independent endpoints exchange SOS/acknowledgment/replies, interrupted delivery recovers without fabricated statuses, and documented tests/demos support every résumé claim. Those local capabilities are implemented in the sample app; physical offline verification remains pending. Next establish reproducible measurements, then evaluate bounded relay and urgent-message scheduling. Encryption/identity review precedes any private data. On-device language assistance is optional later work. Selling to organizations, discovery interviews and pilot operations are not prerequisites for this deliverable.

The following table preserves the larger product roadmap; it is not the current execution order.

| Stage | Included | Excluded from this stage |
|---|---|---|
| M1: direct rescue exchange | Both interfaces; manual location; offline SOS, human acknowledgment, reply; durable local records | Multi-hop, automatic floor estimation, AI, public distribution |
| M2: interruption and relay | One or more measured relay paths; restart recovery; queue limits; deduplication | Guaranteed reachability or unattended iPhone operation |
| M3: indoor research | Sensor capture, baseline estimates, explicit uncertainty, reproducible evaluation | Guaranteed room location or validated structural-fire performance |
| M4: supervised organizational pilot | Workflow review, exercises, deployment support, replay | Automatic dispatch or replacement of existing emergency procedures |
| Later capabilities | Firefighter tracking, multi-command coordination, AI, partner integrations | Require their own design and evidence before inclusion |

The original product MVP is M1 plus M2. The active portfolio scope above is a smaller evidence-backed deliverable; M3 remains optional research within the same project.

## 4. Primary workflows

### Public request

1. Join a verified exercise using the coordinator's enrollment method. Install and prepare apps before internet is removed.
2. Open the assistance screen. Enter a short description, building/landmark, floor if known, room if known, and people count if known.
3. Optionally grant location permission. Never require it to submit a manually located request.
4. Review the information, then explicitly send. Persist locally before claiming it is queued.
5. In M1, show local connection status and verified responder-device receipts. M2 adds intermediate forwarding attempts and relay receipts. Without a verified destination receipt, show the request's actual waiting/delivery state.
6. Display the responder's acknowledgment, replies, assignment, resolution, and withdrawal disposition when received, attributed to the verified command endpoint. Allow correction, follow-up, and withdrawal; each new message has its own delivery state.

### Responder handling

1. Enter an exercise with verified responder authority.
2. See requests in a list; a map or floor schematic is supplementary, not required for M1.
3. Open a request with reported location, sensor estimate if any, observation age, and provenance.
4. Explicitly acknowledge the request; optionally send a reply.
5. Record an assignment or handling status. Mark resolved only through an explicit authorized action.
6. Reconcile duplicate delivery and out-of-order follow-ups without duplicating the request.

The responder sees outgoing delivery separately for each acknowledgment, reply, and handling update: saving an action locally does not establish that the requester received it. An optional operator display label is not proof of individual identity; M1 verifies the command endpoint authority.

### Prepared-exercise readiness

Before removing internet, verify enrollment, applicable transport permissions, supported device capabilities, and a synthetic round trip. Exercise entry includes a coordinator-only setup path on the responder interface; credential issuance mechanics are frozen in SEC-01, not inferred from a role selector. No third coordinator app is required for this design checkpoint.

For the initial foreground prototype, show “Keep this app open for local exchange.” If a required transport permission is denied or hardware is unsupported, show the blocked communication state and a settings/setup action. Manual location entry remains usable, but cannot restore a blocked radio link. Do not claim permission success proves responder reachability.

### Failure and reconnection

When connections disappear, retain requests and outgoing receipts locally. Show disconnected state. Retry when a compatible enrolled peer becomes available. Restored communication must not reset observation age or fabricate acknowledgment.

## 5. Functional requirements

| ID | Requirement | Acceptance scenario |
|---|---|---|
| FR-01 | Preserve public and responder interfaces | One participant submits and one responder handles the same request |
| FR-02 | Prepare exercise membership offline after initial setup | No login or cloud lookup is needed during the prepared drill |
| FR-03 | Submit with manually entered location | Location/motion permission denial does not block sending |
| FR-04 | Persist before queued confirmation | Restart immediately after submission; the same request remains |
| FR-05 | Separate device receipt from human acknowledgment | Device receipt alone never displays responder acknowledgment |
| FR-06 | Reply and acknowledge through the local transport | The participant receives both without internet |
| FR-07 | Correct and withdraw a request | Updates reference the original; withdrawal is not shown as rescue completion |
| FR-08 | Preserve reported and estimated location independently | A conflicting estimate does not overwrite a reported floor |
| FR-09 | Show age and unavailable/uncertain location | Old, missing, or clock-uncertain observations are visibly identified |
| FR-10 | Deduplicate and reconcile messages | Repeated frames produce one request and one instance of each event |
| FR-11 | Support interrupted exchange in M2 | A relay stores a request and forwards after a later contact |
| FR-12 | Enforce responder authority | A relay or public participant cannot create trusted responder status |
| FR-13 | Offer accessible status and forms | Text/scalable UI and semantic labels convey status without color alone |
| FR-14 | In M4, export an explicit, redacted exercise record | Coordinator chooses export; no automatic cloud upload occurs |

## 6. Status language

Delivery state is per message; handling state is per request. These can differ. A withdrawal message may still be queued after the original SOS was acknowledged.

| Fact | User-facing language | Does not imply |
|---|---|---|
| Durable local message | Waiting to send | Anyone else has received it |
| Relay accepted durable custody locally | Forwarded to a nearby device | A responder received it |
| Authorized command device committed receipt | Received by responder device | A person reviewed it |
| Authorized responder explicitly acknowledged | Acknowledged by responder | Assistance is assigned or dispatched |
| Responder assigned handling | Assigned, with responder-provided details | Guaranteed arrival |
| Authorized responder closed request | Marked resolved by responder | Independent verification of the outcome |
| Participant requested withdrawal | Withdrawal requested | Responder has received the withdrawal |
| Command recorded a withdrawal disposition | Withdrawal noted by responder, with disposition | Automatic resolution or independently verified outcome |
| Responder action committed locally without requester receipt | Waiting to send to requester | Requester received the acknowledgment/reply/update |
| Intended requester durably committed responder message | Received by requester device | Requester read or understood the message |

Intermediate relay status applies to M2. For either direction, every receipt must bind the exact message and intended destination identity; it is not an application read receipt.

Do not use reassuring automatic copy such as "help is on the way" based solely on connectivity, relaying, or receipt.

## 7. Quality requirements

- Core exchange continues without DNS, cellular data, push notifications, or cloud services during the prepared exercise.
- Failure is explicit: disconnected, unsupported transport, permission denied, queue full, unreadable envelope, and expired forwarding window.
- Local persistence, message integrity, identity checks, and resource limits are required before organizational pilot data.
- Private bodies are readable by their intended endpoints, not transit relays. See [security](SECURITY_PRIVACY.md).
- Foreground-only operation is an accepted first-prototype constraint. Background and screen-lock behavior must be measured and disclosed before expanding claims.
- No media attachments in the MVP. Text and structured location keep the first data path small and testable.
- No claimed location accuracy, universal range, guaranteed delivery deadline, or safety certification exists at this stage.

## 8. Success and evidence

M1 succeeds when the direct drill scenarios in [validation](VALIDATION.md) pass on physical devices and participants understand the statuses. M2 succeeds when the relay and recovery scenarios pass within the documented test topology. M3 succeeds as research when performance—including unavailable and wrong estimates—is measured on held-out conditions; a weak result is evidence to revise the approach, not permission to hide failures.

Adoption success requires a partner who confirms a workflow benefit and a practical deployment path. Interview counts or a polished demo are not proof of willingness to purchase.

## 9. Boundaries and later capabilities

No 911/CAD integration, automatic dispatch, escape-route recommendation, injury diagnosis, or replacement of radio/PASS procedures is in the MVP. Open public use requires trusted responder discovery, installation/readiness planning, abuse controls, and a deployment model.

Firefighter tracking remains in the larger vision but follows the civilian-to-responder workflow. AI translation/summarization remains optional and must preserve original text and critical facts. The model is never responsible for responder authority, delivery status, or location coordinates.
