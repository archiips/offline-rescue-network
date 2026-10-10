# Registered inbox implementation plan

> Execute continuously using the existing autonomous authorization. Parent coordinates disjoint file ownership; implementation delegates must read this spec and plan, use red/green behavior checks, and avoid GUI automation outside Computer Use.

**Goal:** One prepared responder handles up to 16 isolated public conversations with automatic foreground exchange and clear readiness.

**Architecture:** One stable responder identity, a Keychain public-card registry and an independent C++ endpoint/store per public card. Internal enrollment context preserves existing proof protocol. Native UI selects explicit conversation IDs.

**Tech stack:** Existing C++20, Swift 6, CryptoKit, Keychain, Network and SwiftUI; no new dependencies.

**Spec:** ../specs/2026-10-10-registered-inbox-design.md

## Global constraints

Public/responder journeys preserved; synthetic-only; iOS 18/macOS 14 floors unchanged; user-local Xcode signing/project changes excluded. New mode uses separate inbox storage; existing single-conversation histories retained. No production enrollment, automatic relay, physical range or floor-accuracy claims.

## Review focus

- Authentic A packet/receipt transplanted into B must fail with no cross-conversation state change.
- C++ first-event commit followed by registry failure must withhold receipt and recover exact history on retry/restart.
- Missing/corrupt registry/history must fail closed and never rotate keys or replace data.
- Abandoned proofs, stale/revoked credentials and full inbox must preserve existing work; unreachable peers must not permanently starve others.
- Selecting another inbox row during an action must not redirect it; renewal preserves identity/history and invalid readiness blocks networking.

## Tasks and ownership

- [x] Core: delegate owns EnrollmentBootstrap.swift, new internal context and RegisteredResponderInbox.swift, and RegisteredInboxTests.swift. Parent does not edit these concurrently. Add behavioral tests, observe failure, then implement. API: inbox initializer `(secure:credential:trust:registryStore:now:)`, `rows` with `id` and `snapshot`, `perform(conversationID:action:value:reference:)`, `receive(_:)`, `start()`, `stop()`, `transport`, `status`. Validate two-peer isolation, failed registry save/retry, restart, capacity, missing history, expiry and actual sockets. Existing SecureEndpointController only receives a conformance extension in the new context file.
- [x] Readiness: parent owns EnrollmentReadiness.swift/Tests and native RescueDemoApp.swift. Add a validated immutable summary `(role, realm, validUntil, issuerFingerprint)` derived from signed profile and credential with effective expiry `min(profile.validUntil, credential.expires)`. Tests cover independent policy/credential cutoff and invalid/revoked identity. Native preparation displays readiness and retains renewal action.
- [x] Native inbox software/build: after core API settles, parent adds responder inbox/list/details and explicit conversation actions. Preserve old single-pair histories via a separate mode. Build signed Simulator app and inspect rendered preparation/inbox where credential-grant policy allows; record unexercised trust interactions.
- [ ] Review/verify/publication: full `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-auto-swift`; signed `xcodebuild` using /private/tmp/rescue-auto-derived; focused adversarial and three-endpoint socket results; Claude `--model claude-opus-5-5 --effort medium` review with model identity verification. Update evidence/current state/TODO/decisions only after checks. `git diff --check`, ignore/staged privacy checks, scoped commit/push excluding project.pbxproj. Then continue remaining finite software milestones through heartbeat.

## Ledger

- 2026-10-10: discovery and independent read-only design/scope review complete. Chosen per-peer C++ stores over broad shared-schema migration; design critiqued for correctness, privacy, crash recovery, maintainability and UX. User explicitly supersedes skill checkpoint-approval pauses. Hourly same-chat continuation created (`continue-rescue-app-development`), preserving physical/partner gates and existing verified publication workflow.
- Ruling: work in the existing checkout with disjoint file ownership rather than a second checkout. No concurrent source ownership overlap; preserve local signing edits needed for build and exclude them from publication. Persistent source/spec/ledger remain in the repository, never only in temporary directories.
- Review finding: a mere filename/existence check accepts an authentic other-peer C++ database because sample IDs are identical. Add an optional bound endpoint SQLite v3 schema carrying immutable full responder/public fingerprint binding; legacy training v1 and endpoint v2 remain unchanged. Bound open rejects existing empty, unbound or differently bound databases; load/save check binding. Admitted inbox history also requires a real request. Delegate owns bridge/session_store, endpoint C API, EndpointController and focused binding tests; core delegate only consumes the optional binding initializer. This preserves file ownership isolation.
- Behavioral discovery: stopped inbox actions initially threw instead of queuing; abandoned provisional contexts initially survived restart. Core delegate reproduced/fixed both. A real socket test exposed public idle reconnect selecting a vanished Bonjour service ahead of a new responder instance; parent removed stale-destination insertion and the same test will be rerun.
- Claude limitation: explicit Opus 5.5/medium CLI attempt returned Not logged in in sandbox; escalation was rejected by automatic approval review because it would send repository source/documents to an external service. No workaround or substitute Claude model used. Continue with independent ChatGPT review and local tests; report this limitation accurately.
- Native preliminary signed Simulator build succeeded; Computer Use inspected Public and Responder unregistered preparation. Complete credential approval/inbox interaction remains unexercised; no synthetic or physical success inferred from screen inspection.

- Final review: fresh ChatGPT reviewer found outbound registry fence missing. Two actual socket tests failed on unwanted send/removed pending after replacement. Parent added registry validation before packet extraction and after await before confirmation. Both green; same reviewer confirmed the scoped fix. Already transmitted packets cannot be recalled; receipt confirmation remains withheld if the registry changed.
- Final verification (2026-10-10): `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-auto-swift` exits0,191 Swift Testing +6 XCTest pass; actual three-endpoint scenario22.088s is scenario time, not radio latency. Logs remain local under /private/tmp/rescue-inbox-final-swift.log. `cmake -S experiments/workflow-model -B /private/tmp/rescue-inbox-sanitize -DCMAKE_BUILD_TYPE=Debug -DRESCUE_SANITIZERS=ON`, build and `UBSAN_OPTIONS=halt_on_error=1 ctest --test-dir /private/tmp/rescue-inbox-sanitize --output-on-failure`:53/53 pass. Final signed `xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-auto-derived CODE_SIGNING_ALLOWED=YES build` succeeds. C++ was unchanged after sanitizer pass.
- Readiness mutation: replacing effective cutoff min with max caused both cutoff assertions to fail; restored implementation and focused2-test run pass. Intact cross-conversation database transplant/zero-file, stopped action, idle reconnect and registry replacement regressions all have observed behavioral red/green evidence.
- Review disposition: all reported important findings corrected; parent independently inspected delegated SQLite binding patch, and fresh reviewer followed up the registry fix. Existing SQLite/private-data/clock/physical limits remain declared.151 local Markdown link targets resolve; diff whitespace and ignored private-data fixture checks pass. No raw logs/account-specific signing file are publication inputs.
- Unexercised checks: complete native credential approval/inbox interactions, actual power-loss/hot-journal recovery, physical no-internet/no-common-AP/range/lifecycle/localization and real issuer/account authority. These require separate evidence/authorization/hardware, not more speculative code.
