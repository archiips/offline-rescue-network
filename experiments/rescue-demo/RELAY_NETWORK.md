# Signed relay network — bounded portfolio evidence

Verified 2026-10-08 on one Apple Silicon Mac. This extends the [custody foundation](RELAY_QUEUE.md), retaining [direct Secure exchange](SECURE_EXCHANGE.md) and both native interfaces. Native relay controls are the next milestone.

## What happens

A public endpoint uploads an encrypted SOS to a separate relay process and stops. The relay saves ciphertext, then delivers it when a responder process starts. The responder commits its request before returning a signed acceptance containing an encrypted reverse device receipt. The relay saves that receipt before removing the SOS. When the public endpoint returns, the receipt clears its outbox and changes delivery to deviceReceived. A human acknowledgment and reply follow as separate events with their own receipts.

All three processes use real Network-framework sockets and C++ SQLite stores. Endpoints hold manually paired identities in the Mac login Keychain; the relay receives only their public cards. Contacts are sequential: the harness checks owned endpoint PIDs are dead and their ports refuse connections. No direct-send command or automatic forwarding exists. This demonstrates nonoverlapping contacts on one Mac; it does not establish physical radio range, firewall isolation, separate machines, background delivery or operational readiness.

## Bounds and ownership

- C++ custody:64 items,181...4276 payload bytes,273664 payload bytes total, no eviction, eight attempts, per-flow FIFO and persisted three-urgent/one-ordinary scheduling when eligible. Attempts commit before sending. Capacity/exhausted heads can block progress.
- Swift ORL1: signed kind, priority, positive expiry, two-hop budget, sender/recipient digests and reverse-receipt correlation;358...4096 bytes including signed/encrypted ORS1. Incoming expiry must be after now and at most48 hours away; created messages default to24 hours. Accurate clocks are assumed, not proved.
- ORA1 destination-signed acceptance:134...4230 bytes. An event requires exactly its correlated reverse receipt; a receipt requires none. ORC1 upload response is36 bytes and untrusted: custody never proves endpoint delivery.
- ORF1 endpoint cache: own signature binds the mapping ID and exact packet. Cache admission does not prune or renew expired entries. Public ORG1 epoch/peer guard is68 bytes and read with a fixed bound. Missing, mismatched or corrupt files fail closed; deleting both files maliciously is outside the sample guarantee.
- One active owner per root/role; one relay flush at a time. After awaiting a response, custody is revalidated before mutation. Reverse receipt admission precedes original removal; this ordered pair is idempotent but is not one SQLite transaction.

Endpoint bodies remain unencrypted in SQLite. Relay metadata reveals identities, priority, expiry and traffic shape. Same-user Mac processes are not an OS confidentiality boundary. Custom protocol, manual pinning and source review do not establish agency enrollment, audit, forward secrecy or a portable C++ crypto implementation. Preset synthetic data only.

## Reproduce

Run from repository root; use fresh scratch directories. Swift/macOS tests require local sockets and test-owned login-Keychain access.

```sh
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-net-swift
RESCUE_RELAY_HOST=/private/tmp/rescue-net-swift/arm64-apple-macosx/debug/rescue-relay-host \
  python3 -m unittest discover -s experiments/workflow-model/tests -p test_relay_network_smoke.py
python3 experiments/workflow-model/tests/relay_network_smoke.py \
  --host /private/tmp/rescue-net-swift/arm64-apple-macosx/debug/rescue-relay-host
```

CLI forms:

```text
rescue-relay-host endpoint [--new-session] <0 public | 1 responder> <absolute-root> <listen-port> <relay-port>
rescue-relay-host relay <absolute-store-file> <listen-port> <public-card> <public-port> <responder-card> <responder-port>
```

Endpoint commands:card, pair <card>, sos, ack, reply, correction, upload, state, quit. Relay commands:state, flush, flush-drop, quit. Pair both endpoints manually before uploads. Relay configuration uses their exact cards. Outgoing sockets use explicit loopback ports; listeners do not provide an OS firewall boundary. Bonjour is disabled for this harness.

Expired/full/lost cache recovery is explicit `endpoint --new-session`: rotate identity, preserve old epoch stores and re-pair both endpoints and relay. This resets the exercise; it does not migrate a pending SOS. No automatic resealing or plaintext fallback.

## Fresh verification

43/43 CTest with sanitizers and fatal UBSan;89/89 Swift tests;13/13 relay Python checks with real-host configuration (no skipped host checks);14/14 existing measurement-harness checks; signed native simulator build. Updated iPad responder app was inspected with prior history retained and networking stopped. No native relay UI claim or new latency benchmark.

The actual-process harness verifies11 named facts:

1. cards-paired-before-contacts
2. relay-startup-failure-bounded
3. upload-refused-while-relay-absent
4. custody-id-stable-across-restarts
5. responder-absent-flush-retained
6. lost-response-exact-retry-one-sos
7. receipt-held-origin-pending
8. delayed-receipt-device-received
9. acknowledgment-separate-and-reply-delivered
10. stores-empty-no-direct-path
11. relay-holds-no-keys-or-plaintext

Process checks include killed relay/public restart, restarted responder after deliberately dropped acceptance, identical cached packet retry, one SOS, delayed reverse receipt and6 history entries per endpoint (SOS/ack/reply plus receipts). The relay folder holds only its custody database and not the preset location bytes. These observations support the implemented encrypted path; absence of one byte string alone is not an independent cryptographic proof.

Harness cleanup targets only owned PIDs, fresh roots and exact test-Keychain account hashes. Every account is attempted; scratch removal runs even after failures, cleanup errors remain visible alongside the original exception. No private Keychain values are read or printed.

Independent review reproduced and fixed equal-size cache substitution and missing-cache resealing. Signed mapping records, cache guards, unsigned custody metadata checks and post-await checks now have regression tests. Final read-only review found no remaining findings; see [execution ledger](../../docs/superpowers/plans/2026-10-08-relay-network.md). Claude used verified Opus5.5/medium, reached session quota after core fixes and was not silently replaced; parent completed host/harness locally.
