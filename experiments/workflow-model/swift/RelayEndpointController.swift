import Foundation
import CryptoKit

/// Relay-mode adapter for one paired secure endpoint. Outgoing events and returned device receipts are sealed
/// and signed once, then kept as exact ORL1 bytes in an append-only C++ cache at
/// `secure-{role}/{epoch}.relay-cache.sqlite` (ciphertext and hashes only; no keys or plaintext). Retries and
/// restarts reuse those bytes, so the relay ID stays stable. Expired mappings fail closed and are never
/// replaced; a new secure session is the explicit recovery. No direct-send path exists here.
@MainActor public final class RelayEndpointController {
    typealias Context = (identity: SecureIdentity, peer: SecurePairingCard, envelope: SecureEnvelope)
    public let secure: SecureEndpointController
    private let clock: () -> Int64
    private var cache: RelayQueue?

    /// `clock` returns wall-clock seconds by default; it is not a trusted time source.
    public init(secure: SecureEndpointController, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
        self.secure = secure
        self.clock = clock
    }

    /// Cache file for the endpoint's current epoch.
    var cacheURL: URL {
        secure.endpoint.storageURL.deletingPathExtension().appendingPathExtension("relay-cache.sqlite")
    }

    public func cacheCount() throws -> Int { try openCache().count() }

    /// Signed ORL1 for the oldest pending event, or nil when nothing is pending. Does not change the outbox;
    /// only a validated reverse receipt does. Default priority: public events urgent, responder events ordinary.
    public func outgoing(priority: RelayPriority? = nil) throws -> RelayPacket? {
        let context = try secure.relayContext()
        guard let raw = try secure.endpoint.nextPacket() else { return nil }
        return try packet(.event, raw: raw, correlation: Data(count: 32),
                          priority: priority ?? (secure.role == .publicUser ? .urgent : .ordinary), context: context, now: clock())
    }

    /// Handles one ORL1 delivered by the relay and returns the signed ORA1 acceptance. Events commit in C++
    /// and then return their cached device receipt; receipts must correlate with this endpoint's saved event
    /// packet before C++ confirms them. Any throw means no acceptance, so the relay keeps custody.
    public func receive(_ bytes: Data) throws -> Data {
        let context = try secure.relayContext()
        let now = clock()
        let packet = try RelayPacket(bytes: bytes)
        try packet.verify(from: context.peer, to: context.identity.card, now: now)
        let raw = try context.envelope.open(packet.sealed)
        switch packet.kind {
        case .event:
            let receipt = try secure.endpoint.accept(raw)
            let returned = try self.packet(.receipt, raw: receipt, correlation: packet.digest, priority: .ordinary, context: context, now: now)
            return try RelayAcceptance.make(original: packet, identity: context.identity, returning: returned).bytes
        case .receipt:
            try recordReceipt(packet, raw: raw, context: context, now: now)
            try secure.endpoint.confirm(raw)
            return try RelayAcceptance.make(original: packet, identity: context.identity, returning: nil).bytes
        }
    }

    /// Records the receipt's correlation before confirming, so a retry after confirmation (pending removed)
    /// still proves it answers this endpoint's own saved packet; C++ history then makes confirmation idempotent.
    private func recordReceipt(_ packet: RelayPacket, raw: Data, context: Context, now: Int64) throws {
        let cache = try openCache()
        let record = Self.mapping("offline-rescue/ORL1/received-receipt", kind: .receipt, own: context.identity.card,
                                  peer: context.peer, raw: raw, correlation: packet.correlation)
        if try cache.lookup(id: record) != nil { return }
        guard let head = try secure.endpoint.nextPacket(),
              let sent = try cache.lookup(id: Self.cacheID(kind: .event, own: context.identity.card, peer: context.peer,
                                                           raw: head, correlation: Data(count: 32))),
              Data(SHA256.hash(data: sent.payload)) == packet.correlation else { throw RelayProtocolError.correlation }
        _ = try cache.cacheAdmit(id: record, flow: Self.hex(Data(SHA256.hash(data: raw))), priority: .ordinary,
                                 expiry: packet.expiry, hops: Int(RelayPacket.hops), payload: packet.bytes, now: now)
    }

    /// Cached exact packet for this raw message, or a new one sealed, signed and durably cached before return.
    private func packet(_ kind: RelayKind, raw: Data, correlation: Data, priority: RelayPriority, context: Context,
                        now: Int64) throws -> RelayPacket {
        guard raw.count <= RelayPacket.maximumEventPlaintext else { throw RelayProtocolError.plaintextSize }
        let cache = try openCache()
        let id = Self.cacheID(kind: kind, own: context.identity.card, peer: context.peer, raw: raw, correlation: correlation)
        let flow = Self.hex(Data(SHA256.hash(data: raw)))
        if let hit = try cache.lookup(id: id) {
            guard hit.expiry > now else { throw RelayProtocolError.cacheExpired }
            guard let cached = try? RelayPacket(bytes: hit.payload),
                  (try? cached.verify(from: context.identity.card, to: context.peer, now: now)) != nil,
                  cached.kind == kind, cached.correlation == correlation, hit.flow == flow,
                  hit.priority == cached.priority, hit.expiry == cached.expiry, hit.remainingHops == Int(RelayPacket.hops) - 1,
                  cached.sealed.count == raw.count + SecureEnvelope.minimumPayload - 1
            else { throw RelayProtocolError.cacheMismatch }
            return cached
        }
        let (expiry, overflow) = now.addingReportingOverflow(RelayPacket.maximumLifetime)
        guard !overflow else { throw RelayProtocolError.expiryTooFar }
        let created = try RelayPacket.make(kind: kind, priority: priority, expiry: expiry, correlation: correlation,
                                           sealed: try context.envelope.seal(raw), identity: context.identity, recipient: context.peer)
        // The lookup above missed on this serialized handle, so an admission duplicate means a concurrent owner.
        guard try cache.cacheAdmit(id: id, flow: flow, priority: priority, expiry: expiry, hops: Int(RelayPacket.hops),
                                   payload: created.bytes, now: now) == .admitted else { throw RelayProtocolError.cacheMismatch }
        return created
    }

    private func openCache() throws -> RelayQueue {
        let url = cacheURL
        if let cache, cache.storageURL == url { return cache }
        cache = nil
        let opened = try RelayQueue(storageURL: url)
        cache = opened
        return opened
    }

    nonisolated static func cacheID(kind: RelayKind, own: SecurePairingCard, peer: SecurePairingCard, raw: Data, correlation: Data) -> String {
        mapping("offline-rescue/ORL1/cache", kind: kind, own: own, peer: peer, raw: raw, correlation: correlation)
    }

    private nonisolated static func mapping(_ domain: String, kind: RelayKind, own: SecurePairingCard, peer: SecurePairingCard,
                                raw: Data, correlation: Data) -> String {
        var hash = SHA256()
        hash.update(data: Data(domain.utf8) + Data([0, kind.rawValue]))
        hash.update(data: own.bytes + peer.bytes)
        let count = UInt32(raw.count)
        hash.update(data: Data([UInt8(count >> 24), UInt8(count >> 16 & 0xff), UInt8(count >> 8 & 0xff), UInt8(count & 0xff)]))
        hash.update(data: raw + correlation)
        return hex(Data(hash.finalize()))
    }

    nonisolated static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
