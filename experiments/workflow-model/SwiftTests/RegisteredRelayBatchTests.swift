import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@MainActor @Test func registeredRelayBatchIsolatesExpiredPublicFromOtherPendingReplies() throws {
    let f = try InboxFixture(); defer { try? FileManager.default.removeItem(at: f.root) }
    var now: Int64 = 150
    let inbox = try RegisteredResponderInbox(secure: f.responder, credential: f.credential,
        trust: f.trust, registryStore: f.registry, now: { now })
    for index in 0..<2 {
        let credential = try EnrollmentCredential.issue(card: f.users[index].card, realm: f.trust.realm,
            notBefore: 100, expires: index == 0 ? 160 : 200, issuer: f.issuer)
        let user = try RegisteredExchangeController(secure: f.users[index], credential: credential.bytes,
            trust: f.trust, responders: [f.credential], now: { 150 })
        try user.perform(.sos, value: "SYNTHETIC independently expiring public \(index)")
        _ = try inbox.receiveRegisteredRelay(#require(try user.registeredRelayOutgoing()).bytes)
        try inbox.perform(conversationID: f.users[index].card.fingerprint, action: .reply, value: "SYNTHETIC queued reply \(index)")
    }
    #expect(inbox.rows.count == 2)
    #expect(inbox.rows.allSatisfy { $0.snapshot.pendingTransfers == 1 })
    now = 170
    let batch = try inbox.registeredRelayBatch()
    #expect(batch.count == 1)
    #expect(try batch.first?.authenticate(trust: f.trust, now: now).recipient == f.users[1].card)
    #expect(inbox.rows.allSatisfy { $0.snapshot.pendingTransfers == 1 })
    #expect(inbox.status.contains("One relay conversation is unavailable"))
}
