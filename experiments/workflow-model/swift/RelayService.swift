import Foundation
import CryptoKit

public enum RelayFlushOutcome: Equatable, Sendable {
    case empty
    /// Destination acceptance validated; `returned` is the admitted reverse receipt ID for events.
    case delivered(id: String, attempts: Int, returned: String?)
    /// Diagnostic only: the response was deliberately ignored, so custody and the attempt remain.
    case dropped(id: String, attempts: Int)
    /// Custody retained for a later attempt.
    case failed(id: String, attempts: Int, reason: String)
}

/// One sample relay: custody of verified ORL1 packets between exactly two pinned opposite-role public cards.
/// Holds no endpoint keys or plaintext and never touches endpoint stores. Upload admission is a bounded
/// synchronous call; `flush` forwards one global head and deletes it only after a signed destination acceptance,
/// admitting any reverse receipt first. One flush runs at a time.
@MainActor public final class RelayService {
    public let storageURL: URL
    private let queue: RelayQueue
    private let cards: [SecurePairingCard]
    private let clock: () -> Int64
    private var flushing = false

    public init(storageURL: URL, publicCard: SecurePairingCard, responderCard: SecurePairingCard,
                clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) throws {
        guard publicCard.role == .publicUser, responderCard.role == .responder else { throw RelayProtocolError.unknownPeer }
        queue = try RelayQueue(storageURL: storageURL)
        self.storageURL = storageURL
        cards = [publicCard, responderCard]
        self.clock = clock
    }

    public func count() throws -> Int { try queue.count() }

    /// Verifies and durably admits one uploaded ORL1, returning ORC1. Identical repeats return the same ORC1.
    public func admit(_ bytes: Data) throws -> Data {
        let packet = try RelayPacket(bytes: bytes)
        let (from, to) = try route(packet)
        try packet.verify(from: from, to: to, now: clock())
        try custody(packet)
        return RelayCustodyReceipt.make(packet)
    }

    /// Selects one item (committing its attempt), sends it to its pinned destination and validates the reply
    /// again after the await. `dropResponse` is a diagnostic that ignores a received reply.
    public func flush(dropResponse: Bool = false,
                      send: (Data, EndpointRole) async throws -> Data) async throws -> RelayFlushOutcome {
        guard !flushing else { throw RelayProtocolError.busy }
        flushing = true
        defer { flushing = false }
        guard let item = try queue.select(now: clock()) else { return .empty }
        do {
            let packet = try RelayPacket(bytes: item.payload)
            let (from, to) = try route(packet)
            try packet.verify(from: from, to: to, now: clock())
            let response = try await send(item.payload, to.role)
            if dropResponse { return .dropped(id: item.id, attempts: item.attempts) }
            // Uploads may have run during the await; custody must still hold these exact bytes.
            guard try queue.lookup(id: item.id)?.payload == item.payload else { throw RelayProtocolError.wrongPacket }
            let returned = try RelayAcceptance(bytes: response).verify(original: packet, destination: to, origin: from, now: clock())
            // Reverse receipt first: a crash before removal only retries the original, which the destination
            // answers idempotently with the same cached receipt.
            if let returned { try custody(returned) }
            _ = try queue.remove(id: item.id)
            return .delivered(id: item.id, attempts: item.attempts, returned: returned?.id)
        } catch {
            return .failed(id: item.id, attempts: item.attempts, reason: String(describing: error))
        }
    }

    private func custody(_ packet: RelayPacket) throws {
        let flow = RelayEndpointController.hex(Data(SHA256.hash(data: packet.sender + packet.recipient)))
        _ = try queue.enqueue(id: packet.id, flow: flow, priority: packet.priority, expiry: packet.expiry,
                              hops: Int(RelayPacket.hops), payload: packet.bytes, now: clock())
    }

    private func route(_ packet: RelayPacket) throws -> (from: SecurePairingCard, to: SecurePairingCard) {
        guard let from = cards.first(where: { $0.digest == packet.sender }),
              let to = cards.first(where: { $0.digest == packet.recipient }), from != to else { throw RelayProtocolError.unknownPeer }
        return (from, to)
    }
}
