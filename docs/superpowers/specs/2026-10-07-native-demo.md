# Native public/responder demo

Goal: a working portfolio demonstration of one rescue communication product with both interfaces, SwiftUI backed by the existing C++ model. Commercial sales readiness is deferred. User authorized continued development, Claude review and public checkpoint publication. No physical phone is needed for this milestone.

Implement an iPhone/iPad demo with public/responder views sharing a C++ simulation session. That session owns two independent model instances and a bounded in-process delivery queue. Send a synthetic SOS, display device receipt, explicitly acknowledge/reply on the responder side, correct reported location, withdraw, assign/resolve and explicitly reopen. Every outgoing message retains its own delivery status. A simulated disconnected link preserves queued events; reconnect transfers them and returns model receipts. No human acknowledgment is automatic.

Only preset synthetic text/location choices are exposed; the app visibly says simulation/training sample. Session state is in memory, reset explicitly and lost on exit. Native screens and C++ state are real; the link between roles is simulated. This is not the physical networking probe, authenticated membership, endpoint encryption, durable storage, multi-hop routing, sensor localization or AI. No task gate is closed by compiling an experiment.

C++ remains the source of domain rules. A narrow opaque-handle C ABI owns session lifetime, actions and immutable snapshot output. Swift serializes calls on MainActor, decodes read-only snapshots and renders them. Snapshot JSON is an internal display bridge, not a private-message wire protocol. Swift Package Manager compiles the existing workflow.cpp in place; no duplicated C++ business logic or third-party dependency. iOS 18 / macOS 14 remain declared experimental floors.

UI: native adaptive cards, clear status text, public request review and conversation, responder inbox/detail/actions; system typography/colors, large tap targets. Both journeys remain accessible through demo role controls. Use the local first-milestone brief; this is not a claim of pixel-exact Figma implementation. The existing Figma quota limit remains separate.

Definition of done: bridge ownership/bounds/error tests; Swift action/snapshot/outage tests; native simulator build; UI walkthrough of send, explicit acknowledgment/reply, outage correction and reconnect; rendered iPhone and iPad inspection when available; read-only Claude review; evidence and commands recorded. Report missing checks explicitly.
