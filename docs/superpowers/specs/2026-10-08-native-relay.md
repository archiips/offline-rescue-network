# Native relay controls

One portfolio app for public iPhone and responder iPad: manually paired endpoints exchange an SOS, device receipt, human acknowledgment and reply via the already verified Mac relay. C++ owns workflow/outbox/cache/custody; Swift owns Apple crypto, networking and native presentation. Synthetic presets only. No new dependencies or C++ protocol change.

## Discovery and chosen design

Baseline8bf23d3: DemoController wraps one secure endpoint; DemoShell persists mode/role, stops networking on background and presents shared LocalConnectionControls plus pairing. RelayEndpointController already supplies outgoing()/receive(), and LocalExchangeTransport(relayTimeout:) supplies bounded sockets. Preserve all existing public/responder actions, conversation, reported location, handling, Training and direct Secure exchange.

Add explicit `relayMode` under Secure exchange, keeping the same endpoint identity/history when changing route. Stop and invalidate old callbacks before changing route. Relay routing owns a RelayEndpointController wrapping the current secure endpoint; incoming relay frames use receive(), direct frames use accept(). Relay start uses a listener with advertisement/browsing disabled, random port by default. UI shows listening port and manual relay host/port fields. A test may request an explicit listener port through the ordinary start method; no debug-only production launch flags.

Manual upload sends only the oldest cached ORL1 and validates ORC1 ID. It never confirms the C++ outbox, loops over the same head, initiates direct transfers or automatically uploads a subsequent action. A returned device receipt is the only path clearing the original; human acknowledgment remains separate. Status says “Relay accepted a copy; waiting for device receipt” and explains that custody is unverified. Stop/route/role/reset/background invalidates in-flight upload results and clears session-only custody labels. Socket failure retains pending state. Pairing and existing reset confirmation stay available for explicit expired/full/lost-cache recovery; old epoch files are preserved.

UI: Direct / Via relay selector, shared controls for both audiences, Start/Stop relay exchange, listener port, Relay connection disclosure with host/port, Upload oldest queued message, busy indicator and plain-language status. Host validation trims whitespace, rejects empty/control/space/oversized values and port0/nondecimal/out-of-range before networking. No persistence of a “delivered” label from custody. Route preference survives launch; networking never auto-starts.

Alternatives rejected: replace direct mode (breaks an existing journey); auto-discovery/auto-forwarding (requires role discovery and introduces lifecycle scope); a phone acting as relay (distinct later role, not needed for this checkpoint). Manual Mac configuration is less polished but is reviewable and reproducible.

## Research and critique

Checked2026-10-08: Apple ScenePhase https://developer.apple.com/documentation/swiftui/scenephase and existing transport implementation. Background means the app may soon terminate; do not infer background delivery. Existing signed protocol/evidence: experiments/rescue-demo/RELAY_NETWORK.md and docs/RESEARCH.md. Inference: explicit controls fit the current simulator demonstration without new discovery dependencies.

Correctness: one adapter/route, no direct fallback, generation check after await. Simplicity: reuse one secure endpoint and shared view. Privacy: show public cards only, retain synthetic-only restriction and existing unencrypted-store warning. Maintainability: no wire changes. Testing: real loopback/service plus durable records, malformed custody and lifecycle interruption, restored preferences and rendered phone/tablet checks. UX: compact disclosure, plain waiting/receipt/ack distinctions and explicit recovery consequence. Delivery remains possible only when a useful later contact occurs.

## Acceptance

Both roles can choose relay, pair, listen, manually upload and receive signed messages; exact retry is stable, pending survives upload/stop/restart, delayed receipt advances device delivery, acknowledgment/reply remain separate. Direct and Training regressions pass. Wrong custody/errors do not imply delivery. Stop/route/role/reset cannot apply an old async result. Native signed build and rendered iPhone/iPad inspection pass; record actual simulator-to-Mac relay evidence separately rather than inferring it from a build. Physical tests, agency trust, encrypted local storage, background guarantees and sales remain open.
