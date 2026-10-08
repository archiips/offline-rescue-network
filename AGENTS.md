# Project instructions

## Product brief

One offline rescue communication system with a public iPhone interface and a responder iPad interface. The shared engine is C++; native Apple UI, sensors, transport, and lifecycle adapters are Swift. Preserve both audiences when narrowing the first pilot population.

## Current state and source of truth

Documentation, a linked Figma draft, networking/C++ experiments and a runnable native rescue demo. Training mode retains its two-model simulated link and v1 SQLite store. Local exchange owns one model and role-tagged v2 SQLite outbox per endpoint, uses bounded Network-framework sockets/Bonjour and commits before device receipts. Native Secure exchange adds manually pinned opposite-role identities, CryptoKit signed HPKE envelopes and Keychain-held keys/trust with a separate SQLite file per epoch. Separate Mac processes, secure restart/lost-receipt recovery and signed native simulator-to-Mac workflows are verified. Plain diagnostic remains explicit. Physical radio, agency enrollment, encrypted message storage and independent audit remain unverified. Preset synthetic data only. See experiments/rescue-demo/SECURE_EXCHANGE.md. Portfolio demonstrability is the current priority; commercial readiness is deferred. For any resume/continue request, start with docs/CURRENT_STATE.md, the portfolio section of docs/TODO.md and current Git state; then README.md, docs/PRD.md and docs/DECISIONS.md. Do not restart completed experimental checkpoints or read unchecked full-product tasks as proof that their bounded demo subset is absent. Figma identifiers and evidence are recorded in docs/design/figma-state.json and docs/DESIGN_REVIEW.md. Experiment build/test commands are in experiments/network-probe/README.md, experiments/workflow-model/README.md and experiments/rescue-demo/README.md; use the actual manifests. Production build/lint commands remain unestablished. Do not invent successful checks or operational capabilities.

## Design constraints

- Prove an offline SOS/acknowledgment round trip before adding sensor estimation or AI.
- Treat delivery, human acknowledgment, and request handling as separate facts.
- Preserve reported location separately from estimated location, with observation time and provenance.
- Do not imply that delayed observations are live, or that forwarding guarantees delivery.
- Do not assume iOS background execution or universal device compatibility.
- Keep relays unable to read private request bodies; validate security choices before using real personal data.
- Experimental targets are not safety assurances or product guarantees.
- Never narrow away the public interface to simplify firefighter tracking.

## Work and documentation

Keep initial work scoped to the active milestone. Update the decision register when evidence changes a design choice. Keep source-backed claims linked to docs/RESEARCH.md; distinguish facts, design defaults, and unvalidated hypotheses.

Update only completed entries in docs/TODO.md after their definitions of done and relevant checks pass. Do not mark an engineering task complete because its documentation exists. Preserve user notes and unrelated work.

No application scaffolding, dependencies, Git initialization, commits, publishing, or external outreach are implied by the initial documentation task. Before future commits, verify ignore coverage for any secret-bearing local files.

## Repository publication authorization

The user authorized a public GitHub repository and ongoing commits/pushes at coherent, verified checkpoints on 2026-10-07. Target: `archiips/offline-rescue-network`. This later authorization supersedes the initial documentation-only restriction on Git setup and publication. Keep commits scoped to this project, inspect staged changes and secret exposure before each push, and preserve unrelated work. Do not treat repository publication as authorization for live deployment or external outreach.


## Claude Code preference

When using the authorized Claude Code CLI, the user requested Opus 5.5 with medium reasoning on 2026-10-08. Use `--model claude-opus-5-5 --effort medium` explicitly and do not configure a fallback model. Verify supported settings/model identity; if unavailable, continue locally and report the limitation rather than silently substituting.
