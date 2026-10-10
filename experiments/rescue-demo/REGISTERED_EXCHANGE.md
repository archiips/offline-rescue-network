# Prepared-registration drill

The later [bounded registered responder inbox](REGISTERED_INBOX.md) adds up to 16 isolated public-device conversations, preparation validity summaries and an explicit preserved-legacy workspace selector. The single-conversation protocol and dated evidence below remain its foundation; physical and real-authority gates stay open.

Status: experimental synthetic enrollment, one public/responder conversation. This is not UW authorization, a public account service, an audited security protocol or physical offline proof.

## What works

An organizer prepares signed credentials bound to each device's existing signing/encryption keys, role, realm, serial and expiry. A fully issuer-signed preparation profile includes the credential, trust cutoff and revocation snapshot. A public device automatically discovers a responder, verifies issuer authorization and fresh possession proofs, then sends its encrypted SOS without manual endpoint pairing or Transfer. Existing C++ queues and distinct device receipt/human acknowledgment/reply facts remain authoritative.

Native Setup → Prepared registration drill supports both roles, public-only request export, bounded profile import, explicit organizer fingerprint verification and Keychain-held profile/keys. Complete preparation before an outage. A completed profile makes the registered workspace the next-launch entry; Other demo modes returns to the preserved original interfaces. Foreground entry starts discovery; background stops it, foreground return resumes unless explicitly stopped. Stop is visible on the workspace; there is no background guarantee. The registered workspace is separate from manual Secure, Training, relay and sensor research; reported place/floor remain manual and synthetic. There is no automatic phone relay in this mode.

## Attended preparation

1. Open Setup → Prepared registration drill. Select Public or Responder and export the registration request. It contains a public card only, not private keys or a person's location.
2. A trusted drill organizer runs the local Mac registrar for that request. Public role cannot issue responder actions; responder issuance requires an explicit organizer CLI option. That option is an attended operator control, not production identity verification.
3. Import the resulting JSON on that same device. Compare the complete issuer fingerprint with the organizer through a trusted channel and complete preparation. The issuer key in a file is not self-authenticating. Do not import arbitrary unsolicited profiles.
4. Keep both registered workspaces foreground. Review/send the sample SOS. Discovery, credential bootstrap and queued delivery run automatically; acknowledge/reply on the responder. No emergency-time public-card copying, fingerprint comparison, QR scan or Transfer is needed after preparation.

Run from repository root with requests/profiles under ignored `private-data/` (or private scratch). The organizer executable is built with the existing Swift package:

```sh
swift build --package-path experiments/workflow-model \
  --scratch-path /private/tmp/rescue-enrollment-swift --product rescue-enrollment-registrar
/private/tmp/rescue-enrollment-swift/arm64-apple-macosx/debug/rescue-enrollment-registrar \
  public private-data/public-request.txt private-data/public-profile.json
/private/tmp/rescue-enrollment-swift/arm64-apple-macosx/debug/rescue-enrollment-registrar \
  responder private-data/responder-request.txt private-data/responder-profile.json --authorize-responder
```

Use the actual architecture-specific Swift build output if different. macOS may require the organizer to approve Keychain access after rebuilding the registrar binary; do not disable Keychain controls or rotate the issuer as a workaround. The registrar stores its issuer private key in Mac login Keychain, never in the public app, exported profile, Git or logs. Credentials/profile cutoff expire after 24 hours; start is backdated five minutes for small preparation-clock skew. This does not establish a trustworthy device clock. The underlying credential adapter caps validity at seven days.

Revoke a credential serial with `rescue-enrollment-registrar revoke SERIAL_UUID`, then issue and distribute fresh profiles to the remaining drill devices. Serial is printed during issuance and is in the public credential. The local issuer keeps a bounded list of up to 64 revoked serials; profiles are still bounded to 4096 bytes. Already-offline profiles do not refresh: old policy can remain valid until its cutoff. This is snapshot revocation, not live revocation or comprehensive device-compromise recovery. Use Update registration to import a newer signed policy before a drill, or renew the same device's profile when preparation is unavailable/expired; existing key/history binding remains. Different saved peers are never automatically replaced. Multi-request responder enrollment/release needs a separate design; do not delete Keychain/history manually to claim recovery.

## Protocol boundary

Distinct `_rescue-reg._tcp` uses existing bounded Network-framework sockets, including the existing peer-to-peer option. Bonjour name/fingerprint prefixes are routing hints only. Four signed domains bind Hello, Challenge, Finish and Ready to exact canonical transcripts and random 32-byte challenges. Neither Hello nor Challenge changes pins. Finish gives the responder only a ten-second provisional lease; an authenticated encrypted application packet is required before it saves a pin. Ready is also provisional at the public device; it saves a pin only after an authenticated device receipt. Idle, lost-packet and abandoned handshakes save neither public nor responder pin. Abandoned Finish/lost Ready cannot persistently occupy its conversation. Repeated Hello from the same public key uses at most one pending entry; exact replay preserves a completed lease and a new Hello cannot erase it. At most four public keys are pending. Concurrent Finishes are resolved against the authenticated packet sender. Exact Finish retries recover the same Ready while the lease is valid. Stop invalidates callbacks and pending proofs. Registration does not broaden radio range or establish proximity.

Issuer, realm, role, card, signature, credential time and prepared policy cutoff/revocation are checked. Every active application operation revalidates authorization. No certificate/name can replace an existing different pin, and no plaintext fallback exists. Stable public credential/fingerprint hints are linkable; sizes/timing remain observable. Malicious enrolled users can consume the one-conversation capacity with an authenticated request. Hostile discovery flooding, fairness, organization enrollment, trusted time, encrypted local message storage and independent audit remain open.

## Evidence

Real Mac Bonjour/socket tests start from unpaired enrolled secure endpoints, then verify automatic SOS/device receipt/acknowledgment/reply, saved-while-stopped retention and restart recovery. Credential tests cover issuer/realm/role/time/revocation/canonical parsing and equal-shape semantic tampering. Handshake tests cover stolen-certificate possession failure, transcript substitution, stopped/expired proof, existing-pin refusal, lost Ready and per-identity pending bounds. Profile tests reject unsigned policy changes and revoked serials. Controlled removal of issuer-signature and transcript-binding checks caused expected behavioral test failures; checks were restored before full verification.

The native preparation screens for both roles were inspected through Computer Use on an iPhone 16 Pro Simulator/iOS 18.3. Final verification: 172 Swift Testing + 6 XCTest checks pass, signed Simulator build succeeds, and three Opus 5.5/medium reviews identified issues that were reproduced and corrected. Full prepared native import/trust/send walkthrough is not claimed from that screen inspection; the complete enrolled exchange is verified at controller/socket level. Physical updated-build tests remain deferred at the user's request because the iPad is unavailable. Original physical screenshots prove an internet-connected Wi-Fi round trip only. See the execution plan for final check counts and review outcomes.
