# Indoor localization research

Status: experiment design, v0.1 · 2026-10-07

## 1. Research question

Can available phone sensors supplement a person's reported indoor location with useful vertical information, while exposing when the estimate is unavailable, stale, or wrong?

The first product milestone works with manually reported floors. This research is M3, not a dependency for the first SOS/acknowledgment drill. See [PRD](PRD.md) and [roadmap](ROADMAP.md).

## 2. What we are estimating

| Quantity | Initial capability |
|---|---|
| Reported building/floor/room | User enters it; preserve provenance |
| Relative vertical displacement | Measure/evaluate from a known sensor reference |
| Physical floor transition | Research pressure plus movement evidence |
| Labeled building floor | Requires a valid entry/reference and floor mapping |
| Horizontal room/precise rescue location | Not produced by the initial sensor model |

The original paper motivates the experiment but does not validate it for unfamiliar devices, unprepared callers, or firefighting conditions [R01](RESEARCH.md#r01). Apple exposes relative altitude, not a floor label [R06](RESEARCH.md#r06).

## 3. Important public-user constraint

A person may open the app only after entering a building or becoming stuck. We cannot assume the phone recorded the entrance pressure or knows the entrance floor. Without a usable reference, show manual location plus available geographic information and **floor estimate unavailable**.

Study this no-reference case explicitly. Do not solve it by silently requiring always-on tracking. The firefighter-tracking extension can use a deliberate entry checkpoint; that does not establish the same capability for an arbitrary civilian.

## 4. Inputs and collection

Initial inputs are timestamped OS location/accuracy, pressure and relative altitude, accelerometer, gyroscope, optional magnetometer, known reference events, and manually labeled ground truth. Capability checks and permission denial are recorded as data, not filtered out of evaluation.

| Metadata | Why it matters |
|---|---|
| Device/OS and sensor availability | Detect unsupported devices and cross-device behavior |
| Sensor units and actual sample intervals | Avoid conversion and sampling assumptions |
| Placement: hand, pocket, bag | Sensor behavior depends on how the phone is carried |
| Movement: stationary, stairs, elevator, later crawling | Walking-only evidence does not support firefighter claims |
| Building, entry floor, labeled floors, known heights if available | Separate relative motion from floor numbering |
| Reference age and restart/lifecycle events | Detect missing baselines and stale observations |
| Day/session and environmental observations | Support held-out evaluation and pressure-disturbance analysis |

Initial sampling request for the controlled experiment: motion at 20 Hz, location at available OS cadence, and pressure/relative altitude at available native cadence. Record actual rates and gaps. These are experiment defaults, not production battery settings or guarantees that the OS delivers them.

Collect only in authorized, non-hazardous spaces. No independent live-fire or hazardous-pressure experiments are part of this research plan.

## 5. Baselines before models

1. **Manual-only:** what participants report, including incorrect and unknown reports. This is the user-workflow baseline, not independent sensor truth.
2. **Relative-altitude baseline:** evaluate OS altitude change against measured transitions.
3. **Pressure/reference baseline:** convert pressure changes to relative height using a documented physical model and stable reference; state its assumptions.
4. **Building-aware baseline:** add known floor mapping and reference checkpoints; evaluate separately from unknown-building conditions.
5. **Sensor fusion candidate:** combine motion evidence and pressure with an explicit state estimator or transition classifier. Start simple; only add a learned model if a held-out comparison justifies it.

Normalize and replay observations through the C++ localization boundary. Python may be used as a research/training tool; deployable inference and authoritative system behavior remain in the C++/native client architecture.

Do not reproduce unavailable/private APIs from the historical paper. Use current supported APIs; missing signals require a revised experiment rather than undocumented access.

## 6. Dataset design

Proposed initial collection target: at least 3 non-hazardous multistory buildings, 3 eligible device models, 2 separate days, and 120 labeled transitions with stationary segments. Include stairs, elevators, mixed-height floors where accessible, and no-reference sessions. This is a feasibility dataset, not operational validation.

Record ground truth through supervised route labels and known physical reference points. Ground truth and user-entered floor must be separate fields. Synchronize annotation time and document label uncertainty. Do not report quantitative height error without measured height ground truth.

Split by building and session, with an explicit held-out device evaluation. Keep overlapping windows from a single route in the same split. Freeze a final test set before tuning. If dataset coverage is insufficient for a stratum, report it as unsupported instead of averaging it away.

## 7. Evaluation

| Metric | Required interpretation |
|---|---|
| Exact-floor accuracy | Include the population and mapping assumptions |
| Within-one-floor rate | Report alongside exact-floor and larger errors |
| Vertical error distribution | Median, 95th percentile, and observed worst case where height truth exists |
| Transition detection delay | Include missed transitions |
| Estimate availability | Count abstentions and unavailable devices/sessions |
| Confidently wrong estimates | Require empirical confidence calibration before using this term numerically |
| Age at responder display | Measure complete collection-to-display behavior |
| CPU, memory, battery change | Compare equivalent collection sessions, not idle-device claims |

Always report results by building, device, placement, movement, reference availability, and reference age. Report available-only performance together with total-cohort coverage. A model that avoids difficult cases can appear accurate while failing to assist most users.

## 8. Promotion gate

LOC-04 produces a signed-off research report with data provenance, split definitions, baselines, failure cases, confidence/abstention analysis, reproducible configuration, and known unsupported conditions. A fusion model is promoted only if it improves the agreed task over the simpler baseline on held-out conditions without concealing worse error behavior.

There is no preselected percentage that certifies rescue safety. Decide acceptable pilot usefulness with the partner after observing error distributions. Until then, estimates remain experimental and reported locations remain independently visible.

## 9. Later firefighter extension

Investigate consistent mounting, entry checkpoints, crawling/climbing, equipment interactions, long trajectories, and independent ranging/reference measurements. Choose suitable hardware through the partner intended-use review; an ordinary phone is not assumed fire-resistant [R16](RESEARCH.md#r16).

NIST's evaluation guidance and vertical test facility are possible references/collaboration resources [R15](RESEARCH.md#r15), not assured access or a certification path already secured.
