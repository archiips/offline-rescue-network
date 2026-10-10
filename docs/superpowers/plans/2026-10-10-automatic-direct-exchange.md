# Automatic direct secure exchange

## Outcome and investigation

A previously paired public/responder pair should exchange saved SOS, acknowledgments and replies while foreground exchange is explicitly running, without selecting Transfer in Setup. Registration and organization credentials are separate work. Current DemoController only learns `peer` in manual transfer; discovery updates a transport array without scheduling delivery. Failure clears `peer`, so there is no retry target. Existing socket receipt verification and durable queues are retained.

## Design and acceptance

Use existing Bonjour results and the last manually selected destination as connection candidates. A single cancellable foreground worker periodically attempts pending secure direct messages, bounded by the existing peer/session/packet limits and per-exchange timeout. Candidate names are untrusted routing hints; only existing pinned cryptographic verification can advance delivery. Never change pairing or fall back to plaintext. Stop/background, route changes, role changes and reset cancel the worker and fence completions. Relay remains manual. Plain diagnostics retain their current controls.

1. Reproduce absence of automatic SOS delivery with real secure controllers, sockets and Bonjour, with no manual transfer call.
2. Add foreground discovery/retry worker, preserving existing manual controls and generation fencing.
3. Verify automatic SOS/receipt/ack/reply, queued-before-start delivery and stop/restart. Run the complete Swift suite and signed native build; inspect UI delivery/queued state where available. Physical retest remains required after reinstall.

## Critique and limits

Correctness: dedupe/receipts remain owned by existing endpoints. Simplicity: reuse transport instead of replacing it. Privacy/security: unsolicited discovery names never grant authority; candidates receive only existing sealed packets, though connection metadata remains visible. Maintainability: one worker, cancelled on every existing stop path. Testing: real discovery may expose environmental multicast restrictions; report these rather than bypassing trust. UX: foreground Start remains explicit in this checkpoint; no background guarantee or registration capability is implied. Failed or absent contacts leave messages saved. Retry pacing must avoid a busy loop and manual/automatic simultaneous transfers.

## Verified checkpoint

- Before fix: `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-auto-swift --filter secureDiscoverySendsAndReturnsReplyWithoutManualTransfer` failed with SOS waiting and responder request absent after 12 seconds.
- After fix/final lifecycle cleanup: `swift test --package-path experiments/workflow-model --scratch-path /private/tmp/rescue-auto-swift` passed all 155 Swift Testing checks and 6 XCTest checks. Real Bonjour/socket tests cover automatic round trip, queued-before-start, stopped retention/restart and unrelated responder rejection/late valid contact.
- `xcodebuild -project experiments/rescue-demo/iOS/RescueDemo.xcodeproj -scheme RescueDemo -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/rescue-auto-derived CODE_SIGNING_ALLOWED=YES build` passed after final changes.
- `git diff --check` passed; user-local signing project changes excluded. No UI layout changes; real controller/network end-to-end checks exercise the affected behavior. Physical inventory reports disconnected/unavailable endpoints, so this fix is not installed or physically retested. Existing manual Start is still required for foreground exchange; enrollment and automatic background operation are out of scope.
