# Secure local sample exchange — 2026-10-08

Native **Secure exchange** retains both public and responder workflows and C++ SQLite ownership. Manually checked pairing cards pin one opposite-role endpoint. CryptoKit RFC9180 HPKE encrypts bodies; a separate Ed25519 signature authenticates the pinned sender. Receiver commits precede encrypted receipts, and sender confirmations still commit before removing pending originals. Preset synthetic data only; this is a portfolio prototype, not an independently audited rescue product.

## Run and pair

Open `iOS/RescueDemo.xcodeproj` and Run with the RescueDemo scheme. Simulator-only ad-hoc entitlements are configured on the app target; **do not disable signing** when testing Keychain. Physical signing uses your actual Xcode development team, not the LOCALDEMO simulator identifier. Build:

```sh
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj \
  -scheme RescueDemo -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/rescue-secure-derived CODE_SIGNING_ALLOWED=YES build
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-secure-swift
swift build --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-secure-swift --product rescue-secure-host
swift build --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-secure-swift --show-bin-path
```

Use the returned binary directory. Start separate Mac hosts with roles0/1, different sample roots and free ports, for example `rescue-secure-host 1 /private/tmp/rescue-responder-example 45991`. The optional `--new-session` flag explicitly rotates that role's identity, clears pairing and starts a fresh SQLite session; coordinate both endpoints. It preserves old sample files.

1. Select Secure exchange and Public/Responder roles on different endpoints.
2. Open Pair endpoints. Share **only the public card** directly with the other endpoint. Mac startup/`card` prints CARD and FINGERPRINT; CLI `pair <public-card>` explicitly trusts a checked card.
3. Compare all fingerprint characters on the actual other endpoint. Native formatting groups the full SHA256 into eight groups for readability; no bits are truncated. Paste/import the card, confirm the comparison and choose Trust checked peer on both sides. A different peer requires a new session.
4. Start exchange on both apps. Send the preset SOS and manually choose the paired endpoint in Nearby sample peers. Discovery labels are untrusted; other peers may appear but cannot authenticate.
5. The public view first shows Received by responder device. Explicit responder acknowledgment changes it to Acknowledged by responder. Replies, location corrections, assignment and resolution retain their separate states.
6. Stop/background keeps queues. Restart restores keys, pairing and history **without starting networking**. Start and select the peer to retry. Reset starts a new key epoch and requires both peers to re-pair. Missing keys/history fails visibly; New secure sample session offers explicit recovery with fresh identity, rather than reusing old IDs.

## Reproducible independent-process check

```sh
python3 experiments/workflow-model/tests/secure_host_smoke.py \
  --host /absolute/returned/bin/path/rescue-secure-host
```

The script creates two real Mac processes and real Keychain identities, exchanges SOS/ack/reply, kills and restarts the public process with a queued correction, refuses a connection, duplicates one encrypted correction and drops both encrypted responses, then retries. Both committed stores must have exactly four known originals, four matching receipts and no pending messages. Encrypted receipt bytes differ because each seal uses a fresh HPKE context; their committed C++ receipt is the same. The proxy verifies ORS1 framing and absence of the preset location in the encrypted wire. The script removes only its exact test-owned Keychain entries. It supplies no latency benchmark.

## Verification evidence

- **62/62 Swift tests**, including 29 additions to the original 33: signatures/public RFC8032 vectors, strict cards/limits, wrong roles/senders/destinations, reflected/plain/tampered packets, exact retry, key/storage failures, rotated/stale epochs, real Keychain path/container continuity, missing paired history and explicit recovery, full 4,276-byte socket frames and secure native-controller round trips.
- **30/30 CTest sanitizer checks** retained; unchanged domain/SQLite engine. **14/14 legacy Python harness tests** retained. The separate secure host smoke scenario passed with actual Keychain/process death/duplicated delivery/lost receipt and exact database invariants.
- Xcode 26.4 simulator build succeeded for arm64/x86_64 using native simulator signing. Earlier unsigned UI build exposed `-34018`; scoped signing fixed actual Keychain operations. Mac SwiftPM data-protection Keychain also rejected missing entitlement: the Mac diagnostic explicitly uses its login Keychain, while iOS uses its app-scoped data-protection Keychain. No fallback after a read failure.
- iPhone 17 Pro/iOS 26.4 simulator→Mac responder: checked both fingerprints, SOS→device receipt→human acknowledgment→reply, queued correction while stopped, force-quit/reinstall and Mac restart, then successful correction retry. Pairing/history remained and networking restarted only manually.
- iPad Pro 11-inch (M5)/iOS 26.4 simulator←Mac public: checked both fingerprints, received SOS, native acknowledgment/reply/assignment/resolution and all four encrypted return messages confirmed with queue0. Pairing sheet and both rescue layouts were visually inspected. Training files and plain role files remain separate.
- Claude Code implementation and read-only reviews explicitly used `claude-opus-5-5 --effort medium`, verified in model metadata. Reviews exposed stale cached keys, unstable iOS container naming and surviving-key/missing-history ID reuse. Behavioral regressions were observed failing and corrected; final review status is in the execution ledger. This is code review, not a security audit.

Executed validation commands (all passed; scratch directories are disposable):

```sh
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-secure-integration-build
ctest --test-dir /private/tmp/rescue-secure-cmake --output-on-failure
RESCUE_EXCHANGE_HOST=/private/tmp/rescue-secure-integration-build/arm64-apple-macosx/debug/rescue-exchange-host python3 -m unittest discover -s experiments/workflow-model/tests -p 'test_measure_exchange.py'
python3 experiments/workflow-model/tests/secure_host_smoke.py --host /private/tmp/rescue-secure-integration-build/arm64-apple-macosx/debug/rescue-secure-host
```

The native build used the exact signed Xcode command above. Final reinstall preserved training selection and secure responder pairing/resolved history, with networking stopped.

## Design and limits

[Specification](../../docs/superpowers/specs/2026-10-08-secure-exchange.md), [ledger](../../docs/superpowers/plans/2026-10-08-secure-exchange.md). ORP1 card85bytes; signed ORS1 envelope181..4276; inner ORX1 remains the C++4096-byte bounded format. `_rescue-sec._tcp` is separate from the retained plain `_rescue-demo._tcp` diagnostic. Secure mode never falls back to plain.

On iOS, private records use non-synchronizing WhenUnlockedThisDeviceOnly Keychain storage with a stable app-scoped namespace. Mac unsigned diagnostics use the login/file-based Keychain, which does not enforce that accessibility class; a provisioned Mac app/data-protection Keychain remains future work. No Secure Enclave or lock-state measurement is claimed. Trust is attended sample pairing, not an agency credential or coordinator-signed enrollment. One peer/request per epoch. Keychain updates lack a cross-process compare-and-swap: use one active owner per role/root; stale controllers are detected, not supported as concurrent authorities.

SQLite message bodies remain plaintext and old sample databases are retained on reset. Traffic metadata is visible; long-term recipient-key compromise has no forward-secrecy guarantee. Exact current-epoch original retries are intentionally accepted idempotently; obsolete epoch/foreign/forged packets reject. Physical no-internet/radio range, permissions/lifecycle, battery, older OS compatibility, relay, urgent scheduling and secure timing are unverified. Existing loopback timings describe the **plain baseline only**. SEC-01/ENG-05/NET-01 and private-data gates remain open.
