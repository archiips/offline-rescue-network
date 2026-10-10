# Registered responder inbox — bounded synthetic checkpoint

One prepared responder can retain up to 16 independent public-device conversations. Each public device keeps the existing automatic registered SOS/receipt/acknowledgment/reply workflow. This extends the [prepared-registration drill](REGISTERED_EXCHANGE.md); it is not a live campus account or UW authorization service.

## Use

Prepare each device before an outage using its own public registration request and the same synthetic organizer realm. Never copy private keys or bundle an issuer secret in the app. Complete organizer verification before emergency use. Public mode starts foreground discovery automatically and saves requests while disconnected. A newly prepared responder opens its inbox automatically. Received requests appear as separate rows; select a row before acknowledgment, reply or handling actions. Updates and device receipts belong to that selected device's conversation.

Preparation shows the device role/realm and the earlier of credential expiry and signed-policy cutoff. The local device clock is still an experimental assumption. Expired/revoked/incorrect preparation blocks exchange; renewal retains device keys and histories. Offline revocation is only as fresh as the prepared signed snapshot. Readiness does not mean any responder is reachable.

An upgraded responder with an existing single-pair history retains that workspace. **Open inbox for new public devices** opens separate inbox stores using the same responder identity and credential. **Open saved single-pair conversation** returns to the earlier history. No pin is removed and no old request history is automatically imported. A public device continuing a previously confirmed legacy request uses that saved single-pair workspace; new public devices use the inbox. This explicit transition avoids silently resetting or reassigning an existing request.

Keep the workspace open for exchange. Stop/background ends networking and proof leases; local responder actions can still be saved while stopped. Resume requires fresh possession proofs independently for each peer. Public idle rediscovery after a responder restart is covered by a real socket regression; no manual Transfer is required.

## Isolation and recovery

- One stable responder signing/agreement identity; one independent C++ endpoint/SQLite outbox per full public-card digest. Fixed synthetic event IDs remain confined to their own database.
- SQLite endpoint v3 stores an immutable responder/public binding, checked on load and save. Existing training v1 and single-endpoint v2 remain unchanged. Bound open rejects an empty existing file, unbound legacy store and intact differently bound database; it never attaches a new binding to an old database.
- Hello/Finish alone create no visible/durable conversation. Four provisional candidates share a ten-second monotonic limit. Issuer/role/credential, possession, encrypted recipient/sender and C++ application validity all precede admission.
- A public-card admission journal is saved in Keychain before durable C++ first-event storage. The first event/receipt commits before registry admission, and registry admission completes before a receipt returns. Failure after event commit withholds the receipt; authenticated exact retry/restart reconciles the journal and history without duplicate requests.
- Registry capacity is 16 including admission recovery bindings; full capacity never evicts another conversation. Known SQLite recovery sidecars must match exact registered filenames and pass existing C++ bounds/mode checks. Missing/corrupt registry, unlisted history, missing admitted history and stale keys/registry fail closed.
- Actions capture immutable conversation IDs. One packet/candidate attempt per authorized conversation per worker pass bounds outbound work; unavailable A does not permanently prevent reachable B from receiving a reply.

Bindings protect against accidental or intact other-conversation database substitution. They are ordinary SQLite metadata, not encrypted or cryptographically authenticated storage: coordinated host edits and same-conversation rollback remain undetected. An interrupted initial bound-database creation can fail closed rather than automatically reset. An empty rollback-sidecar test is not proof of actual power-loss/hot-journal recovery. Retain synthetic data only.

## Verification record

Behavioral regressions exercise identical sample IDs across two public devices; acknowledgment/reply/handling isolation; authentic cross-recipient packet/receipt rejection; invalid first-message rejection; four-candidate expiry; full 16-binding capacity; exact retry after final registry write failure and restart; missing/corrupt/bound-transplanted/empty history; stopped action saving; abandoned-proof restart; legacy-workspace preservation; and actual three-endpoint Bonjour/socket SOS/reply, unreachable-peer fairness and responder restart with no pending public work.

The execution ledger records final commands/counts: [registered inbox plan](../../docs/superpowers/plans/2026-10-10-registered-inbox.md). Computer Use inspected both unregistered native preparation roles. The complete native credential approval/inbox interaction walkthrough and physical latest-build/offline/radio/range tests remain unexercised. Earlier physical screenshots only establish the older functional round trip on internet-connected Wi-Fi. Automatic relay, multiple simultaneous responder authorities, multiple request histories per public identity, open-public abuse resistance and operational readiness are outside this checkpoint.

An attempted requested Claude Opus 5.5/medium review could not run: sandbox invocation returned Not logged in; automatic approval review rejected external repository transmission. ChatGPT agents reviewed the architecture, native upgrade flow and storage boundary instead; parent independently reviewed the delegated binding implementation. No substitute Claude model or workaround was used.
