import Foundation
import Testing
@preconcurrency import Network
@testable import RescueDemoState

// Research floor pulls: ephemeral identities, encrypted ORQF1/ORPF1 over real loopback sockets, adversarial peers.

@MainActor private final class TestClock {
    var value = 1_000.0
    func read() -> Double { value }
}

@MainActor private func waitForPort(_ transport: LocalExchangeTransport) async throws -> NWEndpoint {
    let deadline = ContinuousClock.now + .seconds(5)
    while transport.hostPort == nil {
        guard ContinuousClock.now < deadline else { throw ExchangeTransportError.timedOut }
        try await Task.sleep(for: .milliseconds(10))
    }
    return .hostPort(host: "127.0.0.1", port: try #require(transport.hostPort))
}

/// Two configured controllers, both listening on loopback without Bonjour.
@MainActor private func pair(context: String = "Home stairwell A", responderContext: String? = nil)
    async throws -> (ResearchPeerController, ResearchPeerController, NWEndpoint, NWEndpoint) {
    let requester = ResearchPeerController(role: .publicUser)
    let responder = ResearchPeerController(role: .responder)
    try requester.configure(peerBase64: responder.card.base64, context: context, checkedFingerprint: true)
    try responder.configure(peerBase64: requester.card.base64, context: responderContext ?? context, checkedFingerprint: true)
    try requester.start(port: nil, discovery: false)
    try responder.start(port: nil, discovery: false)
    return (requester, responder, try await waitForPort(requester.transport), try await waitForPort(responder.transport))
}

/// A responder-role peer that holds real pinned keys but answers with whatever packet the test builds.
@MainActor private final class Adversary {
    let identity = SecureIdentity(role: .responder)
    let transport = LocalExchangeTransport(researchTimeout: .seconds(3))
    var envelope: SecureEnvelope!
    var peer: SecurePairingCard!
    var requests: [ResearchWire.Request] = []
    var reply: (ResearchWire.Request) throws -> Data = { _ in throw ResearchPeerError.malformed }

    func pin(_ card: SecurePairingCard) throws {
        envelope = try SecureEnvelope(identity: identity, peer: card)
        peer = card
        transport.onIncoming = { [unowned self] packet in
            let request = try ResearchWire.decodeRequest(try self.envelope.open(packet))
            self.requests.append(request)
            return try self.reply(request)
        }
        try transport.start(name: "Research adversary", advertise: false, browse: false)
    }

    func sealed(_ response: ResearchWire.Response) throws -> Data {
        try envelope.seal(try ResearchWire.encode(response))
    }

    static func honest(_ request: ResearchWire.Request, level: Int? = 4, source: ResearchFloorSource = .appleFloor,
                       age: Double = 1, id: UUID = UUID()) -> ResearchWire.Response {
        .init(domain: ResearchWire.responseDomain, challenge: request.challenge, context: request.context,
              id: id, level: level, source: source, age: age)
    }
}

@MainActor private func attacked(_ build: @escaping (Adversary, ResearchWire.Request) throws -> Data,
                                 context: String = "Home stairwell A",
                                 during: ((ResearchPeerController, TestClock) -> Void)? = nil)
    async throws -> (Result<ResearchPeerObservation, any Error>, ResearchPeerController, Adversary) {
    let clock = TestClock()
    let requester = ResearchPeerController(role: .publicUser)
    requester.now = { clock.read() }
    let adversary = Adversary()
    try requester.configure(peerBase64: adversary.identity.card.base64, context: context, checkedFingerprint: true)
    try adversary.pin(requester.card)
    adversary.reply = { [unowned adversary] request in
        during?(requester, clock)
        return try build(adversary, request)
    }
    try requester.start(port: nil, discovery: false)
    let target = try await waitForPort(adversary.transport)
    let result: Result<ResearchPeerObservation, any Error>
    do { result = .success(try await requester.pull(to: target)) } catch { result = .failure(error) }
    requester.stop(); adversary.transport.stop()
    return (result, requester, adversary)
}

private func failure(_ result: Result<ResearchPeerObservation, any Error>) -> (any Error)? {
    if case .failure(let error) = result { return error }
    return nil
}

// MARK: Codec

@Test func researchWireRoundTripsCanonicalRequestAndResponse() throws {
    let request = ResearchWire.Request(domain: ResearchWire.requestDomain, challenge: Data(repeating: 7, count: 32), context: "Bothell lab")
    let decoded = try ResearchWire.decodeRequest(try ResearchWire.encode(request))
    #expect(decoded == request)
    let id = UUID()
    let response = ResearchWire.Response(domain: ResearchWire.responseDomain, challenge: request.challenge, context: request.context,
                                         id: id, level: -2, source: .relativeAltitude, age: 2.25)
    #expect(try ResearchWire.decodeResponse(try ResearchWire.encode(response)) == response)
    let unknown = ResearchWire.Response(domain: ResearchWire.responseDomain, challenge: request.challenge, context: request.context,
                                        id: id, level: nil, source: .unavailable, age: 0)
    #expect(try ResearchWire.decodeResponse(try ResearchWire.encode(unknown)) == unknown)
}

@Test func researchWireRejectsNonCanonicalUnknownFieldsAndOversizedPlaintext() throws {
    let challenge = Data(repeating: 1, count: 32).base64EncodedString()
    let good = #"{"challenge":"\#(challenge)","context":"Lab","domain":"ORQF1"}"#
    #expect(try ResearchWire.decodeRequest(Data(good.utf8)).context == "Lab")
    let rejected = [
        #"{"challenge":"\#(challenge)","context":"Lab","domain":"ORQF1","extra":1}"#,
        #"{ "challenge":"\#(challenge)","context":"Lab","domain":"ORQF1"}"#,
        #"{"context":"Lab","challenge":"\#(challenge)","domain":"ORQF1"}"#,
        #"{"challenge":"\#(challenge)","context":"Lab","context":"Lab","domain":"ORQF1"}"#,
        #"{"challenge":"\#(challenge)","context":"Lab","domain":"ORPF1"}"#,
        #"{"challenge":"\#(Data(repeating: 1, count: 31).base64EncodedString())","context":"Lab","domain":"ORQF1"}"#,
        #"{"challenge":"\#(challenge)","context":" Lab","domain":"ORQF1"}"#,
        #"{"challenge":"\#(challenge)","context":"","domain":"ORQF1"}"#,
        #"{"challenge":"\#(challenge)","context":"L\u0007b","domain":"ORQF1"}"#,
        #"{"challenge":"\#(challenge)","context":"\#(String(repeating: "x", count: 65))","domain":"ORQF1"}"#,
    ]
    for text in rejected {
        #expect(throws: ResearchPeerError.self) { try ResearchWire.decodeRequest(Data(text.utf8)) }
    }
    let padded = good + String(repeating: " ", count: 1100)
    #expect(throws: ResearchPeerError.self) { try ResearchWire.decodeRequest(Data(padded.utf8)) }
    #expect(throws: ResearchPeerError.self) { try ResearchWire.decodeRequest(Data()) }
}

@Test func researchWireRejectsInvalidSourceLevelAndAge() throws {
    let base = ResearchWire.Response(domain: ResearchWire.responseDomain, challenge: Data(repeating: 2, count: 32), context: "Lab",
                                     id: UUID(), level: 3, source: .appleFloor, age: 1)
    func variant(level: Int?? = .none, source: ResearchFloorSource? = nil, age: Double? = nil, domain: String? = nil) -> Data {
        let response = ResearchWire.Response(domain: domain ?? base.domain, challenge: base.challenge, context: base.context, id: base.id,
                                             level: level ?? base.level, source: source ?? base.source, age: age ?? base.age)
        return try! ResearchWire.encode(response)
    }
    for data in [variant(level: .some(201)), variant(level: .some(-21)), variant(level: .some(3), source: .unavailable),
                 variant(level: .some(nil), source: .appleFloor), variant(level: .some(nil), source: .relativeAltitude),
                 variant(age: -0.001), variant(age: 10.001), variant(domain: "ORQF1")] {
        #expect(throws: ResearchPeerError.self) { try ResearchWire.decodeResponse(data) }
    }
    #expect(try ResearchWire.decodeResponse(variant(level: .some(200))).level == 200)
    #expect(try ResearchWire.decodeResponse(variant(level: .some(-20))).level == -20)
    let text = String(decoding: try ResearchWire.encode(base), as: UTF8.self)
    for bad in [text.replacingOccurrences(of: "appleFloor", with: "manual"),
                text.replacingOccurrences(of: "appleFloor", with: "peerGraph"),
                text.replacingOccurrences(of: #""age":1"#, with: #""age":1e400"#)] {
        #expect(throws: ResearchPeerError.self) { try ResearchWire.decodeResponse(Data(bad.utf8)) }
    }
}

// MARK: Pairing and configuration

@Test @MainActor func researchConfigurationRequiresCheckedOppositeCardAndValidContext() throws {
    let controller = ResearchPeerController(role: .publicUser)
    let responder = SecureIdentity(role: .responder)
    #expect(throws: ResearchPeerError.fingerprintNotChecked) {
        try controller.configure(peerBase64: responder.card.base64, context: "Lab", checkedFingerprint: false)
    }
    #expect(throws: SecureExchangeError.wrongRole) {
        try controller.configure(peerBase64: SecureIdentity(role: .publicUser).card.base64, context: "Lab", checkedFingerprint: true)
    }
    #expect(throws: SecureExchangeError.ownCard) {
        try controller.configure(peerBase64: controller.card.base64, context: "Lab", checkedFingerprint: true)
    }
    for context in ["", "   ", "a\u{0}b", "tab\there", String(repeating: "é", count: 33)] {
        #expect(throws: ResearchPeerError.invalidContext) {
            try controller.configure(peerBase64: responder.card.base64, context: context, checkedFingerprint: true)
        }
    }
    #expect(controller.peerCard == nil)
    #expect(throws: ResearchPeerError.notConfigured) { try controller.start(port: nil, discovery: false) }
    try controller.configure(peerBase64: responder.card.base64, context: "  Home stairwell A \n", checkedFingerprint: true)
    #expect(controller.peerCard == responder.card)
    #expect(controller.context == "Home stairwell A")
}

@Test @MainActor func researchIdentityIsEphemeralAndResetChangesKeys() throws {
    let first = ResearchPeerController(role: .publicUser)
    let second = ResearchPeerController(role: .publicUser)
    #expect(first.card != second.card)
    #expect(first.card.role == .publicUser)
    #expect(first.transport.discoveryType == "_rescue-floor._tcp")
    try first.configure(peerBase64: SecureIdentity(role: .responder).card.base64, context: "Lab", checkedFingerprint: true)
    let old = first.card
    first.reset(role: .responder)
    #expect(first.card != old)
    #expect(first.card.role == .responder)
    #expect(first.peerCard == nil)
    #expect(first.context == nil)
    #expect(first.observation == nil)
    #expect(!first.busy)
}

@Test @MainActor func researchContextChangesRequireStoppedReconfigurationAndClearReadings() async throws {
    let (requester, responder, _, target) = try await pair()
    defer { requester.stop(); responder.stop() }
    responder.updateLocalReading(.init(level: 2, source: .appleFloor, sampledAt: responder.now()))
    await requester.requestObservation(to: target)
    #expect(requester.observation != nil)
    #expect(throws: ResearchPeerError.running) {
        try requester.configure(peerBase64: responder.card.base64, context: "Other", checkedFingerprint: true)
    }
    #expect(requester.observation != nil)
    requester.updateLocalReading(.init(level: 1, source: .relativeAltitude, sampledAt: requester.now()))
    requester.stop()
    #expect(requester.observation == nil)
    #expect(requester.localReading == nil)
    responder.stop()
    #expect(responder.localReading == nil)
    try responder.configure(peerBase64: requester.card.base64, context: "Home stairwell A", checkedFingerprint: true)
    responder.updateLocalReading(.init(level: 2, source: .appleFloor, sampledAt: responder.now()))
    try responder.configure(peerBase64: requester.card.base64, context: "Other", checkedFingerprint: true)
    #expect(responder.localReading == nil)
}

@Test @MainActor func researchLocalReadingRejectsInconsistentValues() {
    let controller = ResearchPeerController(role: .publicUser)
    controller.updateLocalReading(.init(level: 3, source: .appleFloor, sampledAt: 5))
    #expect(controller.localReading?.level == 3)
    for invalid in [ResearchFloorReading(level: 3, source: .unavailable, sampledAt: 5),
                    ResearchFloorReading(level: nil, source: .appleFloor, sampledAt: 5),
                    ResearchFloorReading(level: 201, source: .relativeAltitude, sampledAt: 5),
                    ResearchFloorReading(level: 1, source: .appleFloor, sampledAt: .nan)] {
        controller.updateLocalReading(.init(level: 3, source: .appleFloor, sampledAt: 5))
        controller.updateLocalReading(invalid)
        #expect(controller.localReading == nil)
    }
    controller.updateLocalReading(.init(level: nil, source: .unavailable, sampledAt: 5))
    #expect(controller.localReading?.source == .unavailable)
}

// MARK: Real sockets

@Test @MainActor func researchPullCarriesKnownReadingWithConservativeAge() async throws {
    let (requester, responder, _, target) = try await pair()
    defer { requester.stop(); responder.stop() }
    let reading = ResearchFloorReading(level: 3, source: .appleFloor, sampledAt: responder.now() - 2)
    responder.updateLocalReading(reading)
    let before = requester.now()
    await requester.requestObservation(to: target)
    let after = requester.now()
    let observation = try #require(requester.observation)
    #expect(observation.level == 3)
    #expect(observation.source == .appleFloor)
    #expect(observation.id == reading.id)
    #expect(observation.fingerprint == responder.card.fingerprint)
    #expect(observation.receivedAt >= before && observation.receivedAt <= after)
    #expect(observation.ageAtReceipt >= 2)
    #expect(observation.ageAtReceipt <= 2 + (after - before) + 0.5)
    #expect(observation.isFresh(at: observation.receivedAt))
    #expect(abs(observation.age(at: observation.receivedAt + 3) - (observation.ageAtReceipt + 3)) < 1e-9)
    #expect(!observation.isFresh(at: observation.receivedAt + 10 - observation.ageAtReceipt + 0.01))
    #expect(!observation.isFresh(at: observation.receivedAt - 1))
    #expect(!requester.busy)
}

@Test @MainActor func researchPullCarriesUnknownWithoutLevel() async throws {
    let (requester, responder, _, target) = try await pair()
    defer { requester.stop(); responder.stop() }
    responder.updateLocalReading(.init(level: nil, source: .unavailable, sampledAt: responder.now()))
    let observation = try await requester.pull(to: target)
    #expect(observation.level == nil)
    #expect(observation.source == .unavailable)
}

@Test @MainActor func researchResponderWithoutSharedReadingSendsNothing() async throws {
    let (requester, responder, _, target) = try await pair()
    defer { requester.stop(); responder.stop() }
    await #expect(throws: ExchangeTransportError.self) { try await requester.pull(to: target) }
    await requester.requestObservation(to: target)
    #expect(requester.observation == nil)
    #expect(requester.status.contains("rejected") || requester.status.contains("failed"))
}

@Test @MainActor func researchResponderRefusesStaleOrFutureLocalReading() async throws {
    let (requester, responder, _, target) = try await pair()
    defer { requester.stop(); responder.stop() }
    responder.updateLocalReading(.init(level: 1, source: .appleFloor, sampledAt: responder.now() - 10.5))
    await #expect(throws: ExchangeTransportError.self) { try await requester.pull(to: target) }
    responder.updateLocalReading(.init(level: 1, source: .appleFloor, sampledAt: responder.now() + 5))
    await #expect(throws: ExchangeTransportError.self) { try await requester.pull(to: target) }
    #expect(requester.observation == nil)
}

@Test @MainActor func researchMismatchedContextFailsClosed() async throws {
    let (requester, responder, _, target) = try await pair(context: "Home stairwell A", responderContext: "Home stairwell B")
    defer { requester.stop(); responder.stop() }
    responder.updateLocalReading(.init(level: 1, source: .appleFloor, sampledAt: responder.now()))
    await #expect(throws: ExchangeTransportError.self) { try await requester.pull(to: target) }
    #expect(requester.observation == nil)
}

@Test @MainActor func researchUnpairedPeerFailsClosed() async throws {
    let (requester, responder, _, target) = try await pair()
    defer { requester.stop(); responder.stop() }
    responder.updateLocalReading(.init(level: 1, source: .appleFloor, sampledAt: responder.now()))
    // Requester re-pairs with a different responder card; the real responder no longer trusts or matches it.
    requester.stop()
    try requester.configure(peerBase64: SecureIdentity(role: .responder).card.base64, context: "Home stairwell A", checkedFingerprint: true)
    try requester.start(port: nil, discovery: false)
    await #expect(throws: ExchangeTransportError.self) { try await requester.pull(to: target) }
    #expect(requester.observation == nil)
}

@Test @MainActor func researchResponderRejectsCraftedRequests() async throws {
    let (requester, responder, _, target) = try await pair()
    defer { requester.stop(); responder.stop() }
    responder.updateLocalReading(.init(level: 1, source: .appleFloor, sampledAt: responder.now()))
    // A test-held copy of the requester's keys would be needed to sign; use a fresh unpaired public identity instead.
    let stranger = SecureIdentity(role: .publicUser)
    let strangerEnvelope = try SecureEnvelope(identity: stranger, peer: responder.card)
    let channel = LocalExchangeTransport(researchTimeout: .seconds(3))
    try channel.start(name: "Crafted research requests", advertise: false, browse: false)
    defer { channel.stop() }
    let valid = ResearchWire.Request(domain: ResearchWire.requestDomain, challenge: Data(repeating: 9, count: 32), context: "Home stairwell A")
    await #expect(throws: ExchangeTransportError.self) {
        _ = try await channel.exchange(try strangerEnvelope.seal(try ResearchWire.encode(valid)), to: target)
    }
    // Paired sender keys, semantically wrong requests.
    let paired = try SecureEnvelope(identity: requester.identity, peer: responder.card)
    let wrong = [
        ResearchWire.Request(domain: ResearchWire.requestDomain, challenge: valid.challenge, context: "Home stairwell B"),
        ResearchWire.Request(domain: ResearchWire.responseDomain, challenge: valid.challenge, context: valid.context),
        ResearchWire.Request(domain: ResearchWire.requestDomain, challenge: Data(repeating: 9, count: 16), context: valid.context),
    ]
    for request in wrong {
        await #expect(throws: ExchangeTransportError.self) {
            _ = try await channel.exchange(try paired.seal(try ResearchWire.encode(request)), to: target)
        }
    }
    let honest = try await channel.exchange(try paired.seal(try ResearchWire.encode(valid)), to: target)
    let answer = try ResearchWire.decodeResponse(try paired.open(honest))
    #expect(answer.challenge == valid.challenge)
    #expect(answer.level == 1)
}

// MARK: Authenticated semantic attacks

@Test @MainActor func researchHonestAdversaryBaselineIsAccepted() async throws {
    let (result, requester, adversary) = try await attacked { a, r in try a.sealed(Adversary.honest(r)) }
    let observation = try result.get()
    #expect(observation.level == 4)
    #expect(observation.fingerprint == adversary.identity.card.fingerprint)
    #expect(observation.ageAtReceipt == 1) // injected clock: zero measured round trip
    #expect(adversary.requests.count == 1)
    #expect(adversary.requests[0].challenge.count == 32)
    #expect(requester.observation == nil) // stop cleared it
}

@Test @MainActor func researchSignedWrongChallengeIsRejected() async throws {
    let (result, _, _) = try await attacked { a, r in
        var response = Adversary.honest(r)
        response.challenge = Data(r.challenge.reversed())
        return try a.sealed(response)
    }
    #expect(failure(result) as? ResearchPeerError == .wrongChallenge)
}

@Test @MainActor func researchSignedWrongContextIsRejected() async throws {
    let (result, _, _) = try await attacked { a, r in
        var response = Adversary.honest(r)
        response.context = "Home stairwell B"
        return try a.sealed(response)
    }
    #expect(failure(result) as? ResearchPeerError == .wrongContext)
}

@Test @MainActor func researchSignedRequestEchoIsRejected() async throws {
    let (result, _, _) = try await attacked { a, r in try a.envelope.seal(try ResearchWire.encode(r)) }
    #expect(failure(result) is ResearchPeerError)
}

@Test @MainActor func researchSignedInvalidReadingsAreRejected() async throws {
    let builders: [(ResearchWire.Request) -> ResearchWire.Response] = [
        { Adversary.honest($0, level: 201) },
        { Adversary.honest($0, level: 3, source: .unavailable) },
        { Adversary.honest($0, level: nil, source: .appleFloor) },
        { Adversary.honest($0, age: -1) },
        { Adversary.honest($0, age: 10.5) },
    ]
    for build in builders {
        let (result, requester, _) = try await attacked { a, r in try a.sealed(build(r)) }
        #expect(failure(result) is ResearchPeerError)
        #expect(requester.observation == nil)
    }
    let (raw, _, _) = try await attacked { a, r in
        let text = String(decoding: try ResearchWire.encode(Adversary.honest(r)), as: UTF8.self)
        return try a.envelope.seal(Data(text.replacingOccurrences(of: "appleFloor", with: "manual").utf8))
    }
    #expect(failure(raw) as? ResearchPeerError == .malformed)
    let (oversized, _, _) = try await attacked { a, r in
        try a.envelope.seal(try ResearchWire.encode(Adversary.honest(r)) + Data(repeating: 0x20, count: 1100))
    }
    #expect(failure(oversized) as? ResearchPeerError == .malformed)
}

@Test @MainActor func researchThirdPartySignerAndMisaddressedResponsesAreRejected() async throws {
    let (wrongSender, _, _) = try await attacked { a, r in
        // Valid keys and the right recipient, but not the pinned sender.
        try SecureEnvelope(identity: SecureIdentity(role: .responder), peer: a.peer).seal(try ResearchWire.encode(Adversary.honest(r)))
    }
    #expect(failure(wrongSender) as? SecureExchangeError == .wrongSender)
    let (misaddressed, _, _) = try await attacked { a, r in
        // Pinned sender key, sealed to some other public identity.
        try SecureEnvelope(identity: a.identity, peer: SecureIdentity(role: .publicUser).card).seal(try ResearchWire.encode(Adversary.honest(r)))
    }
    #expect(failure(misaddressed) as? SecureExchangeError == .wrongRecipient)
    let (garbage, _, _) = try await attacked { _, _ in Data(repeating: 0x41, count: 300) }
    #expect(failure(garbage) as? SecureExchangeError == .notEnvelope)
}

@Test @MainActor func researchReplayedEarlierResponseIsRejected() async throws {
    let clock = TestClock()
    let requester = ResearchPeerController(role: .publicUser)
    requester.now = { clock.read() }
    let adversary = Adversary()
    try requester.configure(peerBase64: adversary.identity.card.base64, context: "Lab", checkedFingerprint: true)
    try adversary.pin(requester.card)
    var recorded: Data?
    adversary.reply = { [unowned adversary] request in
        if let recorded { return recorded }
        let packet = try adversary.sealed(Adversary.honest(request))
        recorded = packet
        return packet
    }
    try requester.start(port: nil, discovery: false)
    defer { requester.stop(); adversary.transport.stop() }
    let target = try await waitForPort(adversary.transport)
    _ = try await requester.pull(to: target)
    await #expect(throws: ResearchPeerError.wrongChallenge) { try await requester.pull(to: target) }
    #expect(adversary.requests.count == 2)
    #expect(adversary.requests[0].challenge != adversary.requests[1].challenge)
}

@Test @MainActor func researchDelayedRoundTripIsRejected() async throws {
    let (result, _, _) = try await attacked({ a, r in try a.sealed(Adversary.honest(r, age: 0)) },
                                            during: { _, clock in clock.value += 3.01 })
    #expect(failure(result) as? ResearchPeerError == .roundTripTooLong)
}

@Test @MainActor func researchAgePlusRoundTripBeyondLimitIsRejected() async throws {
    let (result, _, _) = try await attacked({ a, r in try a.sealed(Adversary.honest(r, age: 8)) },
                                            during: { _, clock in clock.value += 2.5 })
    #expect(failure(result) as? ResearchPeerError == .tooOld)
    let (accepted, _, _) = try await attacked({ a, r in try a.sealed(Adversary.honest(r, age: 7)) },
                                              during: { _, clock in clock.value += 2.5 })
    #expect(try accepted.get().ageAtReceipt == 9.5)
}

// MARK: Lifecycle fences

@Test @MainActor func researchAllowsOnlyOnePendingPull() async throws {
    let clock = TestClock()
    let requester = ResearchPeerController(role: .publicUser)
    requester.now = { clock.read() }
    let adversary = Adversary()
    try requester.configure(peerBase64: adversary.identity.card.base64, context: "Lab", checkedFingerprint: true)
    try adversary.pin(requester.card)
    adversary.reply = { [unowned adversary] r in try adversary.sealed(Adversary.honest(r)) }
    try requester.start(port: nil, discovery: false)
    defer { requester.stop(); adversary.transport.stop() }
    let target = try await waitForPort(adversary.transport)
    let first = Task { await requester.requestObservation(to: target) }
    while !requester.busy { await Task.yield() }
    await #expect(throws: ResearchPeerError.busy) { try await requester.pull(to: target) }
    await requester.requestObservation(to: target)
    await first.value
    #expect(adversary.requests.count == 1)
    #expect(requester.observation != nil)
    #expect(!requester.busy)
}

@Test @MainActor func researchStopDuringPullDiscardsResult() async throws {
    let (result, requester, adversary) = try await attacked({ a, r in try a.sealed(Adversary.honest(r)) },
                                                            during: { requester, _ in requester.stop() })
    #expect(failure(result) != nil)
    #expect(requester.observation == nil)
    #expect(!requester.busy)
    #expect(adversary.requests.count == 1)
}

@Test @MainActor func researchResetDuringPullDiscardsResult() async throws {
    var newCard: SecurePairingCard?
    let (result, requester, _) = try await attacked({ a, r in try a.sealed(Adversary.honest(r)) },
                                                    during: { requester, _ in requester.reset(role: .publicUser); newCard = requester.card })
    #expect(failure(result) != nil)
    #expect(requester.observation == nil)
    #expect(requester.peerCard == nil)
    #expect(requester.card == newCard)
    #expect(!requester.busy)
}
