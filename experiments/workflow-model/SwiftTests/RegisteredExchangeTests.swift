import Foundation
import CryptoKit
import Testing
@testable import RescueDemoState

@Test @MainActor func registeredDiscoveryBootstrapsUnpairedDevicesAndExchangesSOSReply() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-registered-network-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let user = try SecureEndpointController(rootURL: root.appendingPathComponent("user"), role: .publicUser, recordStore: EnrollmentTestStore())
    let responder = try SecureEndpointController(rootURL: root.appendingPathComponent("responder"), role: .responder, recordStore: EnrollmentTestStore())
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let trust = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300)
    let publicCredential = try EnrollmentCredential.issue(card: user.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let responderCredential = try EnrollmentCredential.issue(card: responder.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let publicController = try RegisteredExchangeController(secure: user, credential: publicCredential.bytes, trust: trust, now: { 150 })
    let responderController = try RegisteredExchangeController(secure: responder, credential: responderCredential.bytes, trust: trust, now: { 150 })
    #expect(user.peerCard == nil && responder.peerCard == nil)
    try publicController.perform(.sos, value: "Synthetic registered network SOS")
    try publicController.start(); try responderController.start()
    defer { publicController.stop(); responderController.stop() }
    var deadline = ContinuousClock.now + .seconds(15)
    while user.endpoint.snapshot?.state.originalDelivery != .deviceReceived && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.endpoint.snapshot?.state.originalDelivery == .deviceReceived)
    guard responder.endpoint.snapshot?.state.hasRequest == true else { Issue.record("Registered SOS not received"); return }
    try responderController.perform(.acknowledge)
    try responderController.perform(.reply, value: "Synthetic registered reply")
    deadline = ContinuousClock.now + .seconds(15)
    while user.endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic registered reply" }) != true && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.endpoint.snapshot?.state.originalDelivery == .humanAcknowledged)
    #expect(user.endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic registered reply" }) == true)
    #expect(responder.endpoint.snapshot?.pendingTransfers == 0)
    publicController.stop()
    try publicController.perform(.followUp, value: "Queued while stopped")
    try await Task.sleep(for: .milliseconds(200))
    #expect(user.endpoint.snapshot?.pendingTransfers == 1)
    try publicController.start()
    deadline = ContinuousClock.now + .seconds(15)
    while user.endpoint.snapshot?.pendingTransfers != 0 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.endpoint.snapshot?.pendingTransfers == 0)
    responderController.stop()
    try responderController.start()
    try publicController.perform(.followUp, value: "Synthetic after responder restart")
    deadline = ContinuousClock.now + .seconds(15)
    while user.endpoint.snapshot?.pendingTransfers != 0 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(user.endpoint.snapshot?.pendingTransfers == 0)
    try responderController.perform(.reply, value: "Synthetic responder restart reply")
    deadline = ContinuousClock.now + .seconds(15)
    while responder.endpoint.snapshot?.pendingTransfers != 0 && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(responder.endpoint.snapshot?.pendingTransfers == 0)
    #expect(user.endpoint.snapshot?.state.messages.contains(where: { $0.text == "Synthetic responder restart reply" }) == true)
}

@Test @MainActor func registeredActionRejectionIsReportedWithoutPretendingItWasSaved() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-registered-action-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let secure = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: EnrollmentTestStore())
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID()
    let trust = try EnrollmentTrust(realm: realm, issuer: issuer.publicKey.rawRepresentation, validUntil: 300)
    let credential = try EnrollmentCredential.issue(card: secure.card, realm: realm, notBefore: 100, expires: 200, issuer: issuer)
    let controller = try RegisteredExchangeController(secure: secure, credential: credential.bytes, trust: trust, now: { 150 })
    #expect(throws: EndpointError.self) { try controller.perform(.reply, value: "Public cannot issue responder reply") }
    #expect(controller.snapshot?.pendingTransfers == 0)
}
