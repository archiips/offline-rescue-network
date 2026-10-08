# Business and adoption

> Current execution status (2026-10-08): see [current state / resume](CURRENT_STATE.md) and [portfolio tasks](TODO.md#current-portfolio-tasks). This document retains its product requirements, proposal or dated evidence; it does not claim that all described capabilities are implemented.

Status: customer-discovery hypotheses, v0.1 · 2026-10-07

**Deferred work:** these business hypotheses support the longer-term vision. The current goal is a working résumé project and demonstrable engineering evidence. Do not start sales, interviews, outreach, pricing or partner pilots merely because they appear here. Resume from [current portfolio tasks](TODO.md#current-portfolio-tasks).

## 1. Proposed offering

One system with a public assistance app and a responder interface, supporting a measured local SOS/reply workflow and later indoor-location research. The first organizational offering would be a supervised training/evaluation package with deployment help and replay evidence.

The public audience remains part of the product. A department or training organization is the initial prospective institutional customer, not necessarily the only eventual payer.

No customer interviews, partner commitments, revenue, pricing validation, market-size estimates, or procurement agreements exist yet. U.S. organizations are a provisional discovery assumption [D-13](DECISIONS.md).

## 2. Buyers, users, and champions

| Role | Candidate | Need to validate |
|---|---|---|
| Public user | Event participant, building occupant, member of a pilot community | Readiness, installation, trusted responder discovery, accessibility |
| Operator | Responder, incident-command aide, exercise coordinator | Request workload, trust, useful location, integration with existing practice |
| Champion | Training officer, innovation lead, community safety coordinator | A concrete exercise where the tool improves outcomes |
| Budget owner | Department/training institution or event/site operator | Funding source, authority, purchase process, recurring support |
| Integration partner | Established public-safety/software/hardware provider | A measurable capability gap and supported interface |

These are hypotheses. Interview the actual operators and budget owners rather than assuming a firefighter who likes the demo can purchase it.

## 3. Competition and alternatives

| Alternative | Sourced existing capability | Question for comparison |
|---|---|---|
| MSA LUNAR [R12](RESEARCH.md#r12) | Ad-hoc teammate search and distance/direction support | Does our civilian request workflow solve an additional need? |
| FLORIAN [R13](RESEARCH.md#r13) | Vendor-described personnel/incident tools | What local exchange, training, and integration behaviors already exist? |
| Ascent [R14](RESEARCH.md#r14) | Wearable responder tracking demonstrated in training | Can we offer a useful capability without duplicating their strengths? |
| Briar/Bitchat/Bridgefy [R07–R09](RESEARCH.md#r07) | Offline communication implementations/SDK | Why isn't an existing messaging workflow sufficient? |
| Current partner procedures | Must be observed/interviewed | What information is actually missing and when? |

Existing competition validates a category, not an unmet gap. Do not assert lower cost, higher accuracy, superior security, or faster rescue without comparable evidence.

## 4. Differentiation hypotheses

| Hypothesis | Evidence needed | Disconfirming result |
|---|---|---|
| Public-to-responder exchange is useful in local drills | Operators use both interfaces to complete an identified task | Their current tools handle it with less effort |
| Honest delivery/freshness improves decisions | Users correctly interpret delayed and uncertain information | Added states confuse users or do not change decisions |
| Local operation addresses a real coverage gap | Partner exercise loses normal connectivity but local exchange is useful | No practical contact path reaches command |
| Indoor vertical estimates add value | Measured errors/availability plus partner task benefit | Wrong/unknown estimates outweigh useful observations |
| Deployable package is simple enough | Observed setup time, equipment handling, training burden | Setup consumes more effort than the benefit warrants |

Interview and test these before choosing a sales pitch. A technically interesting result can remain a research project if the adoption case fails.

## 5. Discovery program

Initial target: 8–12 discovery conversations across responders, training officers/coordinators, and at least 2 budget/integration stakeholders. This is a discovery sample, not a survey estimate. Include organizations that already use competing tools.

Ask about a specific recent exercise or incident:

1. What information was unavailable, to whom, and for how long?
2. How did you locate people and confirm assistance requests?
3. Which tools/procedures worked, and where did they fail?
4. What devices can people realistically carry/use?
5. How would civilians find/install/join the intended system before an outage?
6. Who would acknowledge requests, and what workload would that add?
7. What data, training, integration, and evidence would a supervised trial require?
8. Who owns the budget and decision? What alternative would this replace or complement?

Do not ask only whether they like the idea. Record observed pain, frequency/context, workaround, cost of change, and contradictory evidence. Any outreach must be explicitly authorized separately; no messages are sent by this documentation task.

## 6. Possible business models

| Model | Potential package | Main uncertainty |
|---|---|---|
| Institutional software/support | Responder software, public exercise access, updates, support | Willingness to pay and ongoing useful frequency |
| Exercise rental/evaluation | Prepared devices or relay kit, setup, facilitated drill, report | Logistics, labor, and repeatability |
| Integration/SDK | C++ localization/network engine plus partner support | Clear performance advantage and integration maintenance |
| Sponsored/free public distribution | Institution funds local deployment; public app remains accessible | Readiness/adoption, reachable responders, sustainable support |

An annual license is a commercial option, not an internet requirement: prepared operations should still work offline. Choose pricing only after estimating delivery costs and interviewing buyers. Do not publish invented savings or a speculative total addressable market as fact.

## 7. Cost and unit-economics worksheet

For each pilot/package record: supported device count, device/relay purchase or rental cost, shipping, replacement rate, setup hours, training hours, support hours, software maintenance, security review, test/validation costs, insurance/legal/partner review where applicable, and integration labor.

Estimate contribution per engagement as collected revenue minus directly attributable delivery costs. Record engineering/validation investment separately; donated pilots still have real labor and equipment costs. Use low/base/high scenarios with source dates and assumptions. Populate amounts only after quotes, actual time logs, or buyer evidence.

## 8. Partner and procurement path

1. Identify an exercise partner and an operator-owned problem.
2. Demonstrate the synthetic-data two-interface round trip.
3. Agree on a supervised exercise, supported equipment, data handling, and stop conditions.
4. Provide a results report including failures and comparisons to the existing workflow.
5. Ask the budget owner whether a supported repeat engagement is justified and what purchasing path applies.
6. Resolve intended-use and integration requirements before proposing operational deployment.

A donated evaluation is one route; a paid bounded pilot is another. Neither implies the product is approved for live incidents. Determine procurement, security, accessibility, and equipment obligations with the actual jurisdiction/partner rather than asserting a universal certification list.

## 9. Adoption risks

The public app must be installed/ready and a responder path must exist. An empty network has little value. Additional interfaces can increase responder workload. Partner hardware may favor other platforms. Training products face existing competitors. Long support and integration efforts can overwhelm a small team.

Mitigate through prepared bounded deployments, simple workflows, measured interoperability, customer interviews, and scoped support commitments. If public readiness is impractical, investigate event/site-sponsored preparation or integration with an existing app; do not silently turn the product into responder-only tracking.

## 10. Business gates

Proceed to M4 only with a named partner and agreed evaluation scenario. Pursue a commercial package when a budget owner identifies a repeat need and delivery costs can be estimated. Pursue an SDK route when an existing vendor identifies an integration gap and accepts a measurable benchmark. Pursue live-incident capability only after its separate intended-use evidence gate.

No source in [research](RESEARCH.md) establishes our willingness-to-pay, price, market size, or proprietary advantage.
