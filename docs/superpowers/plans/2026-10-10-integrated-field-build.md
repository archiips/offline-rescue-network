# Integrated field-test build implementation plan

> Execute in the existing authorized task, with independent ChatGPT review; preserve user-local Xcode signing changes.

**Goal:** Produce one staged, reproducible field-test release of communication, preparation and location research.
**Architecture:** Existing C++ workflow/queues/graph and Swift security/native adapters. Implement and verify sequential coherent checkpoints; do not replace completed subsystems.
**Spec:** `docs/superpowers/specs/2026-10-10-integrated-field-build-design.md`.

## Constraints and review focus
No invented UW map/authority, no contact-to-floor inference, no private keys/personal coordinates in publication, no GUI except Computer Use. Preserve both audiences and all old histories. Review missing permissions, stale surveys, cross-floor coverage, absent relay destinations/attempt exhaustion, stop-after-await and cross-conversation receipt substitution.

## 1. Surveyed local Wi-Fi floor references
- [x] Add `swift/SurveyedWiFiMap.swift` plus `SwiftTests/SurveyedWiFiMapTests.swift`: <=64KiB/128 records, strict version/schema, campus/building/provenance/expiry, exact normalized BSSID and logical interval -20...200. Decode rejects duplicate conflicting keys, invalid ages/coordinates/strings. Use observation time/id for graph provenance; map membership grants no identity authority.
- [x] Extend `LiveResearchGraph.evaluate` with default-nil surveyed evidence; test fresh exact context, same SSID wrong BSSID, wrong campus, stale/expired map, cross-floor interval, contradictory sensor and contact-only cases.
- [x] Native local import/clear and explicit campus/building context in existing live research; preserve sensor-only sharing. Import cannot silently start sensors/network. Add synthetic map format guide, no real AP identifiers.
- [x] Run focused failing tests before implementation, full Swift suite and signed Simulator build; inspect native survey/Unknown/source controls; complete file-import interaction remains deferred and independent review. Publish only verified scoped files after the final combined checks.

## 2. Prepared-pair automatic foreground relay
- [x] Add eligible-flow C++ selection before attempts; regression proves absent/unreachable destination does not burn attempts or starve eligible other direction.
- [x] Add distinct relay-host/endpoint Bonjour routing hints and generation-fenced bounded workers. Keep exact ORL1/ORA1 validation, durable reverse receipts and explicit Stop/background semantics.
- [x] Verify real separate/nonoverlapping endpoint contacts, lost acceptance, restart exact bytes, hostile names, stopped worker and fairness. Build/render native controls; publication recorded below.

## 3. Registered delayed delivery
- [x] Write/critique exact credential-bearing first-contact admission and prepared responder-directory protocol against existing registry/cache ordering before implementation. No 10-second lease extension.
- [x] Implement per-public registered relay caches and bounded credential-verified admission; test revoked/expired authority, cross-public substitution, capacity/recovery and signed receipt-only confirmation.
- [x] Connect foreground relay discovery to registered public/inbox controls without manual emergency pairing; inspect retained public draft/research and responder/relay native controls; full three-device native delayed delivery stays deferred.

## 4. Organizer preparation and estimate integration
- [x] Implement bounded local preparation service/client with device possession and organizer-approved responder role. Retain offline signed profiles and explicit issuer trust during advance preparation. No UW identity claims.
- [x] Add separately dated estimated floor/provenance to reviewed location reports without changing manual reports; backward decode existing histories, strip raw Wi-Fi identifiers from all messages and preserve original timestamps through corrections.
- [x] Combine software scenario suite and field checklist, update CURRENT_STATE/TODO only on completed definitions, review and publish final tested checkpoint. Physical tests remain separately pending until devices/user are available.


## Execution and review record — October 11

Implemented all four bounded software milestones in the existing workspace. No issuer key/access approval, real campus enrollment, account backend, beacon installation or physical test was performed. User-local Xcode signing/project formatting changes remain excluded from publication.

Independent ChatGPT reviews found and corrected: fake destination attempt exhaustion (fresh signed readiness before eligible selection); relay adapter rotation ownership; malformed registered provisional growth (four-context bound/pruning); unselected authorized-responder cache poisoning (select before cache creation); valid equivalent-credential wrapper substitution (owner signature over complete wrapper plus metadata/zero-attempt checks); organizer cancellation on background; and expired conversation isolation (per-row relay batch failure keeps other participants usable). Regression fixtures retain valid signatures/structure while changing the relationship under test. Adapter rotation mutations failed and restored-source checks passed. No Claude fallback was used.

Native Computer Use on the existing iPhone 16 Pro/iOS18.3 Simulator preserved approved synthetic responder registration. Updated inbox visibly starts both direct and registered relay discovery. Participating as encrypted relay opens a stopped workspace, Start enables discovery, Stop visibly stops it, and returning reopens the retained inbox. Other demo modes retain public draft/manual Unknown floor. Opened its research sheet; inspected survey campus/building controls, explicit coverage/provenance entry, disabled reference capture without fresh AP evidence, Unknown graph and disabled dated-estimate use. Rendered layout inspected. No new location/motion/Keychain permissions were approved; no real AP identifiers or coordinates collected. Final Simulator screen is the retained public Training draft; rescue/research/host networking is stopped. Full native file import/error, positive real-sensor estimate, organizer issuance/trust, public-directory preparation and three-device relay walkthrough remain for the attended test session. Controller/socket tests do not substitute for those UI/device checks.

Verification commands and final outcomes are recorded after completion below. Repeated full runs reproduced a Wi-Fi timer defect: relative sleep began when its MainActor task eventually ran, extending the capture deadline. Changed it to the already captured absolute deadline, with no suspension when already expired. A delayed-task regression fails with the original relative timer and passes after restoration; cancellation/generation guards remain. A separate relay test observed public receipt commit before host acceptance removal and stopped too early; its bounded wait now requires both original assertions before Stop. No assertion or timeout was weakened. Final restored-source run is recorded below.

### Final verification

- `swift test --package-path experiments/workflow-model`: **243 Swift Testing + 8 XCTest pass**, final restored production source, zero failures. Includes all previous journeys, surveyed context/expiry/conflicts, original estimate timestamps, registration/preparation, separate public capacity, delayed relay contacts, signature/credential/cache substitution, stop/restart, fake-name exhaustion and expired-conversation isolation.
- `cmake --build /private/tmp/rescue-eligible-cmake` followed by `ctest --test-dir /private/tmp/rescue-eligible-cmake --output-on-failure`: **54/54 pass**, ASan/UBSan configuration with fatal undefined behavior, eligible-flow regression retained.
- `xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -configuration Debug -derivedDataPath /private/tmp/rescue-auto-derived CODE_SIGNING_ALLOWED=YES build`: **BUILD SUCCEEDED** after final source/copy corrections.
- `git diff --check`: passes. `git check-ignore private-data/synthetic-profile.json private-data/survey-map.json`: both ignored. Reviewed changed/new sources for private-key headers and personal-coordinate exposure; none found. Generated profiles/maps/databases/screenshots stay outside publication. Xcode project signing/formatting file excluded.

No new task-observer observations were logged: project-specific protocol, recovery, timing and UI findings are recorded here rather than duplicating existing methodology observations. Existing native-interaction and delegation-boundary observations were applied. Temporary logs are reproducible outputs, not required resume state. Native/physical checks listed above remain explicitly unexercised; this checkpoint completes the finite software build, not those validation gates.

### Native survey import follow-up — October 11

Computer Use exercised the native Files picker on the same iPhone16Pro/iOS18.3 Simulator. Selected an existing synthetic registration-profile JSON as a structurally valid non-survey file: rejected, no map/evidence adopted. That path exposed an unreadable Swift decoder trace, so replaced import/reference failure text with concise actionable messages; validation/state behavior is unchanged. Signed Simulator build passed and the rebuilt app was installed without resetting saved identities/history.

Placed a separate synthetic survey fixture in Simulator Files (Demo Campus / Demo Hall, artificial 02:00:00:00:00:01 AP, level2 coverage; no actual coordinates/AP data). Native picker imported it and displayed one reference. Entered exact campus/building context; floor remained Unknown without a fresh matching observation. Reimported non-survey JSON: readable error, existing map and entered context retained. Clear visibly removed the map and left Unknown. Done returned to the unchanged sample public draft with Unknown reported floor and clear queue. No sensors, permissions, sharing, registration or SOS were activated. File-provider AX omitted picker controls, so screenshot-grounded Computer Use pointer selection was used and the returned app state verified. One transient screenshot capture error recovered by rebinding Simulator.

Checks: final `xcodebuild ... -scheme RescueDemo -sdk iphonesimulator -configuration Debug ... CODE_SIGNING_ALLOWED=YES build` passed; native success/error/retention/clear/draft journey observed; `git diff --check` passed. No engine/protocol behavior changed, so the previously recorded full suite was not unnecessarily repeated. Positive real-sensor estimate, native organizer/public-directory enrollment and combined physical three-endpoint gates remain deferred. Synthetic fixture and raw UI images remain outside Git. No new skill observations: this applies existing native-interaction evidence guidance; the project-specific result is recorded here.
