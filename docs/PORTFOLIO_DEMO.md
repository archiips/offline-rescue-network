# Three-minute portfolio demo

One public iPhone interface sends a synthetic SOS; a responder iPad interface receives, acknowledges and replies through a Mac relay. C++20 owns workflow rules, SQLite outboxes and opaque relay custody. SwiftUI, Network framework, CryptoKit and Keychain provide the Apple interfaces and adapters.

This is a presentation script for the [verified native walkthrough](../experiments/rescue-demo/NATIVE_RELAY.md), not a new recording or measurement. Allow setup time before the three-minute presentation. Use preset synthetic data only.

## Prepare before presenting

Use one Mac with Xcode and two iOS simulators. The recorded exercise used iPhone 17 Pro and iPad Pro 11-inch (M5), both iOS 26.4. Simulator loopback is the demonstrated topology; physical offline radio remains unverified.

1. Follow [native build instructions](../experiments/rescue-demo/README.md#run-in-xcode) to run the signed app on both simulators. Keep signing enabled for Keychain. Build the Mac relay executable from the repository root:

   ```sh
   swift build --package-path experiments/workflow-model \
     --scratch-path /private/tmp/rescue-portfolio-swift --product rescue-relay-host
   swift build --package-path experiments/workflow-model \
     --scratch-path /private/tmp/rescue-portfolio-swift --show-bin-path
   ```

   Use `rescue-relay-host` inside the printed directory; do not assume an architecture-specific path.
2. Choose Secure exchange, Public on the phone and Responder on the tablet, then Via relay. Existing paired peers need no new trust approval. For fresh peers, exchange public cards through Pair endpoints and compare complete fingerprints before trusting the opposite role. Never give the relay private keys.
3. Use an empty coordinated exercise for a fresh SOS. The sample supports one request per key epoch. Existing completed history is suitable for a narrated review. Starting a new exercise requires the app's explicit reset confirmation on both sides, new pairing and updated relay cards; reset retains old files and does not migrate pending messages.
4. Start relay exchange on both foreground apps. Record their current listener ports. Set relay host `127.0.0.1` and an available relay port, for example `55400`, in each Relay connection sheet. This host applies to simulators on this Mac only.
5. In a Mac terminal, run the following form, replacing every uppercase placeholder with the current value. Use a fresh absolute SQLite path for a fresh exercise, in an existing writable directory. Quote each complete public card as one argument:

   ```text
   /PATH/TO/rescue-relay-host relay /ABSOLUTE/PATH/demo.sqlite 55400 'PUBLIC_CARD' PUBLIC_LISTENER_PORT 'RESPONDER_CARD' RESPONDER_LISTENER_PORT
   ```

   Relay commands are `state`, `flush` and `quit`. Keep the terminal visible beside both apps. Forwarding is manual; one `flush` handles one item. If a listener restarts, quit/reopen the same relay database with updated ports. See [full CLI contract and recovery](../experiments/rescue-demo/RELAY_NETWORK.md#reproduce).

## Present in three minutes

| Time | Action | Visible evidence and narration |
|---|---|---|
| 0:00–0:25 | Show both interfaces and the relay terminal. | “One C++ engine serves two native audiences. This demonstration uses signed, encrypted messages over simulator-to-Mac sockets.” |
| 0:25–0:55 | Public sends the preset Floor 1 SOS, then Upload oldest queued message. | Show Waiting for delivery and one pending original. “Relay custody is only a saved copy; it does not confirm responder delivery.” |
| 0:55–1:20 | Run `flush` once, inspect responder; run `flush` again. | Responder has the SOS after the first forward; public still waits. The reverse receipt then changes public delivery to Received by responder device and clears the original. |
| 1:20–1:45 | Responder selects Acknowledge SOS, uploads; run `flush` twice. | Show Acknowledged by responder as a separate human action. “Device receipt and human acknowledgment are different facts.” |
| 1:45–2:10 | Responder sends the preset reply, uploads; run `flush` twice. | Show the reply in public history and its return receipt on responder. No action uploads automatically. |
| 2:10–2:40 | Public selects Floor 4 and queues a correction. Terminate/relaunch the public app. | Pairing, route, corrected location and one pending message survive; networking remains stopped. Restart listening and reopen the relay with its current endpoint ports and the same database. |
| 2:40–3:00 | Upload the correction; run `flush` twice; inspect history and `state`. | Original Floor 1 and correction Floor 4 remain distinct. Both endpoint queues and relay custody drain. “Physical radio and private-data readiness remain future validation gates.” |

The timing is a speaking budget, not a measured runtime. If restart setup exceeds it, use the recovery sequence as an optional extension. Stop both listeners and `quit` the relay after presenting.

## Optional recovery extension

Before uploading the queued correction, quit the relay and attempt upload. Show Connection refused with the original still pending. Reopen the same relay database with current endpoint ports, retry and forward the event and receipt. The [attended observation record](../experiments/rescue-demo/native-relay-evidence.json) records this recovery plus responder background/return and process restart. Backgrounding stops networking; demonstrate preservation rather than background delivery.

For an automated terminal demonstration of nonoverlapping contacts, exact encrypted retries and lost-response recovery, build the host above, then run:

```text
python3 experiments/workflow-model/tests/relay_network_smoke.py --host /PATH/TO/rescue-relay-host
```

The harness creates fresh synthetic endpoints and test-owned login-Keychain identities, checks eleven named facts and cleans up owned processes/accounts. This is a separate Mac-process demonstration, not native UI automation or a latency benchmark. See [process evidence](../experiments/rescue-demo/RELAY_NETWORK.md).

## Evidence to share

| Claim | Supporting evidence | Boundary |
|---|---|---|
| Native encrypted relay SOS, acknowledgment, reply and correction | [Native walkthrough](../experiments/rescue-demo/NATIVE_RELAY.md), [structured record](../experiments/rescue-demo/native-relay-evidence.json) | One attended simulator exercise: four events and four reverse receipts, eight successful flushes |
| Durable encrypted retries across interrupted contacts | [Separate-process relay checks](../experiments/rescue-demo/RELAY_NETWORK.md) | Sequential loopback contacts on one Mac; no physical or firewall isolation claim |
| Repeatable direct-exchange measurement | [Measurement report and raw evidence](../experiments/rescue-demo/MEASUREMENTS.md) | 20/20 trials, 80 confirmed original transfers; earlier plain direct baseline, not signed-relay performance |
| Repeatable signed-relay recovery evaluation | [Signed-relay report/raw evidence](../experiments/rescue-demo/RELAY_MEASUREMENTS.md) | 20/20 loopback scenarios, 60 original confirmations; fault-recovery cycles and command timings, not native/radio latency |
| Automated native-control regression coverage | [Code checkpoint evidence](../experiments/rescue-demo/NATIVE_RELAY.md#code-checkpoint-evidence--2026-10-08) | Recorded checkpoint: 96 Swift, 43 sanitizer CTest, 13 relay Python and 14 measurement-harness checks; not a fresh run by this document |

Suggested résumé wording:

> Built a C++20/SQLite rescue-messaging engine with native SwiftUI public/responder interfaces, CryptoKit signed/encrypted envelopes and durable relay custody; demonstrated SOS, device receipts, human acknowledgment and restart recovery through an iPhone/iPad simulator-to-Mac relay.

Optional signed-relay measurement bullet:

> Built a reproducible signed-relay evaluation harness; completed 20/20 Mac loopback recovery scenarios with 60 confirmed SOS/acknowledgment/reply events, exact retry checks and delayed reverse receipts.

Optional separate plain-direct measurement bullet:

> Created a reproducible Mac loopback failure/recovery harness; completed 20/20 plain direct-exchange trials with 80 confirmed original-message transfers and duplicate/lost-receipt checks.

Do not describe these as field reliability, mesh coverage, measured secure-relay latency or emergency-service readiness. Endpoint SQLite bodies remain unencrypted; manual pinning is not agency enrollment. Both native audiences, explicit delivery semantics and reported-location history are central to the demonstration.
