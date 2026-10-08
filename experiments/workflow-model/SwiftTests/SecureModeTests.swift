import Foundation
import Testing
@testable import RescueDemoState

private final class ModeRecord: SecureRecordStore {
    var data: Data?
    var unavailable = false
    func read() throws -> Data? { if unavailable { throw SecureExchangeError.recordStore(-1) }; return data }
    func write(_ value: Data) throws { if unavailable { throw SecureExchangeError.recordStore(-1) }; data = value }
}

@Test @MainActor func secureModePairsBeforeNetworkingAndPreservesTraining() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-secure-mode-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let record = ModeRecord()
    let demo = DemoController(storageURL: dir.appendingPathComponent("training.sqlite"))
    demo.perform(.sos, value: "Training location")
    demo.useSecureRole(.publicUser, recordStore: record)
    #expect(demo.secureMode && demo.localRole == .publicUser)
    #expect(demo.snapshot?.publicState.hasRequest == false)
    let oldCard = try #require(demo.secureCard)
    demo.startLocalExchange()
    #expect(!demo.transport.active && !demo.error.isEmpty)
    demo.perform(.sos, value: "Secure sample location")
    #expect(demo.snapshot?.pendingTransfers == 1)
    #expect(!demo.pairSecurePeer(SecureIdentity(role: .publicUser).card.base64))
    let responder = SecureIdentity(role: .responder)
    #expect(demo.pairSecurePeer(responder.card.base64))
    #expect(demo.pairedCard == responder.card)
    demo.useTraining()
    #expect(demo.snapshot?.publicState.reportedLocation == "Training location")
    demo.useSecureRole(.publicUser, recordStore: record)
    #expect(demo.secureCard == oldCard && demo.pairedCard == responder.card)
    #expect(demo.snapshot?.publicState.reportedLocation == "Secure sample location")
    #expect(!demo.transport.active)
    demo.reset()
    #expect(demo.secureCard != oldCard && demo.pairedCard == nil)
    #expect(demo.snapshot?.publicState.hasRequest == false)
}

@Test @MainActor func failedSecureInitializationCannotWriteIntoTraining() {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-secure-fail-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let demo = DemoController(storageURL: dir.appendingPathComponent("training.sqlite"))
    demo.perform(.sos, value: "Original training")
    let record = ModeRecord(); record.unavailable = true
    demo.useSecureRole(.publicUser, recordStore: record)
    #expect(demo.snapshot == nil && demo.secureMode && !demo.error.isEmpty)
    demo.perform(.correction, value: "Must not become training")
    demo.useTraining()
    #expect(demo.snapshot?.publicState.reportedLocation == "Original training")
}

@Test @MainActor func secureDemoRoundtripAndRestartOverSocket() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-secure-socket-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let publicRecord = ModeRecord(), responderRecord = ModeRecord()
    let user = DemoController(storageURL: dir.appendingPathComponent("public/training.sqlite"))
    let responder = DemoController(storageURL: dir.appendingPathComponent("responder/training.sqlite"))
    user.useSecureRole(.publicUser, recordStore: publicRecord)
    responder.useSecureRole(.responder, recordStore: responderRecord)
    #expect(user.pairSecurePeer(try #require(responder.secureCard).base64))
    #expect(responder.pairSecurePeer(try #require(user.secureCard).base64))
    user.startLocalExchange(); responder.startLocalExchange()
    defer { user.stopLocalExchange(); responder.stopLocalExchange() }
    let deadline = ContinuousClock.now + .seconds(5)
    while user.transport.hostPort == nil || responder.transport.hostPort == nil {
        guard ContinuousClock.now < deadline else { Issue.record("Secure listeners not ready"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
    user.perform(.sos, value: "Synthetic Floor 2")
    await user.transferQueued(to: .hostPort(host: "127.0.0.1", port: try #require(responder.transport.hostPort)))
    #expect(user.snapshot?.publicState.originalDelivery == .deviceReceived)
    #expect(responder.snapshot?.responderState.hasRequest == true)
    responder.perform(.acknowledge)
    responder.perform(.reply, value: "Synthetic responder reply")
    await responder.transferQueued(to: .hostPort(host: "127.0.0.1", port: try #require(user.transport.hostPort)))
    #expect(user.snapshot?.publicState.originalDelivery == .humanAcknowledged)
    #expect(user.snapshot?.publicState.messages.contains(where: { $0.text == "Synthetic responder reply" }) == true)
    user.stopLocalExchange()
    user.perform(.correction, value: "Synthetic Floor 4")
    let restarted = DemoController(storageURL: dir.appendingPathComponent("public/training.sqlite"))
    restarted.useSecureRole(.publicUser, recordStore: publicRecord)
    #expect(restarted.snapshot?.pendingTransfers == 1 && restarted.pairedCard == responder.secureCard)
    #expect(!restarted.transport.active)
    restarted.startLocalExchange()
    defer { restarted.stopLocalExchange() }
    await restarted.transferQueued(to: .hostPort(host: "127.0.0.1", port: try #require(responder.transport.hostPort)))
    #expect(restarted.snapshot?.pendingTransfers == 0)
    #expect(responder.snapshot?.responderState.reportedLocation == "Synthetic Floor 4")
}

@Test @MainActor func missingSecureHistoryRecoversOnlyThroughExplicitNewSession() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-secure-recover-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let record = ModeRecord()
    let first = DemoController(storageURL: dir.appendingPathComponent("training.sqlite"))
    first.useSecureRole(.publicUser, recordStore: record)
    let card = try #require(first.secureCard)
    #expect(first.pairSecurePeer(SecureIdentity(role: .responder).card.base64))
    first.perform(.sos, value: "Synthetic missing history")
    try FileManager.default.removeItem(at: dir.appendingPathComponent("secure-public"))
    let restart = DemoController(storageURL: dir.appendingPathComponent("training.sqlite"))
    restart.useSecureRole(.publicUser, recordStore: record)
    #expect(restart.snapshot == nil && restart.error.contains("history missing"))
    restart.retrySavedSession()
    #expect(restart.snapshot == nil)
    restart.reset()
    #expect(restart.snapshot?.publicState.hasRequest == false && restart.pairedCard == nil)
    #expect(restart.secureCard != card && !restart.transport.active)
}
