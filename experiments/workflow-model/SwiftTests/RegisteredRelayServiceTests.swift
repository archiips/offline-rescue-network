import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@MainActor private struct RegisteredCustodyFixture {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let publicIdentity = SecureIdentity(role: .publicUser), responder = SecureIdentity(role: .responder)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var url: URL { folder.appendingPathComponent("custody.sqlite") }
    func credential(_ identity: SecureIdentity) throws -> EnrollmentCredential {
        try .issue(card: identity.card, realm: realm, notBefore: 100, expires: 300, issuer: issuer)
    }
    func trust(revoked: Set<UUID> = []) throws -> EnrollmentTrust {
        try .init(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300, revoked: revoked)
    }
    func wrapper(sender: SecureIdentity? = nil) throws -> RegisteredRelayPacket {
        let publicIdentity = sender ?? self.publicIdentity
        let inner = try RelayPacket.make(kind: .event, priority: .urgent, expiry: 250, correlation: Data(count: 32),
            sealed: SecureEnvelope(identity: publicIdentity, peer: responder.card).seal(Data([1])), identity: publicIdentity, recipient: responder.card)
        return try .init(senderCredential: credential(publicIdentity).bytes, recipientCredential: credential(responder).bytes, packet: inner)
    }
    func acceptance(_ wrapper: RegisteredRelayPacket) throws -> Data {
        let publicCard = try EnrollmentCredential.decode(wrapper.senderCredential).card
        let receipt = try RelayPacket.make(kind: .receipt, priority: .ordinary, expiry: 250, correlation: wrapper.packet.digest,
            sealed: SecureEnvelope(identity: responder, peer: publicCard).seal(Data([2])), identity: responder, recipient: publicCard)
        return try RelayAcceptance.make(original: wrapper.packet, identity: responder, returning: receipt).bytes
    }
}

@MainActor @Test func registeredRelayServiceRetainsExactCustodyAcrossLostResponseRestartAndReverseDelivery() async throws {
    let f = RegisteredCustodyFixture(); defer { try? FileManager.default.removeItem(at: f.folder) }
    let wrapper = try f.wrapper(), trust = try f.trust()
    var service = try RegisteredRelayService(storageURL: f.url, trust: trust, now: { 150 })
    _ = try service.admit(wrapper.bytes)
    #expect(try service.count() == 1)
    #expect(Set(service.destinations.map(\.digest)) == [f.publicIdentity.card.digest, f.responder.card.digest])
    let absent = try await service.flush(eligibleDestinations: []) { _, _ in Issue.record("Absent destination sent"); throw EnrollmentError.stopped }
    #expect(absent == .empty)
    let lost = try await service.flush(eligibleDestinations: [f.responder.card.digest]) { bytes, card in
        #expect(bytes == wrapper.bytes && card == f.responder.card)
        throw EnrollmentError.stopped
    }
    guard case .failed(_, let attempts, _) = lost else { Issue.record("Custody unexpectedly removed"); return }
    #expect(attempts == 1)
    service = try RegisteredRelayService(storageURL: f.url, trust: trust, now: { 150 })
    let delivered = try await service.flush(eligibleDestinations: [f.responder.card.digest]) { bytes, _ in
        #expect(bytes == wrapper.bytes); return try f.acceptance(wrapper)
    }
    guard case .delivered(_, let retries, let returned) = delivered else { Issue.record("Expected destination acceptance"); return }
    #expect(retries == 2 && returned != nil)
    #expect(try service.count() == 1)
    let wrongPublic = SecureIdentity(role: .publicUser)
    #expect(try await service.flush(eligibleDestinations: [wrongPublic.card.digest]) { _, _ in throw EnrollmentError.stopped } == .empty)
    let reverse = try await service.flush(eligibleDestinations: [f.publicIdentity.card.digest]) { bytes, card in
        let returned = try RegisteredRelayPacket(bytes: bytes)
        #expect(card == f.publicIdentity.card && returned.packet.kind == .receipt)
        #expect(returned.senderCredential == wrapper.recipientCredential && returned.recipientCredential == wrapper.senderCredential)
        return try RelayAcceptance.make(original: returned.packet, identity: f.publicIdentity, returning: nil).bytes
    }
    guard case .delivered(_, let reverseAttempts, _) = reverse else { Issue.record("Expected reverse receipt acceptance"); return }
    #expect(reverseAttempts == 1)
    #expect(try service.count() == 0)
}

@MainActor @Test func registeredRelayServiceRejectsWrongAcceptanceAndRechecksAuthorityAfterAwait() async throws {
    let f = RegisteredCustodyFixture(); defer { try? FileManager.default.removeItem(at: f.folder) }
    let wrapper = try f.wrapper()
    var wall: Int64 = 150
    let service = try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { wall })
    _ = try service.admit(wrapper.bytes)
    let other = SecureIdentity(role: .responder)
    let wrong = try await service.flush(eligibleDestinations: [f.responder.card.digest]) { _, _ in
        try RelayAcceptance.make(original: wrapper.packet, identity: other, returning: nil).bytes
    }
    guard case .failed = wrong else { Issue.record("Wrong responder accepted"); return }
    let expired = try await service.flush(eligibleDestinations: [f.responder.card.digest]) { _, _ in
        wall = 300; return try f.acceptance(wrapper)
    }
    guard case .failed = expired else { Issue.record("Expired credential accepted after await"); return }
    #expect(try service.count() == 1)
}

@MainActor @Test func registeredRelayServiceSidecarLossReplacementAndOrphansFailClosed() throws {
    let f = RegisteredCustodyFixture(); defer { try? FileManager.default.removeItem(at: f.folder) }
    let service = try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 })
    _ = try service.admit(f.wrapper().bytes)
    let sidecar = f.url.appendingPathExtension("routes.json")
    try Data("{}".utf8).write(to: sidecar)
    #expect(throws: (any Error).self) { try service.count() }
    #expect(throws: (any Error).self) { try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 }) }
    try FileManager.default.removeItem(at: sidecar)
    #expect(throws: (any Error).self) { try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 }) }
}

@MainActor @Test func registeredRelayServiceStoredMetadataGrantsNoRevokedCredentialAuthority() async throws {
    let f = RegisteredCustodyFixture(); defer { try? FileManager.default.removeItem(at: f.folder) }
    let wrapper = try f.wrapper()
    let first = try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 })
    _ = try first.admit(wrapper.bytes)
    let serial = try EnrollmentCredential.decode(wrapper.senderCredential).serial
    let reopened = try RegisteredRelayService(storageURL: f.url, trust: f.trust(revoked: [serial]), now: { 150 })
    let outcome = try await reopened.flush(eligibleDestinations: [f.responder.card.digest]) { _, _ in
        Issue.record("Revoked sender forwarded"); return Data()
    }
    guard case .failed = outcome else { Issue.record("Revoked sender custody removed"); return }
    #expect(try reopened.count() == 1)
}

@MainActor @Test func registeredRelayServiceIsolatesMultiplePublicReverseFlowsAndBoundsPairs() async throws {
    let f = RegisteredCustodyFixture(); defer { try? FileManager.default.removeItem(at: f.folder) }
    let service = try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 })
    let second = SecureIdentity(role: .publicUser)
    _ = try service.admit(f.wrapper().bytes)
    _ = try service.admit(f.wrapper(sender: second).bytes)
    for _ in 0..<2 {
        let outcome = try await service.flush(eligibleDestinations: [f.responder.card.digest]) { bytes, _ in
            try f.acceptance(RegisteredRelayPacket(bytes: bytes))
        }
        guard case .delivered = outcome else { Issue.record("Public event not delivered"); return }
    }
    for identity in [second, f.publicIdentity] {
        let result = try await service.flush(eligibleDestinations: [identity.card.digest]) { bytes, recipient in
            let wrapper = try RegisteredRelayPacket(bytes: bytes)
            #expect(recipient == identity.card)
            #expect(try wrapper.authenticate(trust: f.trust(), now: 150).recipient == identity.card)
            return try RelayAcceptance.make(original: wrapper.packet, identity: identity, returning: nil).bytes
        }
        guard case .delivered(_, let attempts, _) = result else { Issue.record("Cross-public reverse route"); return }
        #expect(attempts == 1)
    }
    #expect(try service.count() == 0)
    for _ in 0..<14 { _ = try service.admit(f.wrapper(sender: SecureIdentity(role: .publicUser)).bytes) }
    #expect(throws: (any Error).self) { try service.admit(f.wrapper(sender: SecureIdentity(role: .publicUser)).bytes) }
}

@MainActor @Test func registeredRelayServiceRechecksSidecarAfterAwaitAndRejectsSidecarOnlyRestart() async throws {
    let f = RegisteredCustodyFixture(); defer { try? FileManager.default.removeItem(at: f.folder) }
    let service = try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 })
    let wrapper = try f.wrapper(); _ = try service.admit(wrapper.bytes)
    let sidecar = f.url.appendingPathExtension("routes.json")
    let result = try await service.flush(eligibleDestinations: [f.responder.card.digest]) { _, _ in
        try Data("{}".utf8).write(to: sidecar)
        return try f.acceptance(wrapper)
    }
    guard case .failed = result else { Issue.record("Sidecar replaced during delivery was accepted"); return }
    try FileManager.default.removeItem(at: f.url)
    #expect(throws: (any Error).self) { try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 }) }
}

@MainActor @Test func registeredRelayServiceRejectsUnsignedRowMetadataSubstitutionBeforeSending() async throws {
    let f = RegisteredCustodyFixture(); defer { try? FileManager.default.removeItem(at: f.folder) }
    let service = try RegisteredRelayService(storageURL: f.url, trust: f.trust(), now: { 150 })
    let wrapper = try f.wrapper(); _ = try service.admit(wrapper.bytes)
    let queue = try RelayQueue(storageURL: f.url)
    _ = try queue.remove(id: wrapper.packet.id)
    // The complete valid credential wrapper and signed inner packet stay identical; only unsigned urgency changes.
    _ = try queue.enqueue(id: wrapper.packet.id, flow: RelayService.flow(for: wrapper.packet), priority: .ordinary,
        expiry: wrapper.packet.expiry, hops: 2, payload: wrapper.bytes, now: 150)
    let outcome = try await service.flush(eligibleDestinations: [f.responder.card.digest]) { _, _ in
        Issue.record("Unsigned urgency substitution was forwarded"); return Data()
    }
    guard case .failed(_, _, let reason) = outcome else { Issue.record("Invalid row was accepted"); return }
    #expect(reason.contains("metadata"))
    #expect(try service.count() == 1)
}
