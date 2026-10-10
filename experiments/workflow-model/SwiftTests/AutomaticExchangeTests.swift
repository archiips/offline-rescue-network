import Foundation
import Testing
@testable import RescueDemoState

private final class AutomaticRecord: SecureRecordStore {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ value: Data) throws { data = value }
}

// Removing discovery-driven delivery must leave the original queued and fail this test.
@Test @MainActor func secureDiscoverySendsAndReturnsReplyWithoutManualTransfer() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-auto-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let user = DemoController(storageURL: root.appendingPathComponent("user/training.sqlite"))
    let responder = DemoController(storageURL: root.appendingPathComponent("responder/training.sqlite"))
    user.useSecureRole(.publicUser, recordStore: AutomaticRecord())
    responder.useSecureRole(.responder, recordStore: AutomaticRecord())
    #expect(user.pairSecurePeer(try #require(responder.secureCard).base64))
    #expect(responder.pairSecurePeer(try #require(user.secureCard).base64))
    user.perform(.sos, value: "Synthetic automatic delivery")
    user.startLocalExchange(); responder.startLocalExchange()
    defer { user.stopLocalExchange(); responder.stopLocalExchange() }
    var deadline = ContinuousClock.now + .seconds(12)
    while user.snapshot?.publicState.originalDelivery != .deviceReceived && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.snapshot?.publicState.originalDelivery == .deviceReceived)
    #expect(responder.snapshot?.responderState.hasRequest == true)
    guard responder.snapshot?.responderState.hasRequest == true else { return }
    responder.perform(.acknowledge)
    responder.perform(.reply, value: "Synthetic automatic reply")
    deadline = ContinuousClock.now + .seconds(12)
    while user.snapshot?.publicState.messages.contains(where: { $0.text == "Synthetic automatic reply" }) != true && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.snapshot?.publicState.originalDelivery == .humanAcknowledged)
    #expect(user.snapshot?.publicState.messages.contains(where: { $0.text == "Synthetic automatic reply" }) == true)
    #expect(responder.snapshot?.pendingTransfers == 0)
    user.stopLocalExchange()
    user.perform(.followUp, value: "Saved while stopped")
    try await Task.sleep(for: .milliseconds(300))
    #expect(user.snapshot?.pendingTransfers == 1)
    #expect(!user.exchangeBusy)
    user.startLocalExchange()
    deadline = ContinuousClock.now + .seconds(12)
    while user.snapshot?.pendingTransfers != 0 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.snapshot?.pendingTransfers == 0)
}

// Nearby names and an accepting unrelated responder must never clear a pinned sender's queue.
@Test @MainActor func automaticExchangeWaitsForPinnedResponderAndRecoversLateContact() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-auto-late-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let user = DemoController(storageURL: root.appendingPathComponent("user/training.sqlite"))
    let responder = DemoController(storageURL: root.appendingPathComponent("responder/training.sqlite"))
    let stranger = DemoController(storageURL: root.appendingPathComponent("stranger/training.sqlite"))
    user.useSecureRole(.publicUser, recordStore: AutomaticRecord())
    responder.useSecureRole(.responder, recordStore: AutomaticRecord())
    stranger.useSecureRole(.responder, recordStore: AutomaticRecord())
    #expect(user.pairSecurePeer(try #require(responder.secureCard).base64))
    #expect(responder.pairSecurePeer(try #require(user.secureCard).base64))
    #expect(stranger.pairSecurePeer(try #require(user.secureCard).base64))
    user.startLocalExchange(); stranger.startLocalExchange()
    defer { user.stopLocalExchange(); responder.stopLocalExchange(); stranger.stopLocalExchange() }
    user.perform(.sos, value: "Synthetic late contact")
    try await Task.sleep(for: .seconds(3))
    #expect(user.snapshot?.pendingTransfers == 1)
    #expect(user.snapshot?.publicState.originalDelivery == .waiting)
    #expect(stranger.snapshot?.responderState.hasRequest == false)
    stranger.stopLocalExchange()
    responder.startLocalExchange()
    let deadline = ContinuousClock.now + .seconds(15)
    while user.snapshot?.pendingTransfers != 0 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.snapshot?.pendingTransfers == 0)
    #expect(responder.snapshot?.responderState.reportedLocation == "Synthetic late contact")
}
