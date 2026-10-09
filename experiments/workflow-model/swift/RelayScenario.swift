import Foundation
import CryptoKit

public struct RelayScenarioFact: Sendable {
    public let name: String
    public let detail: String
}

public struct RelayScenarioError: Error, CustomStringConvertible {
    public let step: String
    public let message: String
    public var description: String { "\(step): \(message)" }
}

/// Process-local delayed-contact walkthrough: two runtime CryptoKit identities, independent C++ endpoint
/// SQLite files and one relay file. "Contacts" are calls in this process at caller-chosen logical times;
/// nothing here demonstrates radio, sockets, device isolation or multi-hop routing. No Keychain use.
@MainActor public enum RelayScenario {
    public static let factNames = [
        "sealed-sos-queued-idempotently", "relay-holds-only-ciphertext", "custody-survives-reopen",
        "delayed-contact-delivered", "lost-receipt-exact-retry-deduplicated", "modified-ciphertext-rejected",
        "custody-released-origin-still-pending", "delayed-reverse-receipt-device-received",
        "human-acknowledgment-separate", "queues-and-outboxes-empty",
    ]

    /// Lowercase hex SHA-256 of the exact sealed bytes. Stable only while the same ciphertext is retried;
    /// the direct adapter reseals retries, so a future network adapter must persist this mapping.
    public static func sampleID(_ sealed: Data) -> String { hex(Data(SHA256.hash(data: sealed))) }

    /// `root` must be absent or empty; files are left for the caller to delete.
    public static func run(root: URL) throws -> [RelayScenarioFact] {
        let files = FileManager.default
        guard root.isFileURL, root.path.hasPrefix("/") else { throw RelayScenarioError(step: "setup", message: "root must be an absolute folder") }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
        guard try files.contentsOfDirectory(atPath: root.path).isEmpty else {
            throw RelayScenarioError(step: "setup", message: "root must be empty")
        }
        var facts: [RelayScenarioFact] = []
        func check(_ ok: Bool, _ step: String, _ message: String) throws {
            if !ok { throw RelayScenarioError(step: step, message: message) }
        }
        func pass(_ name: String, _ detail: String) { facts.append(RelayScenarioFact(name: name, detail: detail)) }

        let location = "Training Building A · Floor 1"
        let publicIdentity = SecureIdentity(role: .publicUser), responderIdentity = SecureIdentity(role: .responder)
        let publicEnvelope = try SecureEnvelope(identity: publicIdentity, peer: responderIdentity.card)
        let responderEnvelope = try SecureEnvelope(identity: responderIdentity, peer: publicIdentity.card)
        let forward = sampleID(publicIdentity.card.bytes + responderIdentity.card.bytes)
        let reverse = sampleID(responderIdentity.card.bytes + publicIdentity.card.bytes)
        let publicUser = EndpointController(storageURL: root.appendingPathComponent("public.sqlite"), role: .publicUser)
        let responder = EndpointController(storageURL: root.appendingPathComponent("responder.sqlite"), role: .responder)
        try check(publicUser.snapshot != nil && responder.snapshot != nil, "setup", "endpoint stores unavailable")
        let relayURL = root.appendingPathComponent("relay.sqlite")
        var relay: RelayQueue! = try RelayQueue(storageURL: relayURL)
        func reopenRelay() throws { relay = nil; relay = try RelayQueue(storageURL: relayURL) }
        var now: Int64 = 0
        let lifetime: Int64 = 3600
        func requests() -> Int { responder.snapshot?.state.messages.filter { $0.kind == .request }.count ?? -1 }
        func pending(_ endpoint: EndpointController) -> Int { endpoint.snapshot?.pendingTransfers ?? -1 }
        func delivery() -> DemoDelivery? { publicUser.snapshot?.state.originalDelivery }
        /// Queues sealed bytes, waits for a later logical contact and returns the exact retained copy.
        func carry(_ sealed: Data, flow: String, _ step: String) throws -> RelayItem {
            try check(try relay.enqueue(id: sampleID(sealed), flow: flow, priority: .ordinary, expiry: now + lifetime,
                                        hops: 2, payload: sealed, now: now) == .admitted, step, "not admitted")
            try reopenRelay()
            now += 600
            let item = try relay.select(now: now)
            try check(item?.payload == sealed, step, "relay did not return the exact sealed bytes")
            return item!
        }

        try check(publicUser.perform(.sos, value: location), "sos", publicUser.error)
        guard let sos = try publicUser.nextPacket() else { throw RelayScenarioError(step: "sos", message: "no queued SOS") }
        let sealedSOS = try publicEnvelope.seal(sos)
        let sosID = sampleID(sealedSOS)
        let first = try relay.enqueue(id: sosID, flow: forward, priority: .urgent, expiry: now + lifetime, hops: 2, payload: sealedSOS, now: now)
        let repeated = try relay.enqueue(id: sosID, flow: forward, priority: .urgent, expiry: now + lifetime, hops: 2, payload: sealedSOS, now: now + 1)
        try check(first == .admitted && repeated == .duplicate && relay.count() == 1, "sealed-sos-queued-idempotently", "expected one admitted copy")
        pass(factNames[0], "\(sealedSOS.count)-byte sealed SOS admitted once under its SHA-256 ID; identical repeat returned duplicate")

        let stored = try Data(contentsOf: relayURL)
        try check(stored.range(of: sealedSOS) != nil, "relay-holds-only-ciphertext", "sealed envelope not in relay file")
        try check(stored.range(of: Data(location.utf8)) == nil && stored.range(of: sos) == nil, "relay-holds-only-ciphertext", "relay file exposes plaintext")
        try check(responder.snapshot?.state.hasRequest == false && pending(publicUser) == 1 && delivery() == .waiting,
                  "relay-holds-only-ciphertext", "queued custody changed an endpoint")
        pass(factNames[1], "relay file contains the sealed envelope but not the location or inner packet; responder empty; origin waiting")

        try reopenRelay()
        publicUser.reopen()
        responder.reopen()
        try check(relay.count() == 1 && pending(publicUser) == 1 && responder.snapshot?.state.hasRequest == false,
                  "custody-survives-reopen", "state changed across reopen")
        pass(factNames[2], "relay queue and both endpoint stores closed and reopened; custody and origin outbox retained")

        now += 600
        let delayed = try relay.select(now: now)
        try check(delayed?.id == sosID && delayed?.payload == sealedSOS && delayed?.attempts == 1 && delayed?.remainingHops == 1,
                  "delayed-contact-delivered", "unexpected first selection")
        let lostReceipt = try responder.accept(try responderEnvelope.open(delayed!.payload))
        _ = try responderEnvelope.seal(lostReceipt) // sealed receipt is lost before reaching the relay
        try check(requests() == 1, "delayed-contact-delivered", "responder did not commit the SOS")
        pass(factNames[3], "at logical time \(now) the responder decrypted and committed the SOS; its first receipt was dropped")

        now += 60
        guard let retry = try relay.select(now: now) else { throw RelayScenarioError(step: "retry", message: "no retry selected") }
        try check(retry.id == sosID && retry.payload == sealedSOS && retry.attempts == 2, "lost-receipt-exact-retry-deduplicated", "retry was not the stored ciphertext")
        let receipt = try responder.accept(try responderEnvelope.open(retry.payload))
        try check(receipt == lostReceipt && requests() == 1, "lost-receipt-exact-retry-deduplicated", "retry duplicated the request")
        pass(factNames[4], "identical ciphertext retried as attempt 2; responder kept one request and regenerated the same receipt")

        var modified = retry.payload
        modified[modified.startIndex + SecureEnvelope.headerSize] ^= 0x01
        do {
            _ = try responderEnvelope.open(modified)
            throw RelayScenarioError(step: "modified-ciphertext-rejected", message: "modified envelope opened")
        } catch SecureExchangeError.badSignature {}
        try check(requests() == 1, "modified-ciphertext-rejected", "modified envelope changed responder")
        pass(factNames[5], "one flipped relay byte failed the sender signature before decryption")

        try check(try relay.remove(id: sosID) && relay.count() == 0, "custody-released-origin-still-pending", "custody not removed")
        try check(pending(publicUser) == 1 && delivery() == .waiting, "custody-released-origin-still-pending", "relay removal changed the origin")
        pass(factNames[6], "relay deleted its copy after the responder commit; origin outbox still waits for a device receipt")

        let returned = try carry(try responderEnvelope.seal(receipt), flow: reverse, "delayed-reverse-receipt-device-received")
        try publicUser.confirm(try publicEnvelope.open(returned.payload))
        try check(try relay.remove(id: returned.id), "delayed-reverse-receipt-device-received", "receipt custody not removed")
        try check(pending(publicUser) == 0 && delivery() == .deviceReceived, "delayed-reverse-receipt-device-received", "origin not device-received")
        pass(factNames[7], "encrypted receipt queued, reopened and delivered at time \(now); origin is deviceReceived, not humanAcknowledged")

        try check(responder.perform(.acknowledge), "human-acknowledgment-separate", responder.error)
        guard let ack = try responder.nextPacket() else { throw RelayScenarioError(step: "ack", message: "no queued acknowledgment") }
        let carriedAck = try carry(try responderEnvelope.seal(ack), flow: reverse, "human-acknowledgment-separate")
        let ackReceipt = try publicUser.accept(try publicEnvelope.open(carriedAck.payload))
        try check(try relay.remove(id: carriedAck.id) && delivery() == .humanAcknowledged && pending(responder) == 1,
                  "human-acknowledgment-separate", "acknowledgment not recorded separately")
        let carriedReceipt = try carry(try publicEnvelope.seal(ackReceipt), flow: forward, "human-acknowledgment-separate")
        try responder.confirm(try responderEnvelope.open(carriedReceipt.payload))
        try check(try relay.remove(id: carriedReceipt.id), "human-acknowledgment-separate", "ack receipt custody not removed")
        pass(factNames[8], "responder acknowledgment and its reverse receipt each relayed separately; origin humanAcknowledged")

        try check(relay.count() == 0 && relay.select(now: now) == nil && pending(publicUser) == 0 && pending(responder) == 0,
                  "queues-and-outboxes-empty", "custody or outbox left behind")
        pass(factNames[9], "relay queue and both endpoint outboxes empty at logical time \(now)")
        return facts
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
