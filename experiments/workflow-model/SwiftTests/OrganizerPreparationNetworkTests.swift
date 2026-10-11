import Foundation
import CryptoKit
import Testing
@preconcurrency import Network
@testable import RescueDemoState

@MainActor private func preparationPort(_ transport: LocalExchangeTransport) async throws -> NWEndpoint.Port {
    let deadline = ContinuousClock.now + .seconds(3)
    while transport.hostPort == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    return try #require(transport.hostPort)
}
@MainActor @Test func organizerPreparationNetworkIssuesOnlyPossessedAuthorizedCards() async throws {
    let issuer = Curve25519.Signing.PrivateKey(), realm = UUID(), authorized = SecureIdentity(role: .responder)
    let host = OrganizerPreparationHost(service: .init(issuer: issuer, realm: realm, authorizedResponderCards: [authorized.card.bytes]))
    try host.start(); defer { host.stop() }
    let port = try await preparationPort(host.transport)
    let network = OrganizerPreparationNetworkClient(); defer { network.stop() }
    let client = OrganizerPreparationClient(identity: .init(role: .publicUser))
    let bytes = try await network.request(host: "127.0.0.1", port: port.rawValue, client: client)
    #expect(try EnrollmentProfile.decode(bytes).validate(card: client.card, issuerApproved: true,
        at: Int64(Date().timeIntervalSince1970)).realm == realm)
    let allowed = OrganizerPreparationClient(identity: authorized)
    let responderBytes = try await network.request(host: "127.0.0.1", port: port.rawValue, client: allowed)
    #expect(try EnrollmentProfile.decode(responderBytes).validate(card: allowed.card, issuerApproved: true,
        at: Int64(Date().timeIntervalSince1970)).realm == realm)
    let responder = OrganizerPreparationClient(identity: .init(role: .responder))
    await #expect(throws: (any Error).self) { try await network.request(host: "127.0.0.1", port: port.rawValue, client: responder) }
}
@MainActor @Test func organizerPreparationNetworkStopCancelsAwaitedRequest() async throws {
    let silent = LocalExchangeTransport(preparationTimeout: .seconds(3))
    silent.onIncoming = { _ in throw EnrollmentError.stopped }
    try silent.start(name: "Synthetic preparation silent", advertise: false, browse: false); defer { silent.stop() }
    let port = try await preparationPort(silent), network = OrganizerPreparationNetworkClient()
    let task = Task { try await network.request(host: "127.0.0.1", port: port.rawValue,
        client: OrganizerPreparationClient(identity: .init(role: .publicUser))) }
    let deadline = ContinuousClock.now + .seconds(1)
    while network.pendingSessions == 0 && ContinuousClock.now < deadline { await Task.yield() }
    try #require(network.pendingSessions > 0)
    network.stop()
    await #expect(throws: (any Error).self) { try await task.value }
}
@MainActor @Test func organizerPreparationNetworkRejectsUnrelatedSignedChallenge() async throws {
    let wrong = OrganizerPreparationService(issuer: .init(), realm: UUID())
    let other = OrganizerPreparationClient(identity: .init(role: .publicUser))
    let challenge = try wrong.challenge(other.hello())
    let hostile = LocalExchangeTransport(preparationTimeout: .seconds(3))
    hostile.onIncoming = { _ in challenge }
    try hostile.start(name: "Synthetic unrelated challenge", advertise: false, browse: false); defer { hostile.stop() }
    let port = try await preparationPort(hostile), network = OrganizerPreparationNetworkClient(); defer { network.stop() }
    await #expect(throws: (any Error).self) { try await network.request(host: "127.0.0.1", port: port.rawValue,
        client: OrganizerPreparationClient(identity: .init(role: .publicUser))) }
}
