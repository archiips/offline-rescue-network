# Project instructions

## Product brief

One offline rescue communication system with a public iPhone interface and a responder iPad interface. The shared engine is C++; native Apple UI, sensors, transport, and lifecycle adapters are Swift. Preserve both audiences when narrowing the first pilot population.

## Current state and source of truth

Documentation only. Start with README.md, docs/PRD.md, docs/DECISIONS.md, and docs/TODO.md. No build/test/lint commands exist; read future project manifests and record actual commands when implementation begins. Do not invent successful checks or operational capabilities.

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
