# Roadmap

Status: evidence-gated roadmap, v0.1 · 2026-10-07

**One project: public SOS + responder interface + shared C++ engine.** Development stages reduce implementation risk without removing either audience. Calendar commitments follow device availability, team capacity, and feasibility evidence; none are invented here.

| Milestone | Deliverable | Unlocking evidence | Main tasks |
|---|---|---|---|
| M0: docs and discovery | Canonical brief, initial specs, source register, task backlog; early workflow/transport findings | Consistent docs; actual supported transport and partner problem identified before dependent work | DOC-01; DISC-01–03; NET-01; SEC-01 |
| M1: direct rescue loop | Both native interfaces, manual location, durable SOS, receipt, human acknowledgment, reply | Physical offline round trip and required M1 failure/UI checks | ENG-01–06; APP-01–03; QA-01 |
| M2: disrupted/relay exchange | Store-forward, retry/recovery, bounded synchronization, priorities | Real isolated relay path and returning acknowledgment; lifecycle limits recorded | NET-02–04; ENG-07; QA-02 |
| M3: indoor-location research | Sensor dataset, baselines, held-out report, optional estimate presentation | Useful measured estimates with explicit failures/uncertainty; no-reference cohort included | LOC-01–05; QA-03 |
| M4: supervised partner pilot | Prepared drill kit, replay/report, partner feedback, adoption decision | Useful workflow, understood states, sustainable deployment effort | PILOT-01–04; BIZ-01–03 |
| Later: selected expansion | Firefighter tracking, additional platforms/transports, integrations, or AI | Each capability's specific gate | FUT-01–05 |

M3 data collection may run alongside M2 after consent and capture design are ready. A partner drill can use manual location before sensor research succeeds. No milestone depends on an LLM.

## First engineering checkpoint

Before scaffolding an app, run NET-01 with the available physical devices and finish the security/protocol decisions needed for private exchange. A successful synthetic transport probe is not itself the product. ENG-01 then establishes build/test commands; M1 creates the first complete user workflow.

## Milestone stop/revise rules

- No usable local link: revise the adapter/device matrix before implementing dependent features.
- No useful relay path: retain direct exchange capability and revise deployment topology; do not claim mesh coverage.
- Sensor estimate is unreliable/unavailable: retain manual location; publish the research result and investigate references/hardware.
- No partner workflow value: revise the business hypothesis before expanding features.
- Operational requirements exceed current equipment/evidence: keep the offering at supervised training/evaluation rather than expanding claims.

## Later capability gates

| Capability | Required evidence before implementation scope expands |
|---|---|
| Continuous firefighter tracking | Partner need, mounting/hardware review, longer-trajectory and movement evaluation |
| Open public onboarding | Verified responder discovery, abuse/capacity model, installation/readiness workflow |
| Multiple command writers | Explicit conflict/ownership rules and disconnected coordination tests |
| On-device translation/summarization | Actual task need; critical-fact preservation, latency/energy evaluation, visible originals |
| Internet / 911 / CAD integration | Named partner, authorized APIs, jurisdictional workflow, security and delivery semantics |
| Android / dedicated radio | Target audience/device evidence and measured protocol interoperability |

## Keeping the roadmap current

Record milestone evidence and limitations in [decisions](DECISIONS.md). Update [tasks](TODO.md) only when their acceptance checks pass. Separate completed documentation from completed engineering. Preserve the public request/reply and responder handling workflows during every architectural change.
