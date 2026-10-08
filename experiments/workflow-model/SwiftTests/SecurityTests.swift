import Foundation
import CryptoKit
import Security
import Testing
@testable import RescueDemoState

// Secure synthetic exchange checks. Keys are generated at runtime; no private key material is stored here.

/// Injected record store with failure switches. Holds bytes only in memory.
private final class MemoryRecordStore: SecureRecordStore {
    struct Failure: Error {}
    var data: Data?
    var failRead = false
    var failWrite = false
    private(set) var writes = 0
    init(_ data: Data? = nil) { self.data = data }
    func read() throws -> Data? {
        if failRead { throw Failure() }
        return data
    }
    func write(_ data: Data) throws {
        if failWrite { throw Failure() }
        writes += 1
        self.data = data
    }
}

private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("rescue-secure-\(UUID().uuidString)", isDirectory: true)
}

private func hex(_ text: String) -> Data {
    var data = Data()
    var index = text.startIndex
    while index < text.endIndex {
        let next = text.index(index, offsetBy: 2)
        data.append(UInt8(text[index..<next], radix: 16)!)
        index = next
    }
    return data
}

private func card(_ role: UInt8 = 0, epoch: Data = Data(repeating: 7, count: 16),
                  signing: Data? = nil, agreement: Data? = nil) -> Data {
    Data("ORP1".utf8) + Data([role]) + epoch
        + (signing ?? Curve25519.Signing.PrivateKey().publicKey.rawRepresentation)
        + (agreement ?? Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
}

private func flipped(_ data: Data, at index: Int) -> Data {
    var copy = data
    copy[copy.startIndex + index] ^= 0x01
    return copy
}

@MainActor private struct Pair {
    let root = temporaryRoot()
    let publicStore = MemoryRecordStore()
    let responderStore = MemoryRecordStore()
    let publicUser: SecureEndpointController
    let responder: SecureEndpointController
    init(paired: Bool = true) throws {
        publicUser = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: publicStore)
        responder = try SecureEndpointController(rootURL: root, role: .responder, recordStore: responderStore)
        if paired {
            try publicUser.pair(responder.card.base64)
            try responder.pair(publicUser.card.base64)
        }
    }
}

// MARK: Pairing cards

@Test func runtimeIdentityProducesStrictOpposableCards() throws {
    let publicIdentity = SecureIdentity(role: .publicUser)
    let responderIdentity = SecureIdentity(role: .responder)
    let card = publicIdentity.card
    #expect(card.bytes.count == 85)
    #expect(card.bytes.prefix(4) == Data("ORP1".utf8))
    #expect(card.bytes[4] == 0 && responderIdentity.card.bytes[4] == 1)
    #expect(card.role == .publicUser && responderIdentity.card.role == .responder)
    #expect(card.base64.count == 116)
    #expect(card.fingerprint == SHA256.hash(data: card.bytes).map { String(format: "%02x", $0) }.joined())
    #expect(try SecurePairingCard(base64: card.base64) == card)
    #expect(try SecurePairingCard(bytes: card.bytes) == card)
    // Signing and encryption keys are distinct and fresh per identity.
    #expect(card.bytes[21..<53] != card.bytes[53..<85])
    #expect(SecureIdentity(role: .publicUser).card != card)
    #expect(SecureIdentity(role: .publicUser).card.bytes[5..<21] != card.bytes[5..<21], "Fresh epoch")
}

@Test func malformedCardsAreRejected() throws {
    let valid = card()
    #expect((try? SecurePairingCard(bytes: valid)) != nil)
    let signing = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation
    var lowOrder = Data(count: 32); lowOrder[0] = 1
    let malformed: [Data] = [
        Data(), valid.prefix(84), valid + Data([0]),
        Data("ORP2".utf8) + valid.dropFirst(4),
        card(2), card(255),
        card(signing: Data(count: 32)), card(agreement: Data(count: 32)), card(agreement: lowOrder),
        card(signing: signing, agreement: signing),
    ]
    for bytes in malformed {
        #expect(throws: SecureExchangeError.invalidCard) { _ = try SecurePairingCard(bytes: bytes) }
    }
    let text = try SecurePairingCard(bytes: valid).base64
    var nonCanonical = Array(text)
    // 85 bytes ends in one byte: two symbols plus "==", the last symbol carrying 4 unused bits.
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    let last = nonCanonical.count - 3
    nonCanonical[last] = alphabet[alphabet.firstIndex(of: nonCanonical[last])! ^ 1]
    let malformedText = [
        "", " " + text, text + "\n", String(text.dropLast()), text + "====",
        "-" + text.dropFirst(), "_" + text.dropFirst(), "!" + text.dropFirst(),
        String(nonCanonical), String(repeating: "A", count: 100_000),
        Data(valid.prefix(84)).base64EncodedString(),
    ]
    for value in malformedText {
        #expect(throws: SecureExchangeError.invalidCard) { _ = try SecurePairingCard(base64: value) }
    }
}

@Test func rfc8032Ed25519PublicKnownAnswersVerify() throws {
    // RFC 8032 section 7.1 TEST 1 and TEST 2: public keys and signatures only.
    let vectors: [(String, String, String)] = [
        ("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
         "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
        ("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
         "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
    ]
    for (publicKey, message, signature) in vectors {
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: hex(publicKey))
        #expect(key.isValidSignature(hex(signature), for: hex(message)))
        #expect(!key.isValidSignature(flipped(hex(signature), at: 0), for: hex(message)))
        #expect(!key.isValidSignature(hex(signature), for: hex(message) + Data([0])))
    }
}

// MARK: Envelope

@Test func envelopeRoundTripLayoutAndBounds() throws {
    let publicIdentity = SecureIdentity(role: .publicUser)
    let responderIdentity = SecureIdentity(role: .responder)
    let sender = try SecureEnvelope(identity: publicIdentity, peer: responderIdentity.card)
    let receiver = try SecureEnvelope(identity: responderIdentity, peer: publicIdentity.card)
    #expect(SecureEnvelope.maximumPayload == 4276)

    let plaintext = Data("ORX1 synthetic sample".utf8)
    let packet = try sender.seal(plaintext)
    #expect(packet.count == 100 + plaintext.count + 16 + 64)
    #expect(packet.prefix(4) == Data("ORS1".utf8))
    #expect(packet[4..<36] == Data(SHA256.hash(data: publicIdentity.card.bytes)))
    #expect(packet[36..<68] == Data(SHA256.hash(data: responderIdentity.card.bytes)))
    #expect(packet.range(of: plaintext) == nil, "Body is not readable in transit")
    #expect(try receiver.open(packet) == plaintext)

    // Fresh HPKE context per packet: same plaintext, different encapsulated key and ciphertext.
    let again = try sender.seal(plaintext)
    #expect(again[68..<100] != packet[68..<100])
    #expect(again[100...] != packet[100...])
    #expect(try receiver.open(again) == plaintext)

    // Both directions.
    #expect(try sender.open(try receiver.seal(Data([9]))) == Data([9]))

    // Exact plaintext and packet bounds.
    #expect(try sender.seal(Data([1])).count == 181)
    let largest = try sender.seal(Data(repeating: 0xab, count: 4096))
    #expect(largest.count == 4276)
    #expect(try receiver.open(largest) == Data(repeating: 0xab, count: 4096))
    #expect(throws: SecureExchangeError.payloadSize) { _ = try sender.seal(Data()) }
    #expect(throws: SecureExchangeError.payloadSize) { _ = try sender.seal(Data(count: 4097)) }
    for size in [0, 4, 99, 180, 4277, 70_000] {
        #expect(throws: SecureExchangeError.packetSize) { _ = try receiver.open(Data(count: size)) }
    }
    // Sliced input with a non-zero start index still opens.
    #expect(try receiver.open((Data([0]) + packet).dropFirst()) == plaintext)
}

@Test func everyTamperedRegionIsRejected() throws {
    let publicIdentity = SecureIdentity(role: .publicUser)
    let responderIdentity = SecureIdentity(role: .responder)
    let sender = try SecureEnvelope(identity: publicIdentity, peer: responderIdentity.card)
    let receiver = try SecureEnvelope(identity: responderIdentity, peer: publicIdentity.card)
    let packet = try sender.seal(Data(repeating: 0x42, count: 40))
    // magic, sender pin, recipient pin, encapsulated key, ciphertext, tag, signature
    for index in [0, 3, 4, 35, 36, 67, 68, 99, 100, 139, 140, 155, 156, packet.count - 1] {
        #expect(throws: SecureExchangeError.self) { _ = try receiver.open(flipped(packet, at: index)) }
    }
    #expect(throws: SecureExchangeError.notEnvelope) { _ = try receiver.open(flipped(packet, at: 0)) }
    #expect(throws: SecureExchangeError.wrongSender) { _ = try receiver.open(flipped(packet, at: 4)) }
    #expect(throws: SecureExchangeError.wrongRecipient) { _ = try receiver.open(flipped(packet, at: 36)) }
    for index in [68, 100, 156, packet.count - 1] {
        #expect(throws: SecureExchangeError.badSignature) { _ = try receiver.open(flipped(packet, at: index)) }
    }
    // Truncated or extended within bounds shifts the signature boundary.
    #expect(throws: SecureExchangeError.badSignature) { _ = try receiver.open(packet.dropLast()) }
    #expect(throws: SecureExchangeError.badSignature) { _ = try receiver.open(packet + Data([0])) }
    #expect(throws: SecureExchangeError.packetSize) { _ = try receiver.open(packet.prefix(180)) }
    // Moving bytes between ciphertext and signature changes the signed region.
    #expect(throws: SecureExchangeError.self) { _ = try receiver.open(packet.dropLast(65) + packet.suffix(64)) }
}

@Test func forgedSignatureWithValidHPKEIsRejected() throws {
    let publicIdentity = SecureIdentity(role: .publicUser)
    let responderIdentity = SecureIdentity(role: .responder)
    let attacker = SecureIdentity(role: .publicUser)
    let receiver = try SecureEnvelope(identity: responderIdentity, peer: publicIdentity.card)
    // Attacker knows the responder's public card and seals correctly, then claims the pinned sender.
    var forged = try SecureEnvelope(identity: attacker, peer: responderIdentity.card).seal(Data("ORX1".utf8))
    #expect(throws: SecureExchangeError.wrongSender) { _ = try receiver.open(forged) }
    forged.replaceSubrange(4..<36, with: Data(SHA256.hash(data: publicIdentity.card.bytes)))
    #expect(throws: SecureExchangeError.badSignature) { _ = try receiver.open(forged) }
}

@Test func peerRolesDestinationsAndReflectionArePinned() throws {
    let publicIdentity = SecureIdentity(role: .publicUser)
    let responderIdentity = SecureIdentity(role: .responder)
    let otherResponder = SecureIdentity(role: .responder)
    #expect(throws: SecureExchangeError.wrongRole) { _ = try SecureEnvelope(identity: publicIdentity, peer: SecureIdentity(role: .publicUser).card) }
    #expect(throws: SecureExchangeError.ownCard) { _ = try SecureEnvelope(identity: publicIdentity, peer: publicIdentity.card) }

    let sender = try SecureEnvelope(identity: publicIdentity, peer: responderIdentity.card)
    let packet = try sender.seal(Data([1, 2, 3]))
    // Reflected own packet.
    #expect(throws: SecureExchangeError.reflected) { _ = try sender.open(packet) }
    // Another responder paired with the same public endpoint is not the destination.
    let foreign = try SecureEnvelope(identity: otherResponder, peer: publicIdentity.card)
    #expect(throws: SecureExchangeError.wrongRecipient) { _ = try foreign.open(packet) }
    // A responder pinned to a different public endpoint rejects the sender.
    let elsewhere = try SecureEnvelope(identity: responderIdentity, peer: SecureIdentity(role: .publicUser).card)
    #expect(throws: SecureExchangeError.wrongSender) { _ = try elsewhere.open(packet) }
}

// MARK: Controller over real C++ stores

@Test @MainActor func pairedControllersExchangeEncryptedRequestAndReceipt() throws {
    let pair = try Pair(paired: false)
    #expect(pair.publicUser.peerCard == nil)
    pair.publicUser.endpoint.perform(.sos)
    #expect(throws: SecureExchangeError.notPaired) { _ = try pair.publicUser.nextPacket() }
    #expect(throws: SecureExchangeError.notPaired) { _ = try pair.responder.accept(Data(count: 200)) }
    try pair.publicUser.pair(pair.responder.card.base64)
    try pair.responder.pair(pair.publicUser.card.base64)
    #expect(pair.publicUser.peerCard == pair.responder.card)

    let packet = try #require(try pair.publicUser.nextPacket())
    #expect(packet.prefix(4) == Data("ORS1".utf8))
    #expect(packet.range(of: Data("ORX1".utf8)) == nil)
    let receipt = try pair.responder.accept(packet)
    #expect(receipt.prefix(4) == Data("ORS1".utf8))
    #expect(pair.responder.endpoint.snapshot?.state.hasRequest == true)
    try pair.publicUser.confirm(receipt)
    #expect(pair.publicUser.endpoint.snapshot?.pendingTransfers == 0)
    #expect(pair.publicUser.endpoint.snapshot?.state.originalDelivery == .deviceReceived)

    pair.responder.endpoint.perform(.acknowledge)
    let acknowledgment = try #require(try pair.responder.nextPacket())
    try pair.responder.confirm(try pair.publicUser.accept(acknowledgment))
    #expect(pair.publicUser.endpoint.snapshot?.state.originalDelivery == .humanAcknowledged)
    // Receipts cannot be fed back as requests, nor reflected to the sender.
    #expect(throws: (any Error).self) { _ = try pair.responder.accept(receipt) }
    #expect(throws: SecureExchangeError.reflected) { _ = try pair.publicUser.accept(packet) }
    #expect(pair.publicUser.endpoint.storageURL.path.contains("/secure-public/"))
    #expect(pair.responder.endpoint.storageURL.path.contains("/secure-responder/"))
}

@Test @MainActor func duplicatesRestartAndDroppedReceiptKeepOneHistory() throws {
    let pair = try Pair()
    pair.publicUser.endpoint.perform(.sos)
    let packet = try #require(try pair.publicUser.nextPacket())
    let receipt = try pair.responder.accept(packet)
    let messages = pair.responder.endpoint.snapshot?.state.messages.count
    let receiver = try SecureEnvelope(identity: pair.publicUser.identity, peer: pair.responder.card)
    let plainReceipt = try receiver.open(receipt)

    // Exact duplicate ciphertext is an authenticated retry, not new history.
    let duplicate = try pair.responder.accept(packet)
    #expect(try receiver.open(duplicate) == plainReceipt)
    #expect(duplicate != receipt, "Receipt re-sealed with a fresh context")
    #expect(pair.responder.endpoint.snapshot?.state.messages.count == messages)

    // Receipt dropped; both endpoints restart as new controllers on the same records.
    let publicUser = try SecureEndpointController(rootURL: pair.root, role: .publicUser, recordStore: pair.publicStore)
    let responder = try SecureEndpointController(rootURL: pair.root, role: .responder, recordStore: pair.responderStore)
    #expect(publicUser.card == pair.publicUser.card && publicUser.peerCard == pair.responder.card)
    #expect(responder.peerCard == pair.publicUser.card)
    #expect(publicUser.endpoint.snapshot?.pendingTransfers == 1)
    let retry = try #require(try publicUser.nextPacket())
    #expect(retry != packet, "Retry re-sealed")
    #expect(try SecureEnvelope(identity: responder.identity, peer: publicUser.card).open(retry)
            == SecureEnvelope(identity: pair.responder.identity, peer: pair.publicUser.card).open(packet))
    let retried = try responder.accept(retry)
    #expect(try receiver.open(retried) == plainReceipt)
    #expect(responder.endpoint.snapshot?.state.messages.count == messages)
    try publicUser.confirm(retried)
    #expect(publicUser.endpoint.snapshot?.pendingTransfers == 0)
    // Duplicate receipt confirmation stays harmless.
    try publicUser.confirm(receipt)
    try publicUser.reopen()
    #expect(publicUser.endpoint.snapshot?.state.originalDelivery == .deviceReceived)
}

@Test @MainActor func plainAndWrongRoleAuthorsRejectBeforeTrustedMutation() throws {
    let pair = try Pair()
    // Plain packets have no fallback.
    let plainPublic = EndpointController(storageURL: pair.root.appendingPathComponent("plain-public.sqlite"), role: .publicUser)
    plainPublic.perform(.sos)
    let plain = try #require(try plainPublic.nextPacket())
    #expect(throws: SecureExchangeError.self) { _ = try pair.responder.accept(plain) }
    #expect(pair.responder.endpoint.snapshot?.state.hasRequest == false)

    pair.publicUser.endpoint.perform(.sos)
    let sos = try #require(try pair.publicUser.nextPacket())
    _ = try pair.responder.accept(sos)
    let messages = pair.responder.endpoint.snapshot?.state.messages.count

    // A responder-authored event wrapped by the authenticated public key is still rejected by C++ role checks.
    let opener = try SecureEnvelope(identity: pair.responder.identity, peer: pair.publicUser.card)
    let plainResponder = EndpointController(storageURL: pair.root.appendingPathComponent("plain-responder.sqlite"), role: .responder)
    _ = try plainResponder.accept(try opener.open(sos))
    plainResponder.perform(.acknowledge)
    let responderEvent = try #require(try plainResponder.nextPacket())
    let wrongAuthor = try SecureEnvelope(identity: pair.publicUser.identity, peer: pair.responder.card).seal(responderEvent)
    #expect(throws: EndpointError(code: 3, message: "Rejected: not permitted for this role")) { _ = try pair.responder.accept(wrongAuthor) }
    #expect(pair.responder.endpoint.snapshot?.state.messages.count == messages)
    #expect(pair.responder.endpoint.snapshot?.state.handling == .open)

    // Garbage plaintext under valid keys is rejected by C++ parsing.
    let garbage = try SecureEnvelope(identity: pair.publicUser.identity, peer: pair.responder.card).seal(Data("ORX1".utf8))
    #expect(throws: EndpointError.self) { _ = try pair.responder.accept(garbage) }
    let pending = pair.publicUser.endpoint.snapshot?.pendingTransfers
    #expect(throws: EndpointError.self) { try pair.publicUser.confirm(try SecureEnvelope(identity: pair.responder.identity, peer: pair.publicUser.card).seal(Data([1]))) }
    #expect(pending == 1 && pair.publicUser.endpoint.snapshot?.pendingTransfers == pending)
}

@Test @MainActor func pairingPinsOneOppositePeerUntilReset() throws {
    let pair = try Pair(paired: false)
    let store = pair.publicStore
    let writes = store.writes
    #expect(throws: SecureExchangeError.invalidCard) { try pair.publicUser.pair("not a card") }
    #expect(throws: SecureExchangeError.wrongRole) { try pair.publicUser.pair(SecureIdentity(role: .publicUser).card.base64) }
    #expect(throws: SecureExchangeError.ownCard) { try pair.publicUser.pair(pair.publicUser.card.base64) }
    #expect(store.writes == writes && pair.publicUser.peerCard == nil)

    store.failWrite = true
    #expect(throws: (any Error).self) { try pair.publicUser.pair(pair.responder.card.base64) }
    #expect(pair.publicUser.peerCard == nil, "Failed save does not pin")
    #expect(throws: SecureExchangeError.notPaired) { _ = try pair.publicUser.nextPacket() }
    store.failWrite = false

    try pair.publicUser.pair(pair.responder.card.base64)
    try pair.publicUser.pair(pair.responder.card.base64)
    #expect(pair.publicUser.peerCard == pair.responder.card)
    #expect(throws: SecureExchangeError.peerAlreadyPinned) { try pair.publicUser.pair(SecureIdentity(role: .responder).card.base64) }
    #expect(pair.publicUser.peerCard == pair.responder.card)
}

@Test @MainActor func resetRotatesKeysEpochAndStoreAndRejectsOldEpoch() throws {
    let pair = try Pair()
    pair.publicUser.endpoint.perform(.sos)
    let oldPacket = try #require(try pair.publicUser.nextPacket())
    let oldCard = pair.responder.card
    let oldURL = pair.responder.endpoint.storageURL
    _ = try pair.responder.accept(oldPacket)
    var changes = 0
    pair.responder.endpoint.onChange = { changes += 1 }

    try pair.responder.resetSession()
    #expect(pair.responder.card != oldCard)
    #expect(pair.responder.card.bytes[5..<21] != oldCard.bytes[5..<21])
    #expect(pair.responder.peerCard == nil)
    #expect(pair.responder.endpoint.storageURL != oldURL)
    #expect(pair.responder.endpoint.storageURL.deletingLastPathComponent() == oldURL.deletingLastPathComponent())
    #expect(FileManager.default.fileExists(atPath: oldURL.path), "Old sample database retained")
    #expect(pair.responder.endpoint.snapshot?.state.hasRequest == false)
    #expect(changes > 0, "Change handler carried to the new endpoint")
    #expect(throws: SecureExchangeError.notPaired) { _ = try pair.responder.accept(oldPacket) }

    // Re-pair the same public endpoint: old-epoch ciphertext still rejected.
    try pair.responder.pair(pair.publicUser.card.base64)
    #expect(throws: SecureExchangeError.wrongRecipient) { _ = try pair.responder.accept(oldPacket) }
    #expect(pair.responder.endpoint.snapshot?.state.hasRequest == false)
    // Public side pinned the old responder card; it must also reset before trusting the new one.
    #expect(throws: SecureExchangeError.peerAlreadyPinned) { try pair.publicUser.pair(pair.responder.card.base64) }

    // Restart sees the rotated record.
    let restarted = try SecureEndpointController(rootURL: pair.root, role: .responder, recordStore: pair.responderStore)
    #expect(restarted.card == pair.responder.card && restarted.peerCard == pair.publicUser.card)
    #expect(restarted.endpoint.storageURL == pair.responder.endpoint.storageURL)
}

@Test @MainActor func recordFailuresFailClosedWithoutRegenerating() throws {
    let root = temporaryRoot()
    // Read failure: nothing written, no database created.
    let unreadable = MemoryRecordStore()
    unreadable.failRead = true
    #expect(throws: (any Error).self) { _ = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: unreadable) }
    #expect(unreadable.writes == 0)
    // Write failure on first creation: no database opened under unsaved keys.
    let unwritable = MemoryRecordStore()
    unwritable.failWrite = true
    #expect(throws: (any Error).self) { _ = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: unwritable) }
    let folder = root.appendingPathComponent("secure-public", isDirectory: true)
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty)

    // Corrupt or wrong-role records are errors and are not replaced.
    for bad in [Data("{}".utf8), Data([0xff, 0x00]), Data(count: 4096)] {
        let store = MemoryRecordStore(bad)
        #expect(throws: SecureExchangeError.recordInvalid) { _ = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: store) }
        #expect(store.writes == 0 && store.data == bad)
    }
    let responderStore = MemoryRecordStore()
    _ = try SecureEndpointController(rootURL: temporaryRoot(), role: .responder, recordStore: responderStore)
    let foreign = responderStore.data
    #expect(throws: SecureExchangeError.recordInvalid) { _ = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: MemoryRecordStore(foreign)) }

    // Key loss with existing secure history fails closed and leaves history untouched.
    let store = MemoryRecordStore()
    let original = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: store)
    original.endpoint.perform(.sos)
    let saved = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    #expect(!saved.isEmpty)
    let lost = MemoryRecordStore()
    #expect(throws: SecureExchangeError.recordMissing) { _ = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: lost) }
    #expect(lost.writes == 0 && lost.data == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == saved)
    // The other role's folder is independent.
    #expect((try? SecureEndpointController(rootURL: root, role: .responder, recordStore: MemoryRecordStore())) != nil)
}

@Test @MainActor func failedResetKeepsSessionAndUnavailableStoreKeepsNewKeys() throws {
    let pair = try Pair()
    let card = pair.publicUser.card
    let url = pair.publicUser.endpoint.storageURL
    let record = pair.publicStore.data
    pair.publicStore.failWrite = true
    #expect(throws: (any Error).self) { try pair.publicUser.resetSession() }
    #expect(pair.publicUser.card == card && pair.publicUser.peerCard == pair.responder.card)
    #expect(pair.publicUser.endpoint.storageURL == url && pair.publicStore.data == record)
    pair.publicStore.failWrite = false

    pair.publicStore.failRead = true
    #expect(throws: (any Error).self) { try pair.publicUser.resetSession() }
    #expect(throws: (any Error).self) { try pair.publicUser.pair(pair.responder.card.base64) }
    #expect(pair.publicUser.card == card && pair.publicStore.data == record)
    pair.publicStore.failRead = false

    // New database cannot be created: record and active endpoint both move to the new epoch.
    let folder = url.deletingLastPathComponent()
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }
    try pair.publicUser.resetSession()
    #expect(pair.publicUser.card != card && pair.publicUser.peerCard == nil)
    #expect(pair.publicUser.endpoint.storageURL != url)
    #expect(pair.publicUser.endpoint.snapshot == nil && !pair.publicUser.endpoint.error.isEmpty)
    #expect(throws: (any Error).self) { _ = try pair.publicUser.endpoint.nextPacket() }
    let restarted = try SecureEndpointController(rootURL: pair.root, role: .publicUser, recordStore: pair.publicStore)
    #expect(restarted.card == pair.publicUser.card)
    #expect(restarted.endpoint.storageURL == pair.publicUser.endpoint.storageURL)
}

@Test @MainActor func staleControllersCannotMutateRotatedRecord() throws {
    let root = temporaryRoot()
    let store = MemoryRecordStore()
    let first = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: store)
    let second = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: store)
    #expect(first.card == second.card)
    try first.resetSession()
    let rotated = store.data
    let responder = SecureIdentity(role: .responder).card.base64
    #expect(throws: SecureExchangeError.staleSession) { try second.pair(responder) }
    #expect(throws: SecureExchangeError.staleSession) { try second.resetSession() }
    #expect(throws: SecureExchangeError.staleSession) { try second.reopen() }
    #expect(store.data == rotated && second.peerCard == nil)
    // Pairing through one controller also makes the other stale.
    let third = try SecureEndpointController(rootURL: root, role: .publicUser, recordStore: store)
    try first.pair(responder)
    #expect(throws: SecureExchangeError.staleSession) { try third.pair(responder) }
    try first.reopen()
}

@Test @MainActor func invalidRootIsRejected() {
    #expect(throws: SecureExchangeError.storageLocation) {
        _ = try SecureEndpointController(rootURL: URL(string: "https://example.invalid/root")!, role: .publicUser, recordStore: MemoryRecordStore())
    }
}

// MARK: Production Keychain store

@Test func keychainStoreIsNamespacedAndUpdatesInPlace() throws {
    let root = temporaryRoot()
    let namespace = "keychain-test-\(UUID().uuidString)"
    let publicStore = DefaultKeychainStore(rootURL: root, role: .publicUser, namespace: namespace)
    let responderStore = DefaultKeychainStore(rootURL: root, role: .responder, namespace: namespace)
    let otherRoot = DefaultKeychainStore(rootURL: temporaryRoot(), role: .publicUser, namespace: namespace + "-other")
    defer { try? publicStore.remove(); try? responderStore.remove(); try? otherRoot.remove() }
    #expect(try publicStore.read() == nil)
    // Non-secret random test bytes only.
    let first = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
    let second = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
    try publicStore.write(first)
    #expect(try publicStore.read() == first)
    try publicStore.write(second)
    #expect(try publicStore.read() == second)
    #expect(try responderStore.read() == nil)
    #expect(try otherRoot.read() == nil)
    // Equivalent spellings of the same root share one namespace.
    let respelled = DefaultKeychainStore(rootURL: URL(fileURLWithPath: root.path + "/./"), role: .publicUser, namespace: namespace)
    #expect(try respelled.read() == second)
    try publicStore.remove()
    #expect(try publicStore.read() == nil)
}

@Test @MainActor func oldEpochControllerCannotAcceptOrConfirmAfterAnotherControllerRotates() throws {
    let pair = try Pair()
    pair.publicUser.endpoint.perform(.sos, value: "Synthetic stale session")
    let request = try #require(try pair.publicUser.nextPacket())
    let receipt = try pair.responder.accept(request)
    let currentResponder = try SecureEndpointController(rootURL: pair.root, role: .responder, recordStore: pair.responderStore)
    try currentResponder.resetSession()
    #expect(throws: SecureExchangeError.staleSession) { _ = try pair.responder.accept(request) }
    #expect(throws: SecureExchangeError.staleSession) { _ = try pair.responder.nextPacket() }
    let currentPublic = try SecureEndpointController(rootURL: pair.root, role: .publicUser, recordStore: pair.publicStore)
    try currentPublic.resetSession()
    #expect(throws: SecureExchangeError.staleSession) { try pair.publicUser.confirm(receipt) }
    #expect(pair.publicUser.endpoint.snapshot?.pendingTransfers == 1)
}

#if os(macOS)
@Test func keychainIdentitySurvivesCreationOfItsRootDirectory() throws {
    let root = URL(fileURLWithPath: "/private/tmp/rescue-keychain-mkdir-\(UUID().uuidString)", isDirectory: true)
    let first = DefaultKeychainStore(rootURL: root, role: .publicUser)
    defer { try? first.remove(); try? FileManager.default.removeItem(at: root) }
    let value = Data([1, 2, 3, 4])
    try first.write(value)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let restarted = DefaultKeychainStore(rootURL: root, role: .publicUser)
    #expect(try restarted.read() == value)
}

#endif

@Test @MainActor func logicalKeychainNamespaceKeepsPairingWhenContainerMoves() throws {
    let source = temporaryRoot(), moved = temporaryRoot()
    let namespace = "rescue-container-move-\(UUID().uuidString)"
    let firstStore = DefaultKeychainStore(rootURL: source, role: .publicUser, namespace: namespace)
    defer { try? firstStore.remove(); try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: moved) }
    let before = try SecureEndpointController(rootURL: source, role: .publicUser, recordStore: firstStore)
    try before.pair(SecureIdentity(role: .responder).card.base64)
    before.endpoint.perform(.sos, value: "Synthetic moved container")
    try FileManager.default.copyItem(at: source, to: moved)
    let after = try SecureEndpointController(rootURL: moved, role: .publicUser,
        recordStore: DefaultKeychainStore(rootURL: moved, role: .publicUser, namespace: namespace))
    #expect(after.card == before.card && after.peerCard == before.peerCard)
    #expect(after.endpoint.snapshot?.state.reportedLocation == "Synthetic moved container")
    #expect(after.endpoint.snapshot?.pendingTransfers == 1)
}

// Resource cleanup belongs to test utilities. Query contains names only, never private record data.
private extension DefaultKeychainStore {
    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecureExchangeError.recordStore(status) }
    }
}

@Test @MainActor func survivingKeysCannotSilentlyRecreateMissingPairedHistory() throws {
    let pair = try Pair()
    pair.publicUser.endpoint.perform(.sos, value: "Synthetic prior history")
    let request = try #require(try pair.publicUser.nextPacket())
    _ = try pair.responder.accept(request)
    let originalCard = pair.publicUser.card
    let folder = pair.publicUser.endpoint.storageURL.deletingLastPathComponent()
    try FileManager.default.removeItem(at: folder)
    #expect(throws: (any Error).self) {
        _ = try SecureEndpointController(rootURL: pair.root, role: .publicUser, recordStore: pair.publicStore)
    }
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    #expect(pair.publicUser.card == originalCard)
    #expect(throws: SecureExchangeError.historyMissing) { try pair.publicUser.reopen() }
    #expect(throws: SecureExchangeError.historyMissing) { _ = try pair.publicUser.nextPacket() }
}

@Test @MainActor func explicitRecoveryStartsNewIdentityWithoutReusingLostHistory() throws {
    let pair = try Pair()
    let oldCard = pair.publicUser.card
    try FileManager.default.removeItem(at: pair.publicUser.endpoint.storageURL.deletingLastPathComponent())
    let fresh = try SecureEndpointController.newSession(rootURL: pair.root, role: .publicUser, recordStore: pair.publicStore)
    #expect(fresh.card != oldCard && fresh.peerCard == nil)
    #expect(fresh.endpoint.snapshot?.state.hasRequest == false)
    #expect(throws: SecureExchangeError.staleSession) { _ = try pair.publicUser.nextPacket() }
    let saved = pair.publicStore.data
    pair.publicStore.failRead = true
    #expect(throws: (any Error).self) {
        _ = try SecureEndpointController.newSession(rootURL: pair.root, role: .publicUser, recordStore: pair.publicStore)
    }
    #expect(pair.publicStore.data == saved)
}

@Test @MainActor func localSecureActionsRejectMissingHistoryAndStaleKeys() throws {
    let pair = try Pair()
    #expect(try pair.publicUser.perform(.sos, value: "Synthetic saved request"))
    let pending = pair.publicUser.endpoint.snapshot?.pendingTransfers
    try FileManager.default.removeItem(at: pair.publicUser.endpoint.storageURL.deletingLastPathComponent())
    #expect(throws: SecureExchangeError.historyMissing) { try pair.publicUser.perform(.correction, value: "Must not save") }
    #expect(pair.publicUser.endpoint.snapshot?.pendingTransfers == pending)
    _ = try SecureEndpointController.newSession(rootURL: pair.root, role: .publicUser, recordStore: pair.publicStore)
    #expect(throws: SecureExchangeError.staleSession) { try pair.publicUser.perform(.followUp, value: "Must not save") }
    #expect(pair.publicUser.endpoint.snapshot?.pendingTransfers == pending)
}
