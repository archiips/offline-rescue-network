# Controlled foreground native relay — 2026-10-09

Setup → Host a relay on this device opens a separate native workspace. Copy the public and responder public cards, compare both complete fingerprints on their endpoints, confirm the comparison and save. Set a listening port and each endpoint’s current host/port. Start listening; endpoints explicitly upload via their relay route. Each Forward one saved packet tap attempts one eligible packet, including reverse receipts. Stop, leaving the workspace, or backgrounding stops networking. Reopen never automatically starts.

The relay reuses the signed ORL1 transport, RelayService and bounded C++ SQLite queue. It has no endpoint private keys and cannot decrypt private bodies. Custody is distinct from destination receipt and human acknowledgment. The original sender remains waiting until the signed destination receipt returns. This is a prototype; it does not contact emergency services.

## Persistence and interruption

Public cards bind a domain-separated SHA256 profile ID to a separate queue. Switching A/B/A reopens A’s queue and preserves B’s files. The active profile pointer is written atomically after successful configuration. Invalid/swapped/same-role cards are rejected before writes. Missing, corrupt, mismatched or symlinked final profile/queue files fail closed. No automatic deletion or adoption of unrelated custody. Configuration is disabled while listening or forwarding. Stop remains available during forwarding; a post-await generation check prevents a stale operation from deleting custody or publishing success. Interrupted attempts still consume the bounded retry budget.

A crash between queue creation and profile publication can leave an orphan queue; recovery then requires deliberate inspection rather than automatic deletion. Filesystem checks do not provide a hardened guarantee against parent-directory substitution, SQLite sidecar manipulation or concurrent local filesystem races. Endpoint history storage remains unencrypted. Public routing metadata is visible. Private-data, security-audit, agency-enrollment and physical-network gates remain open.

## Fresh verification

- Full Swift package: 106 Swift Testing + 4 XCTest checks passed. Ten new host tests cover invalid cards, stopped reopen, pair-bound queue preservation, damaged configuration, invalid roots/contacts, failed listener status, actual-socket SOS/receipt/ack/reply, swapped destinations and stop during forwarding. Removing the post-await fence makes the stop/retry regression fail (mutation checked, then restored).
- Sanitizer C++ CTest: 43/43 passed; shared engine/protocol unchanged.
- Existing Python measurement/relay harness:47/47 passed with Python 3.14 and loopback access, including the separate-process recovery scenario.
- Signed generic iOS Simulator build passed for the native target.
- Claude Code implementation and independent read-only reviews used canonical `claude-opus-5-5`, explicitly launched with `--effort medium`, no fallback. Review found a missing sheet environment injection, invalid-root handling and premature listening text; each was fixed, with regression tests where applicable. Follow-up review found no remaining Critical/Important issues.

## Attended native observation

Computer Use exercised an iPad Pro 11-inch M5 simulator on iOS 26.4 (`Rescue Location Check`, 467E1A4B-58D1-48EA-BE2A-CD727CCD81E9) as the relay, with two fresh manually pinned Mac CLI endpoints over loopback. Existing paired native endpoints were untouched; the simulator’s earlier three-message location training history survived installation and restart.

| Step | Observed result |
| --- | --- |
| Configure | Both complete endpoint fingerprints matched, saved profile and manual ports 47100/47101/47102. |
| SOS upload | Native custody 1; public still waiting with pending 1. |
| Forward SOS | Responder accepted event; sender still waiting until reverse receipt. |
| Forward receipt | Public deviceReceived, pending 0. |
| Ack and receipt | Two manual forwards; public humanAcknowledged. |
| Reply upload, Stop, app restart | Native reopened stopped, saved profile/contacts and custody 1 retained. |
| Resume reply and receipt | Two manual forwards; native custody 0; both endpoints pending 0, messages 3, humanAcknowledged. |
| Leave and reopen | Networking stayed stopped; custody 0. |
| Start, Home, reopen | Networking stopped after background; custody 0. Rendered form inspected. |

Synthetic event IDs: SOS `4ff136772c96c920860f2f3dc5d601c3b18a268e5b671a3c2a90efb287629b3f`; acknowledgment `6cabfa7d9da811917ec7a3751f2b2bf123d6ec2790c64aee288def21e449c4f5`; reply `adaad2554fbc0c17fceb0e50f8ea1a3bfbc4070cf28373defe81079557766f7a`. Six successful manual forwards carried three events and three reverse receipts. CLI endpoints exited and the native host was left stopped with zero custody.

This is native host UI plus separate-process loopback evidence, not three physical phones, radio distance, isolated OS networks, background mesh, automatic discovery or Find My access. No new range guarantee follows. Next localization research is recorded in [the UW roadmap](../../docs/UW_LOCALIZATION_ROADMAP.md).

## Commands used

```sh
swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-location-swift
ctest --test-dir /private/tmp/rescue-location-cmake --output-on-failure
xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-phone-derived CODE_SIGNING_ALLOWED=YES build
RESCUE_RELAY_HOST=/private/tmp/rescue-location-swift/debug/rescue-relay-host RESCUE_EXCHANGE_HOST=/private/tmp/rescue-location-swift/debug/rescue-exchange-host python3 -m unittest discover -s experiments/workflow-model/tests -p 'test_*.py'
```

The Python harness needs Python 3.11+ and permission to bind loopback sockets; system Python 3.9 and restricted socket execution are unsupported verification environments.
