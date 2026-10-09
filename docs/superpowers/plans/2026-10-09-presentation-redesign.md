# Native interface and explanatory demo redesign

**Goal:** Replace the rejected static two-picture clip with an explanatory animated portfolio demo, an intuitive native public/responder UI, and a visual README.
**Architecture:** Preserve C++/Swift controller, secure identity, stores, manual connection and delivery semantics. SwiftUI presentation changes only. An isolated video-authoring project renders an explanatory motion sequence; simulated diagrams are labeled, app screenshots remain real evidence.
**Tech stack:** Native SwiftUI; Remotion under evaluation against Motion Canvas and Screen Studio; no new production dependencies.
**Authority:** User explicitly requested research, implementation, UI/README improvements, Claude delegation and durable resume checkpoints. Prior publication authorization remains.

## Design and critique

- Public: one primary request action; large state summary; location and conversation; secondary updates accessible.
- Responder: request overview, separate acknowledgment/handling, response actions and chronological history. Preserve all assignment, resolution, reopening and withdrawal journeys.
- Move training/role/route/pair/reset controls into a clearly labeled setup sheet. Keep connection state and pending count visible; no automatic listening/upload or invented delivery.
- Use semantic native type sizes, restrained teal/navy/amber accents, generous spacing, consistent icons and cards. Respect Dynamic Type and Reduce Motion. No safety assurances.
- Video story: outage/context → compose SOS → relay custody is not delivery → endpoint receipt → separate human acknowledgment/reply → durable recovery → measured scope. Animate transitions, packet flow and typography; distinguish conceptual explanation from actual captures.
- README: strong hero/poster, playable demo link, interface images, short workflow, architecture, measured evidence, real setup and honest limits.
- Critique: preserve journeys over cosmetic reduction; do not hide failure states; no UI-only tests that mirror styling; fresh signed build, controller tests and actual rendered phone/tablet review. Verify media decoding and samples across scenes; don't call animations live transfer evidence.

## Research (2026-10-09)

- Remotion: React frame-driven compositions, spring/interpolation and local font loading; chosen for reproducible explanatory scenes and editable source. https://www.remotion.dev/docs/api ; https://www.remotion.dev/docs/fonts-api/ ; https://www.remotion.dev/docs
- Motion Canvas: programmable 2D animation and Vite editor/export; strong diagram alternative, less direct reuse of React UI. https://motioncanvas.io/docs/ ; https://motion-canvas.io/docs/rendering/
- Screen Studio: polished recording/export tool; useful for future live interaction footage, but requires installed app/manual editing and doesn't by itself supply the story. https://screen.studio/guide/exporting-the-video
- Apple hierarchy and button guidance informs native controls. https://developer.apple.com/design/human-interface-guidelines/buttons

## Checkpoints / acceptance

- [x] Record active request, design, alternatives and recovery instructions before implementation.
- [ ] Claude Opus 5.5 medium: native UI changes only; all existing actions retained; no model/crypto/store mutations.
- [ ] Signed native build and controller suite; inspect installed iPhone/iPad UI, empty and saved states as feasible without implicit reset.
- [ ] Reproducible motion source and exported narrated/captioned explanatory video; multiple distinct animated scenes, readable type, correct status semantics.
- [ ] README hero, preview, screenshots, setup and scope; local links/media checked.
- [ ] Review final diff, secret coverage, coherent commit/push and exact CURRENT_STATE handoff.

## Resume immediately if usage ends

Read this file and docs/CURRENT_STATE.md, then git status/log. Parent owns video source, media, README and docs; Claude owns ONLY the three existing iOS Swift view files (plus project-file registration only if necessary). Claude prompt and result are in ignored local-artifacts/presentation-redesign; inspect modelUsage and job log before rerunning. Do not discard partial UI edits or rebuild completed networking. Persist verified source checkpoints before extended rendering. Original clip 901e423 was rejected for not explaining anything; do not present it as the new deliverable.
