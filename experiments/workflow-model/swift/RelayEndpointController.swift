import Foundation
import CryptoKit

/// Relay-mode adapter for one paired secure endpoint. Outgoing events and returned device receipts are sealed
/// and signed once, then kept as ORF1 records (exact ORL1 bytes bound by this endpoint's signature to their
/// mapping ID) in an append-only C++ cache at `secure-{role}/{epoch}.relay-cache.sqlite` (ciphertext and hashes
/// only; no keys or plaintext). Retries and restarts reuse those bytes, so the relay ID stays stable. Expired
/// mappings fail closed and are never replaced; a new secure session is the explicit recovery.
///
/// A public guard file `{epoch}.relay-cache.guard` (ORG1: magic4, own card SHA256 32, peer card SHA256 32) is
/// written before the cache is first created. A guard without a nonempty cache, or a cache without the matching
/// guard, fails closed and is never repaired, so losing the cache cannot reseal a pending message under a new ID.
/// Deleting both files together, or any change by another process running as the same user, is outside this
/// local sample's guarantee. No direct-send path exists here.
@MainActor public final class RelayEndpointController {
    typealias Context = (identity: SecureIdentity, peer: SecurePairingCard, envelope: SecureEnvelope)
    public let secure: SecureEndpointController
    private let clock: () -> Int64
    private var cache: RelayQueue?
    private static let guardMagic = Data("ORG1".utf8)

    /// `clock` returns wall-clock seconds by default; it is not a trusted time source.
    public init(secure: SecureEndpointController, clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) {
        self.secure = secure
        self.clock = clock
    }

    /// Cache file for the endpoint's current epoch.
    var cacheURL: URL {
        secure.endpoint.storageURL.deletingPathExtension().appendingPathExtension("relay-cache.sqlite")
    }

    var cacheGuardURL: URL {
        secure.endpoint.storageURL.deletingPathExtension().appendingPathExtension("relay-cache.guard")
    }

    /// Saved cache rows; requires pairing and creates no cache before it.
    public func cacheCount() throws -> Int { try openCache(secure.relayContext()).count() }

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
        _ = try openCache(context) // fail closed on a lost cache before committing anything
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
    /// A saved memo bypasses the pending-head check only when it binds exactly this packet.
    private func recordReceipt(_ packet: RelayPacket, raw: Data, context: Context, now: Int64) throws {
        let cache = try openCache(context)
        let own = context.identity.card
        let memoID = Self.receiptMemoID(own: own, peer: context.peer, raw: raw, correlation: packet.correlation)
        let flow = Self.hex(Data(SHA256.hash(data: raw)))
        if let memo = try cache.lookup(id: memoID) {
            let saved = try Self.validated(memo, mapping: memoID, flow: flow, kind: .receipt, correlation: packet.correlation,
                                           from: context.peer, to: own, owner: own)
            guard saved == packet else { throw RelayProtocolError.cacheMismatch }
            return
        }
        guard let head = try secure.endpoint.nextPacket() else { throw RelayProtocolError.correlation }
        let sentID = Self.cacheID(kind: .event, own: own, peer: context.peer, raw: head, correlation: Data(count: 32))
        guard let sentItem = try cache.lookup(id: sentID) else { throw RelayProtocolError.correlation }
        // The saved event may have expired since delivery; its receipt still answers it.
        let sent = try Self.validated(sentItem, mapping: sentID, flow: Self.hex(Data(SHA256.hash(data: head))), kind: .event,
                                      correlation: Data(count: 32), from: own, to: context.peer, owner: own, raw: head)
        guard Data(SHA256.hash(data: sent.bytes)) == packet.correlation else { throw RelayProtocolError.correlation }
        _ = try cache.cacheAdmit(id: memoID, flow: flow, priority: .ordinary, expiry: packet.expiry, hops: Int(RelayPacket.hops),
                                 payload: RelayCacheRecord.seal(packet, mapping: memoID, identity: context.identity), now: now)
    }

    /// Cached exact packet for this raw message, or a new one sealed, signed and durably cached before return.
    private func packet(_ kind: RelayKind, raw: Data, correlation: Data, priority: RelayPriority, context: Context,
                        now: Int64) throws -> RelayPacket {
        guard raw.count <= RelayPacket.maximumEventPlaintext else { throw RelayProtocolError.plaintextSize }
        let cache = try openCache(context)
        let id = Self.cacheID(kind: kind, own: context.identity.card, peer: context.peer, raw: raw, correlation: correlation)
        let flow = Self.hex(Data(SHA256.hash(data: raw)))
        if let hit = try cache.lookup(id: id) {
            guard hit.expiry > now else { throw RelayProtocolError.cacheExpired }
            let cached = try Self.validated(hit, mapping: id, flow: flow, kind: kind, correlation: correlation,
                                            from: context.identity.card, to: context.peer, owner: context.identity.card, raw: raw)
            guard (try? cached.verify(from: context.identity.card, to: context.peer, now: now)) != nil else {
                throw RelayProtocolError.cacheMismatch
            }
            return cached
        }
        let (expiry, overflow) = now.addingReportingOverflow(RelayPacket.maximumLifetime)
        guard !overflow else { throw RelayProtocolError.expiryTooFar }
        let created = try RelayPacket.make(kind: kind, priority: priority, expiry: expiry, correlation: correlation,
                                           sealed: try context.envelope.seal(raw), identity: context.identity, recipient: context.peer)
        // The lookup above missed on this serialized handle, so an admission duplicate means a concurrent owner.
        guard try cache.cacheAdmit(id: id, flow: flow, priority: priority, expiry: expiry, hops: Int(RelayPacket.hops),
                                   payload: RelayCacheRecord.seal(created, mapping: id, identity: context.identity),
                                   now: now) == .admitted else { throw RelayProtocolError.cacheMismatch }
        return created
    }

    /// Opens an ORF1 row signed by `owner` for exactly `mapping`, then checks the bound ORL1 against the row's
    /// unsigned metadata and the expected direction, kind, correlation and (when `raw` is known) sealed length.
    private static func validated(_ item: RelayItem, mapping: String, flow: String, kind: RelayKind, correlation: Data,
                                  from: SecurePairingCard, to: SecurePairingCard, owner: SecurePairingCard,
                                  raw: Data? = nil) throws -> RelayPacket {
        guard item.id == mapping, item.flow == flow, item.attempts == 0, item.remainingHops == Int(RelayPacket.hops) - 1,
              let packet = try? RelayCacheRecord.open(item.payload, mapping: mapping, owner: owner),
              (try? packet.authenticate(from: from, to: to)) != nil,
              packet.kind == kind, packet.correlation == correlation,
              item.priority == packet.priority, item.expiry == packet.expiry,
              raw.map({ packet.sealed.count == $0.count + SecureEnvelope.minimumPayload - 1 }) ?? true
        else { throw RelayProtocolError.cacheMismatch }
        return packet
    }

    /// Opens this epoch's cache only beside its matching guard; see the type comment. Checked on every use,
    /// including a retained handle, so a deleted cache is never recreated or written while detached.
    private func openCache(_ context: Context) throws -> RelayQueue {
        let url = cacheURL, guardURL = cacheGuardURL
        let expected = Self.guardMagic + context.identity.card.digest + context.peer.digest
        let files = FileManager.default
        let saved: Data?
        do {
            if files.fileExists(atPath: guardURL.path) {
                let attributes = try files.attributesOfItem(atPath: guardURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular,
                      attributes[.size] as? Int == expected.count else { throw RelayProtocolError.cacheGuard }
                let handle = try FileHandle(forReadingFrom: guardURL)
                defer { try? handle.close() }
                // Bound the read even if the file changes after its attributes were checked.
                saved = try handle.read(upToCount: expected.count + 1)
            } else { saved = nil }
        }
        catch { throw RelayProtocolError.cacheGuard }
        let size = (try? files.attributesOfItem(atPath: url.path))?[.size] as? Int
        if let cache, cache.storageURL == url {
            guard saved == expected, (size ?? 0) > 0 else {
                self.cache = nil
                throw RelayProtocolError.cacheGuard
            }
            return cache
        }
        cache = nil
        if saved == nil, size == nil, !files.fileExists(atPath: url.path) {
            do { try expected.write(to: guardURL, options: .withoutOverwriting) }
            catch { throw RelayProtocolError.cacheGuard }
        } else {
            guard saved == expected, (size ?? 0) > 0 else { throw RelayProtocolError.cacheGuard }
        }
        let opened = try RelayQueue(storageURL: url)
        cache = opened
        return opened
    }

    nonisolated static func cacheID(kind: RelayKind, own: SecurePairingCard, peer: SecurePairingCard, raw: Data, correlation: Data) -> String {
        mapping("offline-rescue/ORL1/cache", kind: kind, own: own, peer: peer, raw: raw, correlation: correlation)
    }

    nonisolated static func receiptMemoID(own: SecurePairingCard, peer: SecurePairingCard, raw: Data, correlation: Data) -> String {
        mapping("offline-rescue/ORL1/received-receipt", kind: .receipt, own: own, peer: peer, raw: raw, correlation: correlation)
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
