# Security and privacy

> Bounded portfolio checkpoint (2026-10-08): [secure exchange evidence](../experiments/rescue-demo/SECURE_EXCHANGE.md) now establishes manually paired signed/encrypted Apple endpoints with C++ durable state. Full-product enrollment, private storage and physical gates remain open; CryptoKit is an Apple adapter, not portable C++ cryptography.

> Current execution status (2026-10-08): see [current state / resume](CURRENT_STATE.md) and [portfolio tasks](TODO.md#current-portfolio-tasks). This document retains its product requirements, proposal or dated evidence; it does not claim that all described capabilities are implemented.

Status: initial threat model and requirements, v0.1 · 2026-10-07

The first deployment is a prepared exercise with synthetic requests. This boundary enables testing; it is not the eventual public onboarding design. See [system design](SYSTEM_DESIGN.md) for records and [tasks](TODO.md) for the security gates.

## 1. Assets and adversaries

Protect request content, precise personal location, participant identities, responder authority, key material, and the integrity of delivery/handling status.

Assume an untrusted nearby device may listen, inject, replay, advertise a false name, flood peers, withhold messages, or leave at any time. An enrolled relay may be compromised. A phone may be lost. A legitimate participant may submit inaccurate information. A signature proves origin/authority, not the truth of a reported emergency.

Outage resilience does not prevent jamming or guarantee delivery through malicious relays. Offline revocation cannot reach an isolated device instantly.

## 2. Prototype enrollment and authority

- The exercise coordinator establishes an authority key and an exercise identifier before the drill.
- Participants scan/verify an enrollment artifact supplied in person. It binds the exercise, command public identity, and assigned role.
- Responder authority requires coordinator-approved credentials. A role selection in the UI, peer name, Bluetooth pairing, or OS link encryption does not grant it.
- Public participants can create/correct/withdraw their own request. Relays can hold and forward opaque messages. Responders can acknowledge/reply and update handling status.
- Both endpoints can issue authenticated device receipts for messages addressed to their own enrolled identity, after durable commit. A public receipt grants no responder authority. Optional operator display labels are command-supplied text, not verified individual identities.
- The prototype has one command endpoint identity. Provision its key to the coordinator and distribute the verified public key to participants. The public endpoint exposes its verified reply key through enrollment.
- Reject exercise/role mismatch and expired credentials according to the provisioning policy. If time validation is unavailable, require coordinator revalidation rather than treating a claimed role as verified.

Provisioning metadata may expose exercise participation; it should not include unnecessary names, addresses, or phone numbers.

The M1 responder interface includes a coordinator-only setup path for prepared enrollment. SEC-01 determines credential issuance, coordinator authentication, and key ownership before implementing it. A setup screen is not a security mechanism by itself; no third coordinator app or automatic elevation from public to responder is implied.

## 3. Cryptographic gate

SEC-01 must select and document a reviewed encryption/authentication construction and maintained library available on the target devices. Record dependency version/license, identity-to-encryption binding, replay behavior, key storage, test vectors, and library error handling.

Use endpoint encryption for private bodies and authenticated binding for envelope destination, exercise, version, and event identity. Keep relay-visible metadata minimal. Protect receipts and human status events with issuer authority and integrity. Use platform link encryption as an additional layer, not as a substitute for endpoint privacy.

Do not implement custom cryptographic primitives or treat a design document as a security review. A synthetic-data transport experiment may precede this gate; private/pilot data may not. Persisted relays store ciphertext. Endpoints use platform data protection for private records and platform-protected key storage. Plaintext diagnostic logs are forbidden.

## 4. Privacy and consent

M1 needs a description, a reported location, and an incident-scoped reply identity. Real name, phone number, continuous background location, microphone, camera, and medical profile are not required.

Ask for OS location only when useful and provide manual entry if denied. Sensor-research consent is separate from assistance submission. Raw sensor logs, ground-truth labels, and replay exports are opt-in exercise artifacts. No automatic analytics or cloud upload is part of the initial design.

For prepared synthetic-data drills, use a provisional maximum local retention of 7 days after exercise closure, with immediate explicit deletion available. Encrypted relay payloads are deleted when the exercise ends. Exported copies do not disappear when a local record is deleted; export requires an explicit destination and retention notice. A partner's real-data retention needs a separate agreement before collection.

A requester may retain an unresolved record locally, but this never authorizes ongoing discovery after drill closure. If participants want to retain data past the exercise default, use a clearly consented export rather than silently expanding retention.

## 5. Abuse and resource controls

Bound envelope size, frame assembly, queues, retries, and inventory exchange as specified in the system design. Rate-limit per enrollment identity and peer; limits must account for legitimate follow-ups and must never invisibly discard an accepted local SOS.

Test revoked/unknown identities, forged responder events, replay, duplicate floods, oversized frames, and messages directed to other exercises. Public-launch abuse needs additional identity/discovery and capacity design. Per-device limits alone do not stop Sybil identities in an open network.

## 6. Lost devices and revocation

Support ending an exercise locally and distributing coordinator-approved closure/revocation updates when contacts exist. Prepared exercise membership includes a planned end time; devices with validated time stop forwarding then, and other devices require local coordinator closure. An isolated device cannot learn an early closure instantly. Log the last known authorization context. The prototype cannot retract data already decrypted/exported by a recipient or immediately revoke a disconnected device. Record these limits in a pilot agreement.

Choose key backup/rotation and command-device replacement procedures before a partner pilot. Private keys must never enter committed fixtures or exports. Check ignore rules for any development signing/secrets before future commits.

## 7. Required review evidence

Before a supervised pilot: provisioning walkthrough; threat-model review; integrity and role-spoof tests; encryption/decryption and replay tests; database/log/export inspection; lost-device/revocation exercise; retention/deletion exercise; dependency/license review; partner approval for intended data and use.

This list is specific to our proposed workflow, not a claim of certification or a universal set of regulatory requirements. Determine applicable obligations from the intended use, equipment, jurisdiction, and integration partner before operational deployment.
