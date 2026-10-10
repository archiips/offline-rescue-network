# Bounded registered responder inbox

## Brief and authorization

One rescue product retains public iPhone and responder iPad interfaces. Prepared users open the app and submit a synthetic SOS without emergency pairing or Transfer. Extend the current single-conversation registration drill to one responder with up to 16 independently registered public devices. On 2026-10-10 the user explicitly authorized autonomous design, implementation, delegation and verified publication without checkpoint questions. Physical tests remain deferred.

## Design

Reuse one existing C++ endpoint and SQLite outbox per exact public pairing card. Its fixed sample request/event IDs remain confined to that store. A stable responder identity/credential signs every conversation; never generate a different responder identity per public device. Extract a narrow internal enrollment-conversation interface from SecureEndpointController, leaving its existing behavior intact.

The inbox has one listener, an exact-card registry and at most four provisional peer contexts with ten-second monotonic leases. Validate issuer/role/credential and possession proofs before admitting a candidate. Neither Hello nor Finish creates a durable conversation. Route encrypted packets by full sender digest only as a lookup hint, then verify signature, recipient, exact card, fresh authorization and C++ event validity.

For first admission, preflight the decrypted first event through a disposable C++ endpoint, then save its exact public-card binding in a Keychain admission journal before creating durable inbox history. C++ commits the event and receipt into a deterministic responder-epoch/full-public-digest database; atomically move the binding from journal to admitted registry before returning the encrypted receipt. If registry finalization fails, withhold the receipt. A retry of that exact authenticated identity reconciles the journal and committed database. Missing registry with databases and unlisted databases fail closed. A journal without a database represents interruption before first commit and can retry the unconfirmed original. Never delete an orphan, replace keys, silently reset admitted history, or evict existing work. Registry capacity is 16 including journal bindings; bounded provisionals are not multiplied by inbox size.

Actions take an explicit immutable conversation ID. Replies and receipt confirmations use that conversation's envelope and C++ endpoint. A bounded round-robin outbound worker attempts each authorized peer, so unreachable peers do not permanently starve others. Stop/background invalidates all ephemeral destinations and proofs; restart retains identities, registry and outboxes and requires fresh possession proofs.

Native responder preparation opens an inbox, with selection and the existing acknowledgment/reply/handling/conversation UI for each row. Public registered mode remains unchanged. Existing single-pair registration histories stay accessible separately; do not migrate or overwrite them automatically. Preparation gains a tested validity summary with role, realm and effective expiry, plus visible renewal instructions. File import remains an advance synthetic organizer flow, not consumer or UW enrollment.

## Alternatives and critique

A shared C++ database would collide on fixed IDs and needs a broad wire/schema/action migration; defer it. Independent responder keys would break the issued credential; reject it. Removing pin checks would allow cross-recipient mixing; reject it. Per-peer stores are simpler but bound this checkpoint to one request history per public identity and one responder authority. Registry failure after C++ commit needs explicit retry tests. Enrolled-user capacity abuse, trusted time and discovery denial of service remain limitations; no open-public abuse resistance claim.

Security/privacy: only public bindings enter registry, no issuer secrets enter app; SQLite bodies remain unencrypted and synthetic-only. No new dependencies, Wi-Fi claims, background execution or automatic relay claims. Test selected-row action isolation, lost receipts, registry failures, corrupt/missing metadata/history, expiry and full capacity. Inspect rendered UI; a build alone does not prove native interaction usability.

## Acceptance

Two independently enrolled public devices both send their fixed sample IDs and produce distinct inbox rows. Acknowledgment/reply/handling/correction for A never changes B. Wrong-conversation receipts and authentic envelope substitutions fail. Duplicate admissions remain one row. Restart and failed registry admission retain exact C++ history and recover via authenticated retry. Abandoned proofs use no durable slot; full inbox rejects without eviction. Existing training/manual Secure/relay/research journeys remain available. Actual local sockets prove automatic three-endpoint round trips; physical and complete native trust walkthrough limits are recorded separately.

## Evidence basis

Local inspection at `2405d3b`: C++ Model can represent many requests, but endpoint bridge fixes actor/exercise/request IDs; SecureEndpointController and EnrollmentBootstrap intentionally pin one peer. Existing CryptoKit, Keychain and Network adapters are reused, with no new external API assumptions. See REGISTERED_EXCHANGE.md and the existing enrollment design for current official API references and trust boundaries. Independent read-only architecture/scope agents confirmed these constraints. Review the implemented security boundaries with Claude Opus 5.5 / medium before publication.
