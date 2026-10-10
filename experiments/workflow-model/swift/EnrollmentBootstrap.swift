import Foundation
import CryptoKit

/// Experimental two-party drill bootstrap. Discovery never supplies the trust policy.
/// Four signed frames prove possession and the exact challenge transcript before pinning.
@MainActor public final class EnrollmentBootstrap {
    struct Claims: Codable {
        var domain: String
        var credential: Data
        var challenge: Data
        var transcript: Data
    }
    struct Proof: Codable {
        var domain: String
        var credential: Data
        var challenge: Data
        var transcript: Data
        var signature: Data
        var claims: Claims { .init(domain: domain, credential: credential, challenge: challenge, transcript: transcript) }
    }
    private struct Pending {
        let hello: Data
        let response: Data
        let peerCredential: Data
        let began: Double
        var finish: Data?
        var ready: Data?
    }
    var pendingCount: Int { pending.count }
    public private(set) var peerCredential: Data?
    private let secure: any EnrollmentConversationContext
    private let credential: Data
    private let trust: EnrollmentTrust
    private let now: @MainActor () -> Int64
    var elapsed: @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime }
    private var active = true
    private var pending: [Data: Pending] = [:]
    private var outgoing: Pending?

    public convenience init(secure: SecureEndpointController, credential: Data, trust: EnrollmentTrust,
                now: @escaping @MainActor () -> Int64 = { Int64(Date().timeIntervalSince1970) }) throws {
        try self.init(context: secure, credential: credential, trust: trust, now: now)
    }
    init(context secure: any EnrollmentConversationContext, credential: Data, trust: EnrollmentTrust,
         now: @escaping @MainActor () -> Int64) throws {
        guard try trust.verify(credential, expectedRole: secure.role, at: now()).card == secure.card else { throw EnrollmentError.wrongIdentity }
        self.secure = secure; self.credential = credential; self.trust = trust; self.now = now
    }
    public func stop() { active = false; pending = [:]; outgoing = nil; peerCredential = nil }

    /// Revalidate prepared authorization on every application operation, including after expiry.
    public func validateSession() throws { _ = try authorizedPeer() }
    private func authorizedPeer() throws -> SecurePairingCard {
        try validateSelf()
        guard let peerCredential else { throw EnrollmentError.wrongIdentity }
        let peer = try trust.verify(peerCredential, expectedRole: opposite, at: now()).card
        if let saved = secure.peerCard {
            guard saved == peer else { throw EnrollmentError.alreadyPaired }
        } else {
            guard secure.role == .publicUser, let outgoing, outgoing.ready != nil, fresh(outgoing) else { throw EnrollmentError.wrongTranscript }
        }
        return peer
    }
    private var opposite: EndpointRole { secure.role == .publicUser ? .responder : .publicUser }
    private func validateSelf() throws {
        guard active else { throw EnrollmentError.stopped }
        _ = try secure.enrollmentIdentity()
        guard try trust.verify(credential, expectedRole: secure.role, at: now()).card == secure.card else { throw EnrollmentError.wrongIdentity }
    }
    private func digest(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    private func fresh(_ value: Pending) -> Bool {
        let time = elapsed()
        return time.isFinite && value.began.isFinite && time >= value.began && time - value.began < 10
    }
    private func sign(_ domain: String, challenge: Data, transcript: Data) throws -> Data {
        let claims = Claims(domain: domain, credential: credential, challenge: challenge, transcript: transcript)
        return try EnrollmentWire.encode(Proof(domain: domain, credential: credential, challenge: challenge,
            transcript: transcript, signature: secure.enrollmentIdentity().signingKey.signature(for: EnrollmentWire.encode(claims))))
    }
    private func verify(_ data: Data, domain: String) throws -> Proof {
        try validateSelf()
        let proof = try EnrollmentWire.decode(Proof.self, data)
        guard proof.domain == domain, proof.challenge.count == 32, proof.signature.count == 64,
              proof.transcript.count == (domain == "OREH1" ? 0 : 32) else { throw EnrollmentError.malformed }
        let peer = try trust.verify(proof.credential, expectedRole: opposite, at: now()).card
        guard peer.signingKey.isValidSignature(proof.signature, for: try EnrollmentWire.encode(proof.claims)) else { throw EnrollmentError.invalidSignature }
        if let saved = secure.peerCard, saved != peer { throw EnrollmentError.alreadyPaired }
        return proof
    }
    private func nonce() -> Data {
        var bytes = Data(count: 32)
        bytes.withUnsafeMutableBytes { raw in
            // SystemRandomNumberGenerator uses the system random source; no fallback seed.
            var generator = SystemRandomNumberGenerator()
            for i in 0..<raw.count { raw[i] = UInt8.random(in: .min ... .max, using: &generator) }
        }
        return bytes
    }
    public func hello() throws -> Data {
        try validateSelf()
        guard secure.role == .publicUser else { throw EnrollmentError.wrongRole }
        let hello = try sign("OREH1", challenge: nonce(), transcript: Data())
        outgoing = Pending(hello: hello, response: Data(), peerCredential: Data(), began: elapsed())
        return hello
    }
    public func answerHello(_ hello: Data) throws -> Data {
        guard secure.role == .responder else { throw EnrollmentError.wrongRole }
        let proof = try verify(hello, domain: "OREH1")
        let peer = try trust.verify(proof.credential, expectedRole: .publicUser, at: now()).card
        pending = pending.filter { fresh($0.value) }
        if let existing = pending.values.first(where: { (try? EnrollmentCredential.decode($0.peerCredential).card) == peer }) {
            if existing.hello == hello { return existing.response }
            // Do not let a replay/new Hello invalidate an already completed provisional lease.
            if existing.ready != nil { throw EnrollmentError.busy }
        }
        pending = pending.filter { (try? EnrollmentCredential.decode($0.value.peerCredential).card) != peer }
        guard pending.count < 4 else { throw EnrollmentError.busy }
        let challenge = nonce()
        let response = try sign("OREC2", challenge: challenge, transcript: digest(hello))
        pending[challenge] = Pending(hello: hello, response: response, peerCredential: proof.credential, began: elapsed())
        return response
    }
    public func answerChallenge(_ response: Data) throws -> Data {
        guard secure.role == .publicUser, let request = outgoing, fresh(request) else { throw EnrollmentError.wrongTranscript }
        let proof = try verify(response, domain: "OREC2")
        guard proof.transcript == digest(request.hello) else { throw EnrollmentError.wrongTranscript }
        let finish = try sign("OREF1", challenge: proof.challenge, transcript: digest(request.hello + response))
        outgoing = Pending(hello: request.hello, response: response, peerCredential: proof.credential,
                           began: request.began, finish: finish)
        return finish
    }
    public func answerFinish(_ finish: Data) throws -> Data {
        guard secure.role == .responder else { throw EnrollmentError.wrongRole }
        let proof = try verify(finish, domain: "OREF1")
        guard var request = pending[proof.challenge], fresh(request), proof.credential == request.peerCredential,
              proof.transcript == digest(request.hello + request.response) else { throw EnrollmentError.wrongTranscript }
        // A fresh Finish can reauthorize the same persisted peer after stop/restart.
        // A new unpinned responder remains provisional until encrypted application traffic.
        if secure.peerCard != nil { peerCredential = proof.credential }
        if let previous = request.finish {
            guard previous == finish, let ready = request.ready else { throw EnrollmentError.wrongTranscript }
            return ready
        }
        let ready = try sign("ORER1", challenge: proof.challenge, transcript: digest(finish))
        request.finish = finish; request.ready = ready; pending[proof.challenge] = request
        return ready
    }
    /// A responder only persists a pin after an authenticated encrypted application packet.
    /// Lost Ready / abandoned Finish cannot occupy its one conversation across restart.
    public func acceptApplication(_ packet: Data) throws -> Data {
        try validateSelf()
        if secure.peerCard == nil {
            guard secure.role == .responder, packet.count >= 36 else { throw EnrollmentError.wrongTranscript }
            let sender = Data(packet.dropFirst(4).prefix(32))
            guard let request = pending.values.first(where: {
                $0.ready != nil && fresh($0) && (try? EnrollmentCredential.decode($0.peerCredential).card.digest) == sender
            }) else { throw EnrollmentError.wrongTranscript }
            let peer = try trust.verify(request.peerCredential, expectedRole: .publicUser, at: now()).card
            _ = try SecureEnvelope(identity: secure.enrollmentIdentity(), peer: peer).open(packet)
            try secure.pair(peer.base64)
            peerCredential = request.peerCredential
        }
        try validateSession()
        return try secure.accept(packet)
    }
    public func nextPacket() throws -> Data? {
        let peer = try authorizedPeer()
        let envelope = try SecureEnvelope(identity: secure.enrollmentIdentity(), peer: peer)
        return try secure.nextPlaintextPacket().map(envelope.seal)
    }
    public func confirm(_ receipt: Data) throws {
        guard secure.role == .publicUser || secure.peerCard != nil else { throw EnrollmentError.wrongRole }
        let peer = try authorizedPeer()
        if secure.peerCard == nil {
            _ = try SecureEnvelope(identity: secure.enrollmentIdentity(), peer: peer).open(receipt)
            try secure.pair(peer.base64)
        }
        try secure.confirm(receipt)
    }
    public func acceptReady(_ ready: Data) throws {
        guard secure.role == .publicUser, let request = outgoing, fresh(request), let finish = request.finish else { throw EnrollmentError.wrongTranscript }
        let proof = try verify(ready, domain: "ORER1")
        let challenge = try EnrollmentWire.decode(Proof.self, request.response).challenge
        guard proof.credential == request.peerCredential, proof.challenge == challenge,
              proof.transcript == digest(finish) else { throw EnrollmentError.wrongTranscript }
        let peer = try trust.verify(proof.credential, expectedRole: .responder, at: now()).card
        _ = peer // possession proof verified; defer persistent public pin until an authenticated receipt
        peerCredential = proof.credential
        var completed = request; completed.ready = ready; outgoing = completed
    }
}
