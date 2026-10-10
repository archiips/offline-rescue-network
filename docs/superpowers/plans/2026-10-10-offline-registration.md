# Offline registration implementation

Execute inline under the user's explicit continue-building authorization. Preserve unrelated local signing settings.

1. Credential foundation: `swift/Enrollment.swift`, tests `SwiftTests/EnrollmentTests.swift`. Canonical sorted JSON, signature domains, strict size/shape validation, role/card binding, realm, issuer, validity and trusted local revocation/expiry policy. Test semantic equal-shape substitutions, exact boundaries and malformed/canonical input. No issuer secret persistence or logging.
2. Challenge bootstrap: `swift/EnrollmentBootstrap.swift`, tests. Four-frame possession/transcript proof, bounded expiring pending state, exact retry recovery, no automatic existing-pin replacement, stop fencing. Preserve existing key records and C++ stores.
3. Real socket end-to-end: distinct registration transport configuration; provision both endpoint credentials using a synthetic in-memory issuer in tests. Bootstrap then normal secure SOS/device receipt/ack/reply without `pair` calls by the user. Full Swift test suite, native signed build and final diff/security review. Record completed foundation separately from pending native onboarding and physical proof.
4. Native preparation and registered-mode integration follows the verified foundation with its own UI acceptance checks; do not claim it exists from library tests. Continue without requiring iPad availability. Real account/issuer operations remain deferred pending deployment trust authority.

Review focus: expiry at exact boundary; equal-length wrong realm/card/signature; replayed Finish and exact lost-Ready retry; expired outstanding challenge; failed/stale record pin mutation; current manual/relay compatibility. Commands: `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-enrollment-swift`; signed `xcodebuild` using RescueDemo scheme and Simulator destination. No physical/offline range claim from Mac tests.

## Execution and verified checkpoint — 2026-10-10

Milestones 1–4 implemented within the synthetic drill boundary. Added signed credential/trust/profile adapters, challenge bootstrap, registered controller, Keychain-backed Mac registrar, native public-request export/profile import, registered conversation workspace and next-launch preference. Real account service/organization authority and multi-request engine migration remain future work, not implemented login.

Review-led deviations:

- Opus 5.5/medium review and two follow-ups (actual CLI model metadata `claude-opus-5-5`, no fallback) found asymmetric trust persistence, repeated-Hello slot exhaustion and responder restart reauthorization. Revised both sides to provisional handshake trust, pinning only on authenticated encrypted request/receipt. Bound/dedupe pending entries, preserve completed replayed leases, resolve simultaneous Finishes by authenticated sender and restore a matching saved peer credential after a fresh Finish.
- Reproduced responder restart failure before its fix: public follow-up and responder reply remained queued; added the actual socket regression, then passed it after correction. Idle-expiry/rebootstrap, concurrent Finishes and mid-session credential expiry are also covered.
- Action rejection originally returned without throwing; a new test failed before the wrapper was corrected. Invalid actions now report that they were not saved.
- Full parallel suite exposed unrelated advertisements crowding the existing manually pinned direct peer. Add an untrusted fingerprint routing hint and filter before the bounded peer cap, retaining signature/recipient checks. A regression includes forty unrelated advertisements preceding the intended peer. This is the only change to the prior manual Secure behavior; plain/relay/research remain unchanged.
- Fully sign prepared profile policy, including cutoff/revocation snapshot; add registrar `revoke SERIAL_UUID`, explicit UI issuer approval parameter and Update registration. Backdate credential start five minutes for small setup skew. Prepared policy still requires a trusted organizer fingerprint and cannot learn new revocations offline.

Final checks:

- `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-auto-swift`: **172 Swift Testing + 6 XCTest passed**. Uses real Bonjour/socket round trips from unpaired enrolled endpoints; SOS/device receipt/human acknowledgment/reply and both public/responder stop/restart recovery pass. Earlier test additions initially failed to compile until their new APIs existed; separate behavioral failures/mutations above establish the relevant negative controls.
- Controlled removal of issuer-signature checking and transcript binding caused expected semantic test failures; restored before final suite/build. Equal-shape validly signed transcript substitution and credential-field substitution are retained as regressions.
- `xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-auto-derived CODE_SIGNING_ALLOWED=YES build`: **BUILD SUCCEEDED** after final code changes.
- Computer Use inspected rendered native Public and Responder preparation screens on running iPhone 16 Pro/iOS 18.3 Simulator. Complete native organizer-import/trust/send UI walkthrough remains unverified; controller/socket end-to-end evidence is separate. No physical retest while iPad unavailable.
- Registrar initial public-only issuance smoke succeeded with its private issuer key in Mac Keychain. The rebuilt CLI signed-policy/revocation smoke encountered macOS Keychain authorization and was stopped without changing access controls; do not report that optional smoke as passing. Profile policy/revocation behavior passes unit tests.
- `git diff --check` passed; `git check-ignore private-data/example-profile.json` confirms private capture coverage. Exclude the user's existing development-team/project-format changes from publication. No private keys, account/device identifiers or actual location captures belong in this checkpoint.

Acceptance boundary: locally verified synthetic registration and automatic trusted exchange, not production campus registration, arbitrary mesh, encrypted SQLite, independent audit, dependable clock, unrestricted responder capacity or physical no-internet/radio range. No hardware purchase, new dependency or external deployment was needed.
