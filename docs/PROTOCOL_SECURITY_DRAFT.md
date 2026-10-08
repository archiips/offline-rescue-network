# Product message contract and security proposal

> Current execution status (2026-10-08): see [current state / resume](CURRENT_STATE.md) and [portfolio tasks](TODO.md#current-portfolio-tasks). This document retains its product requirements, proposal or dated evidence; it does not claim that all described capabilities are implemented.

Status: candidate for SEC-01/ENG-02 review, not a frozen protocol · 2026-10-07

The rescue product still has public and responder interfaces backed by C++. This document prepares implementation after transport evidence and security review. It is **not** the diagnostic probe's wire format.

## Message semantics

| Event | Sender allowed | Meaning |
|---|---|---|
| Request | Enrolled public device | New request with manual situation/location and unknown values permitted |
| Follow-up / correction / withdrawal request | Original requester | New immutable event linked to the original request; original acknowledgment does not cover this event |
| Destination receipt | Authorized destination device | Exact event was validated and committed locally; never means read, accepted by a human, or dispatched |
| Human acknowledgment / reply | Verified responder | Explicit human action, with referenced request/event IDs |
| Assignment / resolution / reopen / withdrawal disposition | Authorized command role | Explicit handling change with reason and monotonically increasing command revision |

Every event has an independent random event ID, exercise ID, request ID, authenticated sender and destination, schema version, event type, and bounded body. Replies/receipts reference the exact event they answer. Receipts are not themselves receipt-requesting, preventing acknowledgment loops. Unknown critical types/versions are rejected without changing state. Capability discovery cannot silently downgrade authentication or confidentiality.

Candidate initial budget: 8 KiB maximum entire encoded event, 2 KiB free-text body, 32 queued events per requester, separate reserved receipt/control capacity, exercise-wide queue bounds. These are **proposed test inputs**, not measured production limits. User-declared urgency is bounded and rate-limited; no model decides rescue priority. A saturated queue reports failure rather than silently losing accepted messages. Corrections/withdrawals are new events and share the emergency/control scheduling budget, so a delayed update is not buried behind routine content.

C++ validates and persists each local event transactionally before reporting it queued. The destination authenticates/authorizes/decrypts, validates references and bounds, then commits event + deduplication record in one transaction before issuing a receipt. Retries reuse the same immutable event ID/bytes. Duplicate delivery can regenerate a receipt; conflicting bytes for the same ID are rejected. The duplicate receipt is authorized and correlated just like the original. Never claim exactly-once transport.

Report observation time and uncertainty separately from local receipt time. Wall clocks are not sufficient replay defenses. C++ reducer owns delivery and handling independently. Resolved requests retain late updates for explicit review/reopen; an update never silently changes command revision. Scope the single command-authority assumption to one exercise. Multi-command conflict resolution remains deferred.

## Trust and provisioning

Prepared exercise only: coordinator pins an exercise authority through an attended enrollment step before the drill. Signed membership binds exercise, device signing/encryption keys, role, permitted actions, validity and key epoch. Public devices cannot self-assign responder roles. Bonjour names and radio connections are untrusted discovery hints.

Provision the command destination encryption key and the requester's reply encryption key from authenticated membership, not from an unsigned nearby advertisement. Keep signing and encryption keys distinct. A responder validates requester membership and request ownership; the requester verifies both responder membership and the action's authority. An exercise-local participant ID is not a real-world identity claim.

Membership/revocation updates must be authority-signed. Offline peers may have stale revocation information; show the last authority update and enforce a documented exercise validity/freshness policy. Do not claim instantaneous revocation or silently trust a clock that cannot be validated. Lost-device recovery/rekeying ends the prior key epoch; retained pending ciphertext may become unreadable. Resolve key access while locked, local data protection, backups and expiry before SEC-01 closes.

## Cryptography decision candidates

| Approach | Benefit | Limitation / decision |
|---|---|---|
| Authenticated TLS on each direct link | Reviewed channel mechanisms; matches Apple guidance | Does not by itself keep stored/forwarded bodies private from later relays; required peer trust/provisioning still needs design |
| Portable libsodium message encryption + signatures | C-compatible library usable by the C++ engine; recipients can retain/forward ciphertext | Primitives are not a complete application protocol; exact composition, context binding and key lifecycle need review |
| Apple CryptoKit for all envelope operations | Native integration | Would put portable security logic into Apple adapters or require a second implementation; not preferred for the shared C++ engine |

Working recommendation: evaluated portable endpoint-private envelopes, plus authenticated links where useful. Libsodium is a **candidate, not an installed dependency**. Its official docs list 1.0.22-stable and ISC licensing as accessed 2026-10-07. Pin the exact source revision/archive hash and check advisories before adoption; don't depend on a moving stable URL. Single-part Ed25519 signatures verify a trusted key's signature but do not encrypt. Sealed boxes hide a body from non-recipients but do **not** authenticate its sender. Neither mechanism alone satisfies this product's trust model.

Security review must select the complete envelope construction rather than copy this table into code. It must bind exercise, version, role credential, sender, destination, event/request IDs and ciphertext together; reject substitution across exercises, directions or recipients. Prefer a documented, reviewed construction with test vectors. Canonical/deterministic CBOR (RFC 8949) is a candidate encoding; if used, define duplicate-key rejection, integer/string bounds and deterministic encoding rules before signing. Do not sign an arbitrary reserialized JSON object.

Relays see only minimum routing/control information and ciphertext, never situation, floor/room or conversation. Metadata still reveals timing, participation and possibly traffic classes. Choose which controls are immutable/authenticated and which relay-local counters can change. Hop limits bound forwarding but do not create trust or guarantee delivery. Redact logs; do not persist plaintext diagnostics or raw key material. Hardware-backed key availability must be verified for the chosen algorithms instead of assuming every key is Secure Enclave-compatible.

## Required security evidence before private data

- Exact dependency/license/advisory/build provenance; Apple/C++ known-answer interoperability fixtures.
- Forged responder, unauthorized handling action, swapped recipient/exercise, modified body/header, stale membership, duplicate/conflicting event and replay rejection tests.
- Durable commit/receipt behavior across crashes, disk-full failure and restart; key loss/rotation and offline-revocation workflow.
- Defined retention, OS key/data-protection settings, lock-state behavior, encrypted export and log inspection.
- Review of the complete cryptographic protocol and denial-of-service limits. Claude review is useful engineering feedback, not an independent security audit.

NET-01, SEC-01 and ENG-02 remain open. Synthetic probing can proceed without these private-data capabilities; production rescue messaging cannot.

## Primary sources (accessed 2026-10-07)

- [Apple TN3213](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework): Network framework architecture/security and peer-to-peer support.
- [Libsodium introduction](https://doc.libsodium.org/doc), [signatures](https://doc.libsodium.org/public-key_cryptography/public-key_signatures), [sealed boxes](https://doc.libsodium.org/public-key_cryptography/sealed_boxes): version/license, trusted-key signatures, recipient encryption and absent sender authentication.
- [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949): CBOR encoding and deterministic representation considerations.
