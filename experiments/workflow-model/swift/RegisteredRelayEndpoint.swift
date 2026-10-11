import Foundation
import CryptoKit

/// One credential-authorized conversation. Exact wrappers survive retries; custody never confirms C++ work.
@MainActor final class RegisteredRelayEndpoint {
    private let adapter: RelayEndpointController
    private let own: Data
    private let peer: Data
    private let trust: EnrollmentTrust
    private let now: () -> Int64
    private let validate: () throws -> Void
    private let url: URL
    private var cache: RelayQueue?
    init(adapter: RelayEndpointController, own: Data, peer: Data, trust: EnrollmentTrust,
         storageURL: URL, now: @escaping () -> Int64, validate: @escaping () throws -> Void) {
        self.adapter = adapter; self.own = own; self.peer = peer; self.trust = trust
        url = storageURL.deletingPathExtension().appendingPathExtension("registered-relay.sqlite")
        self.now = now; self.validate = validate
    }
    private func cards() throws -> (SecurePairingCard, SecurePairingCard) {
        try validate()
        let a = try EnrollmentCredential.decode(own).card, b = try EnrollmentCredential.decode(peer).card
        guard a.role != b.role else { throw EnrollmentError.wrongRole }
        _ = try trust.verify(own, expectedRole: a.role, at: now())
        _ = try trust.verify(peer, expectedRole: b.role, at: now())
        return (a, b)
    }
    private func open() throws -> RelayQueue {
        let (a, b) = try cards()
        let guardURL = url.appendingPathExtension("guard")
        let expected = Data("ORWG1".utf8) + Data(SHA256.hash(data: a.bytes)) + Data(SHA256.hash(data: b.bytes))
        let fm = FileManager.default
        let hasGuard = fm.fileExists(atPath: guardURL.path), hasQueue = fm.fileExists(atPath: url.path)
        if hasGuard || hasQueue {
            guard hasGuard && hasQueue else { throw RelayProtocolError.cacheGuard }
            for file in [guardURL, url] {
                let attrs = try fm.attributesOfItem(atPath: file.path)
                guard attrs[.type] as? FileAttributeType == .typeRegular,
                      (attrs[.size] as? Int ?? 0) > 0 else { throw RelayProtocolError.cacheGuard }
            }
            let handle = try FileHandle(forReadingFrom: guardURL); defer { try? handle.close() }
            guard try handle.read(upToCount: expected.count + 1) == expected else { throw RelayProtocolError.cacheGuard }
        } else {
            guard cache == nil else { throw RelayProtocolError.cacheGuard }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try expected.write(to: guardURL, options: .withoutOverwriting)
        }
        if let cache { return cache }
        let opened = try RelayQueue(storageURL: url); cache = opened
        return opened
    }
    func outgoing() throws -> RegisteredRelayPacket? {
        _ = try cards()
        guard let packet = try adapter.outgoing() else { return nil }
        let queue = try open()
        if let row = try queue.lookup(id: packet.id) {
            guard row.payload.count > 64 else { throw RelayProtocolError.cacheMismatch }
            let raw = Data(row.payload.dropLast(64))
            let (owner, _) = try cards()
            guard owner.signingKey.isValidSignature(Data(row.payload.suffix(64)), for: raw), row.attempts == 0 else { throw RelayProtocolError.cacheMismatch }
            let saved = try RegisteredRelayPacket(bytes: raw)
            let (a, b) = try cards(), verified = try saved.authenticate(trust: trust, now: now())
            guard verified.sender == a, verified.recipient == b, saved.packet.bytes == packet.bytes,
                  row.flow == RelayService.flow(for: packet), row.expiry == packet.expiry,
                  row.priority == packet.priority, row.remainingHops == Int(RelayPacket.hops) - 1 else { throw RelayProtocolError.cacheMismatch }
            return saved
        }
        let wrapper = try RegisteredRelayPacket(senderCredential: own, recipientCredential: peer, packet: packet)
        _ = try wrapper.authenticate(trust: trust, now: now())
        let identity = try adapter.secure.enrollmentIdentity()
        let record = wrapper.bytes + (try identity.signingKey.signature(for: wrapper.bytes))
        guard record.count <= RegisteredRelayPacket.maximumSize else { throw RelayProtocolError.plaintextSize }
        guard try queue.cacheAdmit(id: packet.id, flow: RelayService.flow(for: packet), priority: packet.priority,
            expiry: packet.expiry, hops: Int(RelayPacket.hops), payload: record, now: now()) == .admitted else {
            throw RelayProtocolError.cacheMismatch
        }
        return wrapper
    }
    func receive(_ bytes: Data) throws -> Data {
        let (a, b) = try cards(), wrapper = try RegisteredRelayPacket(bytes: bytes)
        let verified = try wrapper.authenticate(trust: trust, now: now())
        guard verified.sender == b, verified.recipient == a else { throw EnrollmentError.wrongIdentity }
        return try adapter.receive(wrapper.packet.bytes)
    }
}
