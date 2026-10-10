# Optional device location — execution plan

Authorized by the user's “go ahead.” Scope: foreground, opt-in one-shot coordinates; manually reported floor; review before SOS; display provenance, accuracy and observation time on both interfaces and in history. No automatic floor/building inference, geocoder, background tracking, new dependency, physical range claim or phone-relay implementation.

## Evidence and design

Apple Core Location `requestLocation()` may return a less accurate fix or fail; `requestWhenInUseAuthorization()` requires a foreground permission prompt and a purpose string. Sources consulted 2026-10-09:
- https://developer.apple.com/documentation/corelocation/cllocationmanager/requestlocation()
- https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization()

Use one manager per capture, identity-fenced callbacks, a bounded timeout and cancellation on leaving foreground or view/session context. Accept finite valid coordinates, nonnegative accuracy and fixes no older than 60 seconds or more than 5 seconds ahead at capture. These freshness thresholds are prototype defaults, not safety assurances. Retain exact observation timestamp thereafter; never label it live. Reduced accuracy remains usable and visibly identified.

A version-tagged JSON location report travels inside the existing bounded reported-location field. C++ continues to own durable workflow, original/correction history, wire validation and delivery facts. Swift owns native observation semantics and presentation. Legacy strings remain readable; malformed tagged reports display an unavailable notice rather than invented coordinates. No ORX1 or SQLite migration. Old clients would display the tagged text; matched demo clients required for structured presentation. A new binary protocol/schema is disproportionate to this checkpoint.

Manual reported text and floor are distinct from device observation. Sample building remains explicitly sample; coordinates do not establish that building or floor. Capture never sends. SOS review freezes its payload; corrections show the full draft before explicit send. Persist only after send, using existing storage; opt-in UI explains prototype local history is unencrypted. Validate only synthetic simulator coordinates; no private-data exercise is authorized.

## Checkpoints / acceptance

1. Add pure Swift validated report codec and tests: legacy, malformed/oversized, invalid/nonfinite coordinates, freshness boundaries, reduced accuracy, immutable serialized snapshots and real C++ store/history restart.
2. Add native one-shot adapter and UI capture/remove/error/cancel states; show structured report in public, responder and conversation history. Preserve manual-only flow and status semantics.
3. Run Swift suite, CTest and signed simulator build. Inspect native simulator permission/capture/review/send/correction and responder rendering using synthetic coordinates. Preserve existing paired secure simulators.
4. Review diff, document exact evidence/limits, publish scoped verified checkpoint.

## Critique and revision

Correctness: device coordinates cannot confirm a manually named building; separate labels. Simplicity: keep existing bounded field, avoid geocoding/maps. Privacy: explicit capture and send, no auto-start, no raw-coordinate logs; unencrypted history disclosed. Maintainability: platform adapter isolated from portable report validation. Testing: real C++ persistence and legacy fixtures, native checks beyond build. UX: denied/unavailable never blocks manual SOS; timestamp remains visible after delay; stale captured draft can be sent as an explicitly dated observation rather than silently refreshed. Review freezes before send. No new worktree needed: one sequential implementation, initially clean checkout, no concurrent writer.

## Execution / review

All four checkpoints completed; exact commands and native evidence in experiments/rescue-demo/LOCATION_CAPTURE.md. Tests first failed for missing report types, then passed after implementation. Final totals:96 existing Swift Testing +4 XCTest,43 CTest; signed simulator build passes. Secure real-socket regression now includes structured observation. Native permission flow found transient inactivity cancellation; revised to background-only cancellation and repeated successfully. Diff reviewed for bounds, legacy compatibility, user review, provenance, secret exposure and unrelated changes. No broad LOC-01 or full-product task marked complete.
