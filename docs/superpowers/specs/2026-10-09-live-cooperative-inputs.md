# Live cooperative research inputs

Approved direction: UW Wi-Fi + opted-in participating phones + sensors + C++ graph. Keep public iPhone/responder iPad. No beacons, arbitrary mesh, UW survey/map or accuracy claim. Testing order home → Bothell → Seattle; user steps in for physical hardware/signing only.

## Architecture

Separate native research workspace and ephemeral CryptoKit identity per role/session, separate `_rescue-floor._tcp` discovery. Reuse LocalExchangeTransport and SecureEnvelope; fresh research keys isolate rescue keys/history. Two manually paired opposite-role participants, full fingerprint comparison. No research persistence or telemetry. Explicit sensor/network starts; stop/background/exit clear remote data and invalidate pending work. One outgoing pull at a time, three-second deadline, no automatic polling or forwarding.

Encrypted authenticated request: domain ORQF1, random 32-byte challenge, manually matched research context (trimmed 1…64 UTF-8 bytes, no control characters). Response ORPF1 echoes exact challenge/context; carries original UUID, optional logical level -20…200, source appleFloor/relativeAltitude/unavailable and sender observation age seconds. Strict Codable wire <=1024 plaintext bytes. Unknown cannot carry a level. Signed pins bind original sender; wrong nonce/context/key/source fails closed. Respond with local original sensor reading only, never peer/graph/manual reported floor.

All local times use systemUptime. Response usable only when measured round trip <=3 s and sender age + full round trip <=10 s. Later age adds receiver elapsed time; pulling cannot refresh the original reading. No raw remote uptime/wall-clock comparison. Transport integrity cannot prove sensor truth or simultaneity. Original provenance is pinned identity + original UUID; no peer-supplied origin IDs. Stop/reset/re-pair generation fences after awaits prevent old results. Context changes require stopped reconfiguration and clear readings.

Connected Wi-Fi: explicit NEHotspotNetwork.fetchCurrent with precise location permission + Access Wi-Fi Information entitlement. Nil/denied/unsupported/timeout means missing evidence. No scans/RSSI workaround. SSID/BSSID remain local memory; never transmitted or written to rescue history. No floor from SSID/BSSID without separately surveyed mapping. Initial graph has local sensor references and a distinct peer reference/contact edge. Contact never creates a relative-level constraint, so a peer alone cannot determine the target floor. Local sensor disagreement is Unknown. Never share graph output as original sensor evidence.

## Stable Swift interface for native UI

Delegate owns ONLY swift/ResearchPeer.swift and SwiftTests/ResearchPeerTests.swift under experiments/workflow-model. Parent owns native adapters, transport constructor, manifests/docs. No overlapping edits.

- public enum ResearchFloorSource: String, Codable, Sendable { appleFloor, relativeAltitude, unavailable }
- public struct ResearchFloorReading: Sendable; public init(level:Int?, source:ResearchFloorSource, sampledAt:Double, id:UUID=UUID()); public fields.
- public struct ResearchPeerObservation: Sendable; public level:Int?, source:ResearchFloorSource, id:UUID, fingerprint:String, receivedAt:Double, ageAtReceipt:Double; public age(at:Double)->Double and isFresh(at:Double)->Bool.
- @MainActor public final class ResearchPeerController: ObservableObject; public init(role:EndpointRole = .publicUser); public let transport:LocalExchangeTransport; published public private(set) card:SecurePairingCard, peerCard:SecurePairingCard?, status:String, busy:Bool, observation:ResearchPeerObservation?.
- public reset(role:EndpointRole); configure(peerBase64:String, context:String, checkedFingerprint:Bool) throws; updateLocalReading(_ reading:ResearchFloorReading?); start(port:UInt16?=nil) throws; stop(); requestObservation(to:NWEndpoint) async.
- Stop clears local/remote reading; configure clears readings to avoid cross-context carryover. Internal clock injection/codec helpers allowed. Parent supplies LocalExchangeTransport(researchTimeout:) with 4276-byte payload and `_rescue-floor._tcp`.

## Acceptance and pre-build critique

Actual socket tests: encrypted paired known/Unknown readings, wrong peer/context/nonce, stale/future/invalid source/level/age/oversized payload, replay/delayed response, stop/reset fencing. Include valid signed semantic substitutions. Native UI: complete fingerprint check, ephemeral identity warning, context, explicit sharing, missing Wi-Fi, age/provenance and graph separation. Full Swift, sanitizer CTest, signed build, Computer Use on existing Location Check without reset. Device signing/entitlement/radio/sensors stay physical gates.

Correctness: RTT-bounded age, not remote uptime. Simplicity: existing crypto/transport and two participants. Privacy: no identifier broadcasts, no persistence. Maintainability: adapters separate, C++ graph unchanged. UX: Unknown, both roles, manual floor preserved. Testing: protocol adversaries, real sockets, lifecycle. Rejected: plaintext broadcasts, SOS identity reuse, same-floor from contact/SSID, automatic starts. Sources checked 2026-10-09: Apple TN3111/TN3151, fetchCurrent, Access Wi-Fi Information entitlement.
