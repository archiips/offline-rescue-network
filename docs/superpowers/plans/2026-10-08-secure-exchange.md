# Secure exchange execution ledger

Authorized continuation; inline execution with actual Claude Code assistance using Opus 5.5/medium. Design: ../specs/2026-10-08-secure-exchange.md.

1. Foundation: SecureEnvelope.swift, SecureEndpointController.swift, SwiftTests/SecurityTests.swift. Test-first runtime-generated keys, strict cards, HPKE/signatures, trusted peer and fresh epoch, persistent injected record storage plus production Keychain. No new production dependency.
2. Transport: configurable bound/service keeping default4096 and legacy tests; secure4276 and separate Bonjour service. Test strict configured capacity and sockets.
3. Integration: DemoController secure role, pairing/error/reset APIs and one selected endpoint; native pairing sheet and secure default local mode. Preserve original sample workflows/fixtures/training. Add secure CLI target for independent endpoints and public-card exchange.
4. Verify: full Swift test, sanitizer CTest, Python measurement harness tests with legacy host, native simulator build, real secure Mac/socket restart and rendered native simulator-to-Mac SOS/ack/reply. Read-only Claude review, reproduce/fix findings. Update current state/TODO evidence/decisions/security draft. Inspect diff, ignore/secret coverage, scoped commit and authorized push.

Baseline main9fdfa67, isolated /private/tmp/rescue-secure. Work not complete until evidence below. Full product gates remain open.

## Evidence

Completed foundation/transport/native integration and independent secure CLI. RED/GREEN observed for frame4276 bound, foundation stubs, stale cached packet mutation, unstable Mac namespace after mkdir, surviving paired keys with missing history and explicit recovery.

Ruling: CryptoKit remains Swift Apple platform adapter; C++ business/state/storage stays unchanged. No production package added. Mac unsigned CLI uses login Keychain explicitly after DP-34018 failure; does not promise iOS accessibility. iOS uses stable app-scoped namespace. Simulator Keychain requires app-target-only signing entitlements; CODE_SIGNING_ALLOWED=YES, physical team unaffected.

Ruling: allow exact authenticated current-epoch retries; reject foreign/stale/reflected/tampered/plain input. Ciphertext receipts use fresh HPKE contexts while committed domain receipt remains identical. Lost history with paired keys fails; explicit recovery rotates keys/epoch and retains earlier sample files. One active role/root owner; no Keychain cross-process CAS claimed.

Verification:62/62 Swift tests, 30/30 sanitizer CTest, 14/14 legacy Python tests, secure independent-Mac-process Keychain/death/refusal/duplicate/lost-receipt smoke PASS, native simulator arm64/x86_64 build PASS with signing. iPhone secure pairing/SOS/device receipt/human ack/reply/stopped correction/force-quit-reinstall/Mac restart/retry passed; iPad secure incoming SOS/ack/reply/assignment/resolution/all return receipts passed. Pairing and both rendered layouts inspected. Plain timing results unchanged and explicitly not secure benchmarks.

Review: actual Claude Code foundation/whole-branch/follow-ups used verified claude-opus-5-5 with medium effort. Initial reviews identified stale packet keys, container/path instability and surviving-key/missing-history ID reuse; reproduced and fixed with behavior tests. Final review result recorded below before publication.

Documentation/current state/TODO/security sources aligned; original NET-01/SEC-01/ENG-05/product tasks remain open. Physical and encrypted-storage/agency enrollment/audit limits retained. Next: separately research/design bounded relay and urgent scheduling.
Final review: no Critical/product blockers; Important smoke cleanup path mismatch fixed with /tmp logical spelling and required status0. Fresh full smoke PASS verifies exact cleanup. Attributes-only dry run identified seven earlier scratch records and preserved two active Mac fixture identities. The first cleanup API attempt returned InvalidOwnerEdit; no removal was assumed. Exact CLI cleanup outcome recorded separately. Minor single-owner/missing-key/private-storage limitations are documented.

Exact CLI cleanup subsequently removed all seven identified scratch records successfully while preserving two active fixtures; fresh smoke requires cleanup exit0. The reviewer's local-save minor issue was also reproduced/fixed: secure native/CLI actions now check current keys and paired history before C++ submission. A 62nd Swift regression covers no queue mutation after loss/rotation. Other minor limitations are documented, including single-owner/stale reload and simulator-only signing evidence.
