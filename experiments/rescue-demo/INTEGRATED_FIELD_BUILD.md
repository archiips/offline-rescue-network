# Integrated field-test build

This experimental build keeps the public iPhone and responder iPad journeys. It is a synthetic drill, not an emergency service or UW deployment. Physical retesting remains pending.

## Prepare before testing

An organizer prepares a public profile and explicitly approves responder device cards. The bounded local organizer service proves device-key possession before returning an issuer-signed profile. A public profile can carry up to four prepared responder credentials for delayed first contact. The app still requires explicit organizer fingerprint approval during preparation; no code copying or peer selection is required when sending an SOS. Old profiles without a directory retain automatic registered direct discovery but cannot initiate registered relay first contact.

The registrar supports `--serve-local-network PORT` and up to four `--authorize-responder-card REQUEST.txt` entries; for example, `rescue-enrollment-registrar --serve-local-network 8787 --authorize-responder-card responder-request.txt`. Ordinary attended file issuance creates the organizer identity first; service mode requires that existing Keychain identity. This explicitly launched local service is advance preparation, not an internet account backend. It does not verify UW membership. Renewed credentials retain device keys/history. Revocations are prepared snapshots of credential serials; removing a card from the allowlist prevents fresh authorization, and disconnected devices cannot learn later policy changes automatically.

## Communication

Opening the prepared request workspace starts foreground direct discovery and, where a responder directory is available, registered relay discovery. Saving an SOS commits C++ work before network sending. Unreachable contacts leave it queued. A participating device can choose **Participate as encrypted relay**, then **Start foreground relay**. Returning to the request workspace ends relay participation. Backgrounding or Stop ends contacts; restart retains histories/custody.

The relay holds encrypted packets and verifies public signed credentials. It cannot decrypt the request body. A fresh destination-key readiness proof precedes retry consumption. Delivery requires a correlated destination-signed receipt; custody, device delivery, human acknowledgment and handling remain separate facts. A responder inbox holds up to sixteen independent public conversations. Responses return through direct contacts or a relay that previously received that conversation's credentials.

A delayed-contact test needs three endpoints: public, relay and responder. Let public upload while responder is absent; stop public, start responder, then stop responder and return public for the reverse receipt. Repeat for acknowledgment/reply. Exact duplicate custody may remain until the destination reconnects or the packet expires. This is store-and-forward, not unlimited radio range or guaranteed background mesh. Frames/custody are bounded; unusually large credential-plus-content packets fail explicitly.

## Floor research

Open location research, request sensor observations, and explicitly capture the connected Wi-Fi access point when permitted. PersonalDebug lacks Access Wi-Fi Information capability; unavailable observations remain unavailable. This is the connected AP only, not a scan of campus Wi-Fi.

A local survey map is a strict JSON object with `version: 1` and `entries`. Each entry has `campus`, `building`, `provenance`, integer Unix-second `surveyedAt`/`expiresAt`, normalized `bssid`, and integer `minimumLevel`/`maximumLevel`. Maximum 64KiB/128 entries. Use synthetic AP identifiers in shared fixtures; keep real maps private. Enter the exact campus/building context. A fresh matching AP observation contributes the surveyed coverage interval, not the AP's installed floor. Wrong context, stale evidence, conflicting sensors or a multi-floor interval yields Unknown/ambiguous rather than a confident floor. Local capture can record a fresh reference interval with explicit provenance; it remains in memory and must be recaptured after recording.

Nearby participating phones contribute consented, dated sensor observations to the graph through separate explicit research pairing. Emergency SOS does not require that research pairing. A radio contact alone does not establish equal floors. Raw Wi-Fi identifiers stay local. **Use dated estimate in request draft** explicitly adds a single-level estimate, its source and original observation time to review. Manual reported floor remains independently editable. Estimates are unvalidated; later views preserve their age rather than implying live tracking.

## Combined physical checklist (deferred)

1. Home: updated public iPhone/responder iPad prepared direct SOS, receipt, human acknowledgment, reply, stop/restart; document whether router internet, cellular, Wi-Fi and Bluetooth are on independently.
2. Home: three-endpoint delayed registered relay, wrong/stale credentials, unavailable destination and later recovery. Test router-free contacts separately; do not infer the radio path from Wi-Fi icons.
3. Bothell: collect consented private connected-AP coverage references with ground-truth floor/building; test permissions, cross-floor coverage and sensor disagreement. Measure failures and Unknown outputs as well as successes.
4. Seattle: repeat with a separate surveyed context and held-out observations. Shared Wi-Fi login does not transfer a building/floor map between campuses.

No beacon purchase or installation is required by this build. Location accuracy, reliable physical range, campus-network peer isolation, device compatibility, battery/background behavior and emergency readiness remain unverified. SQLite message bodies remain unencrypted at rest; keys/trust remain in Keychain. Use synthetic request content.
