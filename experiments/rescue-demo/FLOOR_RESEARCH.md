# Automatic floor feasibility — 2026-10-09

Setup → Automatic floor research opens a separate optional foreground workspace from either public or responder interface. Device sensors can show a fresh Apple-provided logical level when available. The separate relative-altitude path estimates changes from an explicitly known starting logical level and measured uniform spacing. Neither result replaces the reported floor or enters rescue messages/history. Nothing in this research workspace is persisted, transmitted, or broadcast.

Logical level 0 means ground, not a building's sign numbering. Apple coverage at UW is unknown. Core Motion altitude needs supported hardware and permission; Simulator has no altimeter. No campus Wi-Fi map/classifier, Bluetooth beacons, UWB, phone graph, automatic building identification or claimed accuracy is included. [UW roadmap](../../docs/UW_LOCALIZATION_ROADMAP.md) preserves those later experiments.

## Research behavior

Start foreground sensors explicitly. Location and motion availability are separate. Denied, unsupported, missing, stale or inconsistent observations yield Unknown; manual rescue operation stays available. Apple floor only uses the newest fresh location fix and is never silently fused with the relative candidate.

For relative altitude, enter a known logical level and measured 2–8 m uniform floor spacing. Set starting reference here becomes available only after at least three stable fresh readings across two seconds. Calibration passes the same C++ guards, uses median altitude and begins at the latest sample time. Rejected input retains any existing reference and gives explicit feedback. New estimates need a subsequent stable window. A reference is specific to this sensor session/building; clear/recalibrate after changing building or floor-spacing assumptions.

The pure bounded C++ engine accepts 3…64 strictly ordered samples no older than 10 seconds, with ≥2-second span and ≤0.35 m altitude spread. Reference lifetime is at most 600 seconds. Latest displacement from the reference must be within 0.2 levels of an integer; candidates are bounded to logical levels −20…200. Nonfinite/huge/future/invalid samples, absent reference, transitions, noise and expired data return Unknown with a cause. These thresholds are unvalidated engineering defaults, not confidence probabilities or sensor guarantees.

Stop, leaving the screen, switching input source, or backgrounding clears observations and reference. Returning never auto-starts. Generation/manager checks fence late callbacks. Foreground permission prompts may temporarily make the app inactive without stopping; background does stop. The monotonic timing use has a bundled required-reason declaration (35F9.1); this is not a complete production distribution/privacy audit.

Synthetic fixtures are explicitly labelled and isolated from sensors: no anchor, stable one level up, between levels, noisy and stale readings. They call the same C++ engine. Source switching clears fixture candidates and references before device use. Fixtures prove logic, not physical altitude/floor performance.

## Verification

- Full Swift suite:111 Swift Testing +6 XCTest passed, including five floor-engine corpus tests and two stable-calibration tests. The existing rescue, crypto, sockets, relay, persistence and location cases remain passing.
- C++:47/47 CTest passed under AddressSanitizer/UndefinedBehaviorSanitizer with fatal UBSan checks; four new scenarios cover candidates, exact boundaries, refusal classes and C ABI/null/oversized counts. Engine placeholder produced failing tests before implementation. Calibration tests first failed for missing stable-calibration API, then passed.
- Signed generic Simulator build passed (arm64/x86_64); bundled PrivacyInfo.xcprivacy validated with plutil. No dependency or protocol migration.
- Claude Code core implementation and independent native/final reviews used canonical claude-opus-5-5, explicitly invoked --effort medium with no fallback. Review fixes: stable median calibration, explicit blank starting level, locale-aware spacing, recomputed status plus action feedback, correct permission description and ordered main-actor callbacks. Final review found no Critical/Important defects.

## Attended native checks

Computer Use reused Rescue Location Check (467E1A4B-58D1-48EA-BE2A-CD727CCD81E9), iPad Pro 11-inch M5 / iOS26.4. No new simulator was created. Window inventory also showed the paired responder iPad, Rescue Live Training and the paired iPhone; none was reset, installed over or otherwise changed.

| Action | Visible result |
| --- | --- |
| Open research | Device source, stopped, Apple floor Unknown. |
| Start sensors | Existing denied location permission and unsupported relative altitude each shown truthfully; no invented level. |
| No-anchor fixture | Unknown: no anchor set. |
| Stable-up fixture | Candidate logical level1, unvalidated, synthetic reference ground/3.4 m. |
| Between-level fixture | Unknown: between floors. |
| Noisy fixture | Unknown: altitude unstable. |
| Stale fixture | Unknown: samples older than10 seconds. |
| Stable fixture → device source | Candidate/reference cleared; stopped, empty starting-level/height inputs; Set reference disabled without stable readings. |
| Start → Home → reopen | Same process returned stopped/Unknown, no automatic restart. |
| Start → leave → return | Fresh research workspace stopped/Unknown. |
| Reinstall/restart | Earlier training conversation still three messages on both audiences, reported sample floor4 and queue clear; stored coordinate provenance unchanged. |

The source picker was changed to a native menu so each input source is individually accessible. The form's real rendered stopped/Unknown state was inspected. Final app is left in stopped device research; relay remains stopped and its configuration/history files are preserved.

Real Core Motion callbacks, supported-device permission allow/deny, Apple venue-floor coverage, clock-reference compatibility, pressure drift/HVAC, stairs/elevators/mezzanines/nonuniform spacing, battery and actual floor accuracy remain untested. There are no native unit tests for the sensor adapter; simulator lifecycle/source checks and portable engine/calibration tests do not replace those physical cases. No full LOC-01 or physical gate is closed.

## Commands run

```sh
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-floor-swift
cmake -S experiments/workflow-model -B /private/tmp/rescue-floor-cmake -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON
cmake --build /private/tmp/rescue-floor-cmake
UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir /private/tmp/rescue-floor-cmake --output-on-failure
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-floor-derived CODE_SIGNING_ALLOWED=YES build
plutil -lint /private/tmp/rescue-floor-derived/Build/Products/Debug-iphonesimulator/RescueDemo.app/PrivacyInfo.xcprivacy
```

Next: a consented physical one-building validation following the UW roadmap, with independently recorded logical floors and measured spacing. Record incorrect candidates as well as Unknowns, transition latency, source availability and exact device/OS/permission conditions. Physical hardware/building access remain unavailable; do not invent results or add an untrained Wi-Fi classifier to fill that gap.
