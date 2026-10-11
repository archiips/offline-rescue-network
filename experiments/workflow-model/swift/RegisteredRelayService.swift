import Foundation
import CryptoKit

/// Bounded opaque custody for issuer-authorized participants. Public route metadata is only a hint;
/// every stored wrapper is reauthenticated before forwarding and again after asynchronous delivery.
@MainActor public final class RegisteredRelayService {
    public let storageURL: URL
    public var destinations: [SecurePairingCard] {
        var seen = Set<Data>()
        return routes.compactMap { route in
            guard let card = try? SecurePairingCard(bytes: route.recipient), seen.insert(card.bytes).inserted else { return nil }
            return card
        }
    }
    private struct Route: Codable, Equatable {
        let sender, recipient: Data
        var flow: String { RelayEndpointController.hex(Data(SHA256.hash(data: Data(SHA256.hash(data: sender)) + Data(SHA256.hash(data: recipient)))) ) }
    }
    private struct Metadata: Codable { let version: Int; let routes: [Route] }
    private let queue: RelayQueue
    private let trust: EnrollmentTrust
    private let now: () -> Int64
    private var routes: [Route]
    private var savedMetadata: Data
    private var flushing = false
    private var metadataURL: URL { storageURL.appendingPathExtension("routes.json") }
    private static let maximumMetadata = 65536

    public init(storageURL: URL, trust: EnrollmentTrust, now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970) }) throws {
        guard storageURL.isFileURL, !storageURL.hasDirectoryPath else { throw RelayProtocolError.cacheGuard }
        self.storageURL = storageURL; self.trust = trust; self.now = now
        let metadataURL = storageURL.appendingPathExtension("routes.json")
        let files = FileManager.default
        let hasMetadata = files.fileExists(atPath: metadataURL.path), hasQueue = files.fileExists(atPath: storageURL.path)
        let bytes: Data
        if hasMetadata || hasQueue {
            guard hasMetadata && hasQueue else { throw RelayProtocolError.cacheGuard }
            bytes = try Self.readMetadata(metadataURL)
            try Self.requireQueue(storageURL)
        } else {
            // Public sidecar comes first. Interrupted creation leaves an orphan that is never silently repaired.
            try files.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            bytes = try Self.encode([])
            try bytes.write(to: metadataURL, options: .withoutOverwriting)
        }
        let metadata = try JSONDecoder().decode(Metadata.self, from: bytes)
        guard metadata.version == 1, metadata.routes.count <= 32, try Self.encode(metadata.routes) == bytes else { throw RelayProtocolError.cacheGuard }
        var seen = Set<String>()
        for route in metadata.routes {
            let sender = try SecurePairingCard(bytes: route.sender), recipient = try SecurePairingCard(bytes: route.recipient)
            guard sender.role != recipient.role, seen.insert(route.flow).inserted,
                  metadata.routes.contains(Route(sender: route.recipient, recipient: route.sender)) else { throw RelayProtocolError.cacheGuard }
        }
        self.routes = metadata.routes; self.savedMetadata = bytes
        queue = try RelayQueue(storageURL: storageURL)
        try Self.requireQueue(storageURL)
    }
    private static func encode(_ routes: [Route]) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let bytes = try encoder.encode(Metadata(version: 1, routes: routes))
        guard bytes.count <= maximumMetadata else { throw RelayProtocolError.cacheGuard }
        return bytes
    }
    private static func readMetadata(_ url: URL) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, (1...maximumMetadata).contains(size) else { throw RelayProtocolError.cacheGuard }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        guard let bytes = try file.read(upToCount: maximumMetadata + 1), bytes.count <= maximumMetadata else { throw RelayProtocolError.cacheGuard }
        return bytes
    }
    private static func requireQueue(_ url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? Int, size > 0 else { throw RelayProtocolError.cacheGuard }
    }
    private func validate() throws {
        guard try Self.readMetadata(metadataURL) == savedMetadata else { throw RelayProtocolError.cacheGuard }
        try Self.requireQueue(storageURL)
    }
    public func count() throws -> Int { try validate(); return try queue.count() }

    /// Route metadata is durable before opaque custody; abandoned metadata grants no authorization.
    public func admit(_ bytes: Data) throws -> Data {
        try validate()
        let wrapper = try RegisteredRelayPacket(bytes: bytes)
        let cards = try wrapper.authenticate(trust: trust, now: now())
        let forward = Route(sender: cards.sender.bytes, recipient: cards.recipient.bytes)
        if !routes.contains(forward) {
            guard routes.count <= 30 else { throw RelayError(code: .capacity, message: "Registered relay supports at most 16 prepared pairs") }
            let next = routes + [forward, Route(sender: forward.recipient, recipient: forward.sender)]
            let metadata = try Self.encode(next)
            try metadata.write(to: metadataURL, options: .atomic)
            routes = next; savedMetadata = metadata
        }
        let packet = wrapper.packet
        _ = try queue.enqueue(id: packet.id, flow: RelayService.flow(for: packet), priority: packet.priority,
                              expiry: packet.expiry, hops: Int(RelayPacket.hops), payload: wrapper.bytes, now: now())
        return RelayCustodyReceipt.make(packet)
    }
    public func flush(eligibleDestinations: Set<Data>, send: (Data, SecurePairingCard) async throws -> Data) async throws -> RelayFlushOutcome {
        guard !flushing else { throw RelayProtocolError.busy }
        try validate()
        flushing = true; defer { flushing = false }
        let flows = routes.filter { eligibleDestinations.contains(Data(SHA256.hash(data: $0.recipient))) }.map(\.flow)
        guard let item = try queue.select(now: now(), eligibleFlows: flows) else { return .empty }
        do {
            let wrapper = try RegisteredRelayPacket(bytes: item.payload), packet = wrapper.packet
            let cards = try wrapper.authenticate(trust: trust, now: now())
            guard item.id == packet.id, item.flow == RelayService.flow(for: packet), item.priority == packet.priority,
                  item.expiry == packet.expiry, item.remainingHops == Int(RelayPacket.hops) - 1,
                  routes.contains(Route(sender: cards.sender.bytes, recipient: cards.recipient.bytes)) else { throw RelayProtocolError.custodyMismatch }
            let response = try await send(wrapper.bytes, cards.recipient)
            try validate()
            _ = try wrapper.authenticate(trust: trust, now: now())
            guard try queue.lookup(id: item.id) == item else { throw RelayProtocolError.wrongPacket }
            let returned = try RelayAcceptance(bytes: response).verify(original: packet, destination: cards.recipient, origin: cards.sender, now: now())
            if let returned {
                let reverse = try RegisteredRelayPacket(senderCredential: wrapper.recipientCredential,
                    recipientCredential: wrapper.senderCredential, packet: returned)
                _ = try admit(reverse.bytes)
            }
            _ = try queue.remove(id: item.id)
            return .delivered(id: item.id, attempts: item.attempts, returned: returned?.id)
        } catch { return .failed(id: item.id, attempts: item.attempts, reason: String(describing: error)) }
    }
}
