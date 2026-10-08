import Testing
@testable import RescueDemoState

@Test @MainActor func nativeRoundTrip() throws {
    let demo = DemoController()
    #expect(demo.snapshot?.publicState.hasRequest == false)
    demo.perform(.sos, value: "Training building / Floor unknown")
    let state = try #require(demo.snapshot)
    #expect(state.publicState.originalDelivery == .deviceReceived)
    #expect(state.responderState.hasRequest)
    demo.perform(.acknowledge)
    #expect(demo.snapshot?.publicState.originalDelivery == .humanAcknowledged)
    demo.perform(.reply, value: "Training response")
    #expect(demo.snapshot?.publicState.messages.contains { $0.kind == .reply && $0.text == "Training response" } == true)
}

@Test @MainActor func disconnectedReturnAndCorrection() throws {
    let demo = DemoController(); demo.perform(.sos, value: "Training floor 1")
    demo.setConnected(false);demo.perform(.acknowledge)
    #expect(demo.snapshot?.publicState.originalDelivery == .deviceReceived)
    #expect(demo.snapshot?.pendingTransfers == 1)
    demo.perform(.correction, value: "Training floor 4")
    #expect(demo.snapshot?.responderState.reportedLocation == "Training floor 1")
    #expect(demo.snapshot?.publicState.pendingPublicMessages == 1)
    demo.setConnected(true)
    let state = try #require(demo.snapshot)
    #expect(state.publicState.originalDelivery == .humanAcknowledged)
    #expect(state.responderState.reportedLocation == "Training floor 4")
    #expect(state.publicState.pendingPublicMessages == 0 && state.pendingTransfers == 0)
}

@Test @MainActor func bridgeEscapingBoundsAndLifetime() throws {
    let demo = DemoController()
    demo.perform(.sos, value: "Test \"floor\"\n第4层")
    #expect(demo.snapshot?.publicState.reportedLocation == "Test \"floor\"\n第4层")
    demo.perform(.reply, value: String(repeating: "x", count: 2049))
    #expect(!demo.error.isEmpty)
    for _ in 0..<100 { demo.reset(); #expect(demo.snapshot?.publicState.hasRequest == false) }
}

@Test @MainActor func lateWithdrawalAndExplicitReopen() {
    let demo = DemoController();demo.perform(.sos, value: "Training floor 1")
    demo.perform(.assign, value: "Training team A");demo.perform(.resolve, value: "Training scenario complete")
    demo.perform(.withdrawal, value: "Training withdrawal")
    #expect(demo.snapshot?.responderState.lateUpdate == true)
    #expect(demo.snapshot?.publicState.handling == .resolved)
    demo.perform(.disposition, value: "Training withdrawal reviewed")
    #expect(demo.snapshot?.publicState.withdrawalPending == false)
    demo.perform(.reopen, value: "Review training update")
    #expect(demo.snapshot?.responderState.handling == .open)
    demo.perform(.withdrawal, value: "Another training withdrawal")
    #expect(demo.snapshot?.publicState.withdrawalPending == true)
}

@Test @MainActor func fullStoreRetainsUnconfirmedTransfers() {
    let demo = DemoController()
    demo.perform(.sos, value: "Training floor")
    demo.setConnected(false)
    for _ in 0..<64 { demo.perform(.followUp, value: "Synthetic update") }
    #expect(demo.snapshot?.pendingTransfers == 64)
    demo.setConnected(true)
    #expect(demo.snapshot?.pendingTransfers == 2)
    let updates = demo.snapshot?.publicState.messages.filter { $0.kind == .followUp } ?? []
    #expect(updates.count == 64)
    #expect(updates.filter { $0.delivery == .deviceReceived }.count == 62)
    #expect(updates.filter { $0.delivery == .waiting }.count == 2)
    #expect(demo.snapshot?.responderState.messages.filter { $0.kind == .followUp }.count == 63)
    #expect(demo.error.contains("full"))
}
