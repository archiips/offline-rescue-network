# Validation and supervised pilot

> Current execution status (2026-10-08): see [current state / resume](CURRENT_STATE.md) and [portfolio tasks](TODO.md#current-portfolio-tasks). This document retains its product requirements, proposal or dated evidence; it does not claim that all described capabilities are implemented.

Status: proposed verification program, v0.1 · 2026-10-07

## 1. Evidence levels

| Evidence | What it can establish | What it cannot establish |
|---|---|---|
| Unit/protocol fixtures | Deterministic state, parsing, ordering, resource behavior | Physical radio or sensor performance |
| Scenario runner | Behavior under chosen contacts and failures | Real-world mobility or iOS runtime |
| Physical-device drill | Observed performance for the recorded matrix/topology | Universal reachability or operational safety |
| Partner usability session | Task understanding and deployment issues | Purchase commitment or live-incident effectiveness |
| External / intended-use evaluation | Evidence for the evaluated use and conditions | Claims beyond those conditions |

Use [NIST localization test-method guidance](RESEARCH.md#r15) as a reference when designing M3. Our internal tests are not certification.

## 2. M1 drill protocol

Prepare an iPhone and iPad with installed apps, enrollment, charged batteries, and synthetic participant data. Record exact models, OS/app versions, radio settings, permission state, and test environment. Disable cellular data and remove usable internet connectivity while leaving radios needed by the tested adapter enabled. Confirm the local path does not depend on an access point or hidden gateway in the no-access-point variant.

Before disconnecting internet, verify prepared enrollment, transport-specific permissions/capabilities, and a synthetic direct exchange. Repeat with a required transport permission denied, where applicable: communication is visibly blocked and manual draft entry remains available. Verify that denied location permission alone still allows local communication and manual submission.

Run 20 scripted direct round trips across the test session. For each: submit a request with reported building/floor, confirm local persistence, receive at responder, have a human acknowledge and reply, and verify return messages. Capture timestamps and delivery/handling facts. Repeat the mandatory failure cases below.

**Engineering target:** all 20 scripted requests and acknowledgments arrive within 30 seconds each while the prepared foreground link is available. Report every failure and latency, including reruns. This target is a prototype acceptance setting, not an emergency-service promise. If it fails, fix/reassess the transport before declaring M1 complete.

## 3. Required scenario matrix

| ID | Scenario | Acceptance |
|---|---|---|
| V-01 | Prepared direct exchange without internet | Public request, human acknowledgment, and reply complete with correct identities |
| V-02 | No responder reachable | Request remains waiting; no receipt or rescue promise is fabricated |
| V-03 | Location/motion permission denied | Manual submission and responder reply remain usable |
| V-04 | Restart after local submission | Same ID and durable request survive; retry does not duplicate it |
| V-05 | Responder device receipt without human action | Public UI distinguishes device receipt from acknowledgment |
| V-06 | Duplicate and out-of-order events | One request; stable facts; follow-up delivery tracked independently |
| V-07 | Correction and withdrawal during an outage | Both eventually reconcile; withdrawal is not automatic rescue resolution |
| V-08 | Spoofed responder / wrong exercise | Invalid authority cannot change trusted delivery or handling state |
| V-09 | Oversized input, queue full, bad frame | Bounded handling and actionable errors; no false durable acceptance |
| V-10 | Lock, background, force quit, reopen | Measured loss of capability disclosed; pending state recovers when possible |
| V-11 | Delayed location and mismatched clocks | Original time preserved; uncertain/stale source never appears live |
| V-12 | Three-device contact sequence A→B, later B→C | Real intermediate forwarding and returning acknowledgment demonstrated |
| V-13 | One-way contact or return path missing | Arrival at command does not fabricate receipt at the public device |
| V-14 | Relay shutdown and database recovery | Durable custody resumes; corruption/storage failure is reported |
| V-15 | Exercise closure and local deletion | Local networking stops on known closure; retention and explicit deletion work |
| V-16 | Missing baseline or conflicting floor information | Estimate abstains or displays conflict; reported floor remains |
| V-17 | Accessibility and status comprehension | Users can identify actual delivery state without color alone |
| V-18 | Optional laptop adapter | Actual phone/laptop interoperability is recorded, not inferred |
| V-19 | Consented exercise export and replay, M4 | Coordinator explicitly exports; redaction, destination, and retention are checked |

V-01/V-06 also verify responder-to-requester receipts: acknowledgment, reply, and handling update remain waiting on the responder until the intended requester commits them and its authenticated receipt returns. V-07 includes command-recorded withdrawal disposition and explicit resolved-to-open revision for late information; receipt alone does not trigger either action.

V-01 through V-11, V-15, and V-17 gate M1; relay scenarios gate M2; V-16 plus the localization evaluation gate M3. V-18 gates adding laptop participation to a supported deployment claim. V-19 gates M4 export/replay.

## 4. M2 network experiments

Run equivalent traffic/contact schedules against direct-only, bounded naive forwarding, and the proposed priority/fairness policy. Hold offered load, message sizes, topology, and random seeds constant. Include persistent clusters, moving bridge, churn, buffer exhaustion, asymmetric contact, short contacts, ordinary traffic mixed with assistance events, and reconnect storms.

Measure successful/unsuccessful delivery, deadline misses against an explicitly chosen experimental deadline, latency distributions, total control and payload bytes, duplicates, queue residence, fairness by sender, and battery/CPU on physical devices. Do not infer improved latency from delivered messages alone.

Cooperative limits are not security guarantees. Include malicious/ineligible-peer injection tests separately from performance tests.

## 5. M3 localization verification

Follow [localization](LOCALIZATION.md). Validate unit conversion, sensor gaps, reference reset, floor mapping, permissions, and unavailable estimates before modeling. Evaluate held-out buildings/devices; preserve ground truth separately from participant reports. Include original sensor-to-display age across interrupted communication.

All claims must name the device matrix, reference conditions, dataset coverage, and error/availability tradeoff. Operational fireground claims require separate equipment and intended-use evaluation.

## 6. User interaction checks

Conduct a small formative session with 5 public-role participants and 2 responder-role participants if available. These are recruitment targets, not representative population estimates. Ask participants to send/correct/withdraw a request and explain each displayed status without coaching. Ask responders to identify old/conflicting location and distinguish acknowledgment from assignment.

Record confusion and errors, not only satisfaction. Any wording that makes a participant believe an undelivered request reached responders is a release blocker for the drill. Inspect rendered screens on supported physical devices with large text and VoiceOver before M1 handoff.

## 7. Organizational pilot protocol

A pilot requires a named coordinator, agreed scenario, supported equipment matrix, synthetic/consented data policy, purpose, stop conditions, and responsibility for existing communication procedures. Default: a non-emergency building exercise, no hazardous exposure, one command authority, and no 911 integration.

Run setup, normal exchange, planned disconnect, correction/withdrawal, and replay/export. Compare with the partner's current exercise workflow. Record time to set up, operator effort, message/location performance, misunderstandings, equipment failures, and support needed.

Stop the exercise for ambiguous delivery/authority, false current location, uncontrolled data exposure, unsafe equipment conditions, or coordinator instruction. Preserve redacted evidence for diagnosis; restore the partner's ordinary exercise workflow. A failed pilot is an input to redesign, not a marketing success.

## 8. Progression criteria

- **M1:** complete mandatory physical/UI checks; no false delivery/authority states; report the direct target honestly.
- **M2:** prove the isolated relay path and recovery; document unsupported lifecycle conditions and capacity limits.
- **M3:** reproducible held-out report; approved presentation of experimental estimates and failures.
- **M4:** named partner completes the agreed exercise and identifies a useful workflow plus remaining barriers.
- **Operational proposal:** separate review of intended use, applicable equipment/integration requirements, security, support, procurement, and independent validation. No internal milestone alone authorizes a safety claim.

## 9. Evidence bundle and commands

Each run records scenario ID, date, build/configuration, device matrix, topology, offered load, pass/fail, raw timing/metric artifact, redaction/consent classification, and reviewer. Preserve unsuccessful runs.

There are no software verification commands in this documentation-only repository. ENG-01 must establish actual C++ tests/build/sanitizers, Swift tests/build, and UI/device procedures from the chosen manifests. Document the exact commands and outcomes with each implementation milestone. Do not copy speculative commands into completion reports.
