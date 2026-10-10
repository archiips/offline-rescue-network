# Cooperative floor graph research checkpoint

2026-10-09. Implemented foundation for the approved UW Wi-Fi + participating nearby-phone approach, **synthetic replay only**. No live Wi-Fi observations, AP map, phone-observation sharing, ranging, or physical accuracy result exists yet. Both public and responder interfaces retain their workflows.

## Run in the native app

Setup → Automatic floor research → Wi-Fi + nearby-phone graph replay. Seven visibly synthetic scenarios compare sensor-only, baseline + local surveyed Wi-Fi, baseline + participating phones, and combined inputs. The C++ inference runs for each comparison; displayed outcomes are not hard-coded. Inputs list nodes, original observation IDs, source, time and contact/relative edges. Research results never overwrite reported floor, enter SOS payloads, or write history. Entering this separate replay leaves the sensor screen and stops its research as before.

## Core rules

`RescueFloorGraph.h` / `floor_graph.cpp` provide a pure stateless allocation-free C ABI. At most 32 nodes, 64 edges and 32 observation records. All elapsed times are finite/nonnegative and belong to one replay clock domain/building/session. Evidence older than 10 seconds or later than now is excluded. These are research defaults, not calibrated physical thresholds.

Contact edges never imply the same floor. Only explicit relative-level intervals constrain another node; current intervals are synthetic supplied measurements. References are sensor, surveyed Wi-Fi or known-reference intervals. Derived graph estimates are not accepted as a reference source kind. Original origin + observation IDs deduplicate copies; conflicting reuse fails closed even if expired. Origin count describes provenance, not independent confidence, authentication or a probability.

A bounded difference-constraint solver returns a single unvalidated candidate only when the feasible interval is a singleton, otherwise Unknown with its remaining interval. Missing reference paths and contradictions return Unknown. Logical levels -20…200 are hard research-domain constraints and can narrow an interval at the extremes; they are not surveyed building geometry. Contradictions anywhere reject the entire snapshot. The solver stops immediately on a proved negative cycle, avoiding arithmetic amplification on contradictory graphs.

Sensor-only includes local sensor references, not manual known-reference inputs. Wi-Fi mode adds local surveyed Wi-Fi references. Peer mode includes explicit relative paths and non-Wi-Fi references; only combined includes remote surveyed Wi-Fi paths. Rejected snapshots hide incomplete diagnostic counts.

## Fresh verification

- 53/53 fatal-UBSan/ASan CTest scenarios, including six new graph scenarios. The ABI scenario includes 2,000 deterministic full-capacity contradictory snapshots. Parent reproduced a signed overflow with this valid bounded input class before fixing early negative-cycle rejection.
- 119 Swift Testing + 6 XCTest cases pass. New tests cover matched replay, exact-copy dedupe, disconnected references, permutation, expiry, unsafe Swift integers/counts, negative times and semantic input exclusion. Parent reproduced the negative-time and manual-reference baseline gaps before fixing them.
- Six new graph CTest scenarios also pass in Release; this target keeps assertions enabled with `-UNDEBUG` and compiles with warnings as errors.
- Signed generic Simulator app build passes.
- Computer Use on existing Rescue Location Check iPad verified all seven fixture selections: contact-only Unknown; surveyed Wi-Fi Candidate 2 only in relevant modes; peer constraint Candidate 3; contradiction Unknown while baseline stays Candidate 2; duplicate origin stays 1; adjacent levels remain Unknown with 2…3 interval; expired evidence excluded. Native screenshot checked readable layout. Returned to original saved public/responder training conversation, three messages each, reported Floor 4 and clear queue. No resets or new simulators.
- Authorized Claude implementation and independent read-only review both reported canonical `claude-opus-5-5`, launched explicitly with medium effort, no fallback. Review found no Critical/Important findings; minor label/documentation/coverage findings were addressed or explicitly documented. Parent independently ran final checks.

Reproduce from repository root:

```sh
cmake -S experiments/workflow-model -B /private/tmp/rescue-graph-cmake -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON
cmake --build /private/tmp/rescue-graph-cmake
UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir /private/tmp/rescue-graph-cmake --output-on-failure
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-graph-swift
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-graph-derived CODE_SIGNING_ALLOWED=YES build
```

## Next checkpoint and limits

Design the opt-in authenticated peer-observation channel and permitted connected-network adapter, keeping research data separate from private rescue bodies. Original identity and provenance need cryptographic binding. Remote raw uptime must not be compared to local uptime: use a reviewed age/clock protocol and ensure constraints describe a compatible motion snapshot, rather than mixing different floor visits. A hard freshness window alone does not prove simultaneity. No automatic loop of derived estimates is permitted. A manually surveyed Wi-Fi reference is not an automatic SSID-to-floor classifier.

Physical evaluation follows [the protocol](../../docs/PHYSICAL_TEST_PLAN.md): controlled place near home, repeatable Bothell building, separate Seattle building. Ground truth must be independent of supplied references. Seven constructed cases are logic checks, not an accuracy benchmark or evidence that cooperation helps real users. Keep physical, private-data and full LOC-01 gates open.
