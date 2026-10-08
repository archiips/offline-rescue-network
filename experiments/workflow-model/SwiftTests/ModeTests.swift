import Foundation
import Testing
@testable import RescueDemoState

@Test @MainActor func modeSwitchPreservesIndependentTrainingAndRoleStores() throws {
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("rescue-mode-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:dir) }
    let demo=DemoController(storageURL:dir.appendingPathComponent("session.sqlite"))
    demo.setConnected(false);demo.perform(.sos,value:"Saved training floor")
    demo.useLocalRole(.publicUser)
    #expect(demo.localRole == .publicUser)
    #expect(demo.snapshot?.publicState.hasRequest == false)
    demo.perform(.sos,value:"Saved local floor")
    #expect(demo.snapshot?.publicState.reportedLocation == "Saved local floor")
    #expect(demo.snapshot?.pendingTransfers == 1)
    demo.useLocalRole(.responder)
    #expect(demo.snapshot?.responderState.hasRequest == false)
    demo.useLocalRole(.publicUser)
    #expect(demo.snapshot?.publicState.reportedLocation == "Saved local floor")
    demo.retrySavedSession()
    #expect(demo.snapshot?.pendingTransfers == 1)
    demo.useTraining()
    #expect(demo.localRole == nil && demo.snapshot?.connected == false)
    #expect(demo.snapshot?.publicState.reportedLocation == "Saved training floor")
    #expect(demo.snapshot?.pendingTransfers == 1)
    demo.useLocalRole(.publicUser);demo.reset()
    #expect(demo.snapshot?.publicState.hasRequest == false)
    demo.useTraining()
    #expect(demo.snapshot?.publicState.hasRequest == true)
}

@Test @MainActor func inMemoryTrainingCannotSilentlyBecomeLocalEndpoint() {
    let demo=DemoController();demo.perform(.sos,value:"Retained training")
    demo.useLocalRole(.publicUser)
    #expect(demo.localRole == nil && !demo.error.isEmpty)
    #expect(demo.snapshot?.publicState.reportedLocation == "Retained training")
}

@Test @MainActor func stopAndRestartDoesNotRunAnOldAutomaticBatch() async throws {
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("rescue-generation-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:dir) }
    let demo=DemoController(storageURL:dir.appendingPathComponent("training.sqlite"))
    demo.useLocalRole(.publicUser);demo.startLocalExchange()
    let responder=EndpointController(storageURL:dir.appendingPathComponent("responder.sqlite"),role:.responder)
    let remote=LocalExchangeTransport();remote.onIncoming={ try responder.accept($0) }
    try remote.start(name:"Generation sample",advertise:false,browse:false)
    defer { demo.stopLocalExchange();remote.stop() }
    let deadline=ContinuousClock.now + .seconds(5)
    while demo.transport.hostPort == nil || remote.hostPort == nil {
        guard ContinuousClock.now < deadline else { Issue.record("Listener not ready");return }
        try await Task.sleep(for:.milliseconds(10))
    }
    demo.perform(.sos,value:"Sample floor")
    await demo.transferQueued(to:.hostPort(host:"127.0.0.1",port:try #require(remote.hostPort)))
    #expect(responder.snapshot?.state.messages.count == 1)
    demo.perform(.followUp,value:"Queued before stop")
    // Both calls are synchronous: the scheduled automatic batch has not entered yet.
    demo.stopLocalExchange();demo.startLocalExchange()
    try await Task.sleep(for:.milliseconds(250))
    #expect(responder.snapshot?.state.messages.count == 1)
    #expect(demo.snapshot?.pendingTransfers == 1 && demo.exchangeBusy == false)
}

@Test @MainActor func failedPeerIsNotRetriedByTheNextAction() async throws {
    let dir=FileManager.default.temporaryDirectory.appendingPathComponent("rescue-failed-peer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at:dir) }
    let demo=DemoController(storageURL:dir.appendingPathComponent("training.sqlite"))
    demo.useLocalRole(.publicUser);demo.startLocalExchange()
    let departed=LocalExchangeTransport()
    try departed.start(name:"Departed sample",advertise:false,browse:false)
    defer { demo.stopLocalExchange();departed.stop() }
    let deadline=ContinuousClock.now + .seconds(5)
    while departed.hostPort == nil {
        guard ContinuousClock.now < deadline else { Issue.record("Listener not ready");return }
        try await Task.sleep(for:.milliseconds(10))
    }
    let oldPort=try #require(departed.hostPort);departed.stop()
    demo.perform(.sos,value:"Saved sample")
    await demo.transferQueued(to:.hostPort(host:"127.0.0.1",port:oldPort))
    #expect(!demo.error.isEmpty && demo.snapshot?.pendingTransfers == 1)
    demo.perform(.followUp,value:"New queued sample")
    try await Task.sleep(for:.milliseconds(250))
    #expect(demo.error.isEmpty)
    #expect(demo.snapshot?.pendingTransfers == 2 && demo.exchangeBusy == false)
}
