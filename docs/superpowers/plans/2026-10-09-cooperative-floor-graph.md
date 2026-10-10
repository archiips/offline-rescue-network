# Cooperative floor graph checkpoint

Goal: implement the first bounded replayable core for the approved UW Wi-Fi + participating-phone localization approach, retaining automatic floor estimation and both rescue audiences.

## Design and constraints

Pure C++ C ABI, Swift adapter, deterministic synthetic replay and native research-only comparison. No new dependencies, Wi-Fi permissions, live peer observation protocol, SOS payload changes, persistence or background work. The existing sensor and encrypted messaging paths remain intact. Bothell is the first campus test site; Seattle is held-out later; Tacoma excluded. Source: UW_LOCALIZATION_ROADMAP.md and PHYSICAL_TEST_PLAN.md.

A graph has at most 32 registered device/reference nodes, 64 timestamped edges, 32 timestamped floor-reference observations. Freshness is a research default of 10 seconds in one replay monotonic clock domain. Contact edges establish reachability only. Explicit relative-level interval constraints must originate from separately validated measurements; this checkpoint only supplies synthetic constraints. They are never inferred from RSSI/contact. References contain origin + observation identity, node, source kind (sensor, surveyed Wi-Fi reference, known reference), integer floor interval and timestamp. Unknown/derived estimates cannot become independent reference observations. Exact original copies deduplicate; conflicting same-origin/ID records fail closed. No probabilistic confidence claims.

Use bounded all-pairs difference constraints with an absolute reference node. Intersect permissible integer levels; disconnected/no-reference => Unknown, non-singleton => Unknown with interval, contradictory constraints => Unknown. Invalid IDs, counts, bounds, timestamps or pointers reject safely; stale/future evidence is skipped. Return contributing distinct origin count as provenance, never confidence. Candidate levels remain -20...200 and unvalidated. Every replay explicitly labels synthetic input and compares sensor-only, Wi-Fi, peer and combined inputs without manufacturing a physical accuracy metric.

Rejected: voting by peer count (circular confidence); same-floor from contact (cross-floor radio); full probabilistic/ML estimator before measured inputs; another transport stack while existing Network adapter already opts into peer-to-peer Wi-Fi. Official Apple API constraints were checked 2026-10-09 in TN3111/TN3151; linked roadmap retains sources.

## Plan and acceptance

- [x] C++ core and adversarial tests: anchored chain, contact-only/no-anchor, adjacent-floor bounds, ambiguous intervals, conflicting anchors/cycles, duplicate and conflicting provenance, source origin counts, stale/future records, input permutation and null/oversized ABI.
- [x] Swift thin adapter and synthetic matched replay fixtures; sensor-only excludes remote references/edges; Wi-Fi-only adds local surveyed Wi-Fi references; peer adds explicit relative constraints and remote non-Wi-Fi references; combined includes all. Assert output and semantic exclusion.
- [x] Native floor-research comparison accessible to both audiences, visibly synthetic and separate from device sensors/manual SOS. No new simulator or history reset.
- [x] Run sanitizer CTest, complete Swift suite, signed Simulator build, native Computer Use check, independent review, documentation/diff checks. Update only completed bounded TODO entry; physical and live-input tasks stay open.

## Critique and revision before build

Correctness: constrain integer intervals rather than majority votes; no geometry or trusted radio ranging claimed. Simplicity: small stateless core; no graph database. Privacy/security: local synthetic replay only, no new network exposure. Maintainability: C++ owns inference, Swift owns presentation. Testing: include semantically valid conflicting originals and permutations, not only malformed records. UX: label all replay references synthetic, show Unknown and provenance, preserve manual/location and baseline screens. Revision: live cross-device timestamps need an independently reviewed age/clock protocol before capture; raw remote uptime is not accepted as a shared clock.

## Execution evidence

Core implementation used verified claude-opus-5-5 with explicit medium effort. Parent observed six C++ scenarios fail against the placeholder and Swift tests fail for missing symbols/then placeholder behavior. Core implementation passed initial tests; parent sanitizer stress reproduced signed overflow on valid full-capacity contradictory inputs, then added the deterministic 2,000-snapshot regression and early negative-cycle rejection. Parent Swift test reproduced negative elapsed/now acceptance, then C++ rejected all negative times. Ruling: nonnegative common replay times and invalid self edges are explicit ABI rules. Existing uncommitted documentation from the preceding authorized discussion is preserved and will be included in this coherent checkpoint.


Final evidence:53/53 sanitizer CTest,119 Swift Testing +6 XCTest,6/6 Release graph checks, signed generic Simulator build. Native Computer Use exercised seven cases and preserved both training histories. Independent review found no Critical/Important findings; parent reproduced/fixed manual known-reference leakage into sensor baseline and added remote Wi-Fi exclusion coverage. Incomplete conflict counters are hidden, domain clipping is explicit, and graph Release tests retain assertions. Detailed commands/limits are in experiments/rescue-demo/COOPERATIVE_FLOOR_GRAPH.md. No live observation adapter or physical accuracy task is marked complete.
