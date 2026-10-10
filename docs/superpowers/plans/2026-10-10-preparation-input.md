# Accessible preparation input follow-up

Outcome: complete the native synthetic registration walkthrough despite an inaccessible system Files picker, without changing emergency-time onboarding or trusting arbitrary profiles.

Scope: retain file import/export; add collapsed preparation-only public-request display and bounded issued-profile text entry. Both routes share the existing canonical <=4096-byte decoder and signature/card/role/time validation. Staging never persists trust. Explicit organizer approval remains required. No new dependencies, automatic account enrollment, emergency pairing, real-authority or physical-network claims.

Alternatives: repeated Files retries failed with `noWindowsAvailable`; native security controls or direct trust-store writes are not bypasses to use. Chosen alternate is ordinary visible native preparation UI using the existing validator. Raw public requests/profiles stay outside Git. Preserve original public/responder and saved histories, including user-local Xcode signing changes.

Critique: keyboard substitutions can corrupt signed JSON, so native input disables smart punctuation/correction and keeps editing ownership of its buffer. Character cap is a UI limit; byte/canonical/signature validation is still authoritative. Role changes clear stale profile text. Trust is a distinct final action; an approved local registrar Keychain prompt is not approval of a new app trust anchor.

- [x] Shared staging path and preparation controls implemented; independently reviewed.
- [x] Native malformed rejection and valid signed profile staging to unchecked issuer gate observed through Computer Use. No completed enrollment inferred.
- [x] Full Swift checks:192 Swift Testing +6 XCTest pass, including exact canonical text, quote substitution/trailing newline/oversize rejection and retained socket recovery/fences.
- [x] Final signed Simulator build succeeds; final installed build preserves exact quote/order, rejects incomplete input and stages the valid profile with approval off.
- [x] Explicit action-time approval and native registration/inbox walkthrough (empty inbox, stop, saved registration and automatic discovery after relaunch on iPhone Simulator); remaining two-audience round trip and physical gates recorded separately.
- [x] Final staged privacy/diff review and scoped publication: `99e2863` pushed to authorized origin/main; personal Xcode signing changes excluded.

Evidence: TextEditor smart punctuation and rapid editing exposed corruption during actual native entry; bounded UITextView now disables substitutions. Native exact profile was entered via Computer Use and accepted to matching local issuer fingerprint, verification toggle off. User confirmation requested at that step, as required by Computer Use security rules. Never approve macOS SecurityAgent using alternate tools; user handled that earlier prompt directly.
