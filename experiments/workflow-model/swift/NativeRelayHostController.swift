import Foundation
import Combine
import CryptoKit
@preconcurrency import Network

/// Foreground host for one sample relay between exactly two pinned opposite-role public cards. Holds no endpoint
/// keys or plaintext and never touches endpoint stores; delivery facts come only from signed destination
/// acceptances inside RelayService.
///
/// Files under `rootURL` (public metadata and opaque custody only):
/// - `<id>.json`: version 1 profile holding the two public cards; `id` is SHA-256 over a domain and both card digests.
/// - `<id>.sqlite`: that pair's C++ relay queue.
/// - `active.json`: atomic pointer to the selected profile.
/// A pair always maps to the same profile, so switching pairs keeps every earlier queue. A missing, corrupt or
/// symlinked profile, pointer or queue fails closed; nothing is recreated, adopted or deleted. Never auto-starts.
@MainActor public final class NativeRelayHostController: ObservableObject {
    public let rootURL: URL
    public let transport = LocalExchangeTransport(relayTimeout: .seconds(8))
    @Published public private(set) var error = ""
    @Published public private(set) var status = "Relay not configured"
    @Published public private(set) var configured = false
    @Published public private(set) var custodyCount = 0
    @Published public private(set) var flushBusy = false
    @Published public private(set) var publicCard: SecurePairingCard?
    @Published public private(set) var responderCard: SecurePairingCard?
    private var service: RelayService?
    private var generation = UUID()

    private struct Failure: Error, CustomStringConvertible { let description: String }
    private struct Profile: Codable { let version: Int; let publicCard: String; let responderCard: String }
    private struct Pointer: Codable { let version: Int; let profile: String }
    private static let pointerName = "active.json"
    private static let maximumFile = 4096

    public init(rootURL: URL) {
        self.rootURL = rootURL
        do {
            guard Self.validRoot(rootURL) else { throw Failure(description: "Relay storage must be a local folder") }
            guard try Self.directoryExists(rootURL) else { return }
            let pointerURL = rootURL.appendingPathComponent(Self.pointerName)
            guard try Self.regularFile(pointerURL) else {
                let saved = try FileManager.default.contentsOfDirectory(atPath: rootURL.path)
                    .filter { $0.hasSuffix(".json") || $0.contains(".sqlite") }
                guard saved.isEmpty else {
                    throw Failure(description: "Saved relay profiles exist but the active selection is missing; enter both cards to reopen one")
                }
                return
            }
            let pointer = try JSONDecoder().decode(Pointer.self, from: Self.read(pointerURL))
            guard pointer.version == 1, Self.validID(pointer.profile) else { throw Failure(description: "Active relay selection is unreadable") }
            let (cards, url) = try Self.existingProfile(pointer.profile, in: rootURL)
            try open(url, cards)
        } catch {
            fail("Saved relay configuration unavailable; nothing was recreated or removed. \(error)")
        }
    }

    /// Deterministic profile name for one public/responder card pair.
    static func profileID(publicCard: SecurePairingCard, responderCard: SecurePairingCard) -> String {
        RelayEndpointController.hex(Data(SHA256.hash(data: Data("offline-rescue/relay-host/profile/v1".utf8) + Data([0])
                                                      + publicCard.digest + responderCard.digest)))
    }

    /// Selects the profile for this pair, creating it only when neither its profile nor its queue exists.
    /// An invalid draft changes nothing; any later failure leaves the host unconfigured.
    @discardableResult public func configure(publicCard publicText: String, responderCard responderText: String) -> Bool {
        guard Self.validRoot(rootURL) else { error = "Relay storage must be a local folder"; return false }
        guard !flushBusy else { error = "Wait for the current forward to finish before changing the relay pair."; return false }
        let cards: (SecurePairingCard, SecurePairingCard)
        do {
            let p = try SecurePairingCard(base64: publicText.trimmingCharacters(in: .whitespacesAndNewlines))
            let r = try SecurePairingCard(base64: responderText.trimmingCharacters(in: .whitespacesAndNewlines))
            guard p.role == .publicUser, r.role == .responder else { throw RelayProtocolError.unknownPeer }
            cards = (p, r)
        } catch {
            self.error = "Cards rejected: enter one public card and one responder card. "
                + (configured ? "The current relay pair is unchanged." : "Relay is not configured.")
            return false
        }
        stop()
        service = nil; configured = false; self.publicCard = nil; self.responderCard = nil; custodyCount = 0
        let id = Self.profileID(publicCard: cards.0, responderCard: cards.1)
        let profileURL = rootURL.appendingPathComponent("\(id).json"), queueURL = rootURL.appendingPathComponent("\(id).sqlite")
        do {
            guard rootURL.isFileURL, rootURL.path.hasPrefix("/") else { throw Failure(description: "Relay storage must be a local folder") }
            if try !Self.directoryExists(rootURL) {
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            }
            if try Self.exists(profileURL) {
                let (saved, url) = try Self.existingProfile(id, in: rootURL)
                guard saved == cards else { throw Failure(description: "Saved profile does not match these cards") }
                try open(url, saved)
            } else {
                let leftovers = try FileManager.default.contentsOfDirectory(atPath: rootURL.path).filter { $0.hasPrefix("\(id).sqlite") }
                guard leftovers.isEmpty else { throw Failure(description: "A relay queue exists without its profile; it was not adopted") }
                // Store first, then profile: a failure between them leaves an orphan queue that later fails closed.
                let created = try RelayService(storageURL: queueURL, publicCard: cards.0, responderCard: cards.1)
                let profile = Profile(version: 1, publicCard: cards.0.base64, responderCard: cards.1.base64)
                try Self.encode(profile).write(to: profileURL, options: .withoutOverwriting)
                try open(created, cards)
            }
            try Self.encode(Pointer(version: 1, profile: id)).write(to: rootURL.appendingPathComponent(Self.pointerName), options: .atomic)
            error = ""
            status = "Relay pair saved; stopped with \(custodyCount) held. Not forwarding."
            return true
        } catch {
            fail("Relay configuration failed; saved relay files were kept unchanged. \(error)")
            return false
        }
    }

    /// Manual listener only: no advertising or browsing.
    public func start(port: UInt16? = nil) {
        guard configured, let service else { error = "Configure the relay pair first."; return }
        stop()
        let run = generation
        transport.onIncoming = { [weak self] bytes in
            guard let self, self.generation == run, self.service === service, self.transport.active else {
                throw Failure(description: "Relay host stopped")
            }
            let custody = try service.admit(bytes)
            self.refreshCount()
            self.status = "Holding \(self.custodyCount) in relay custody; not yet delivered."
            return custody
        }
        do {
            try transport.start(name: "RescueRelayHost", advertise: false, browse: false, port: port)
            error = ""
            status = "Relay start requested; see connection status. Forwarding is manual. Holding \(custodyCount)."
        } catch {
            transport.onIncoming = nil
            self.error = "Could not start relay host: \(error)"
        }
    }

    /// Fences callbacks, then closes sockets. Custody stays saved; an in-flight forward keeps `flushBusy` until it ends.
    public func stop() {
        generation = UUID()
        transport.onIncoming = nil
        transport.stop()
        if configured { status = "Stopped; \(custodyCount) held in relay custody. Not forwarding." }
    }

    /// Forwards one held item to its pinned destination's manual address. The item leaves custody only after
    /// RelayService validates a signed destination acceptance received while this run is still active.
    public func flushOne(publicHost: String, publicPort: String, responderHost: String, responderPort: String) async {
        guard !flushBusy else { error = "A forward is already in progress."; return }
        guard let publicContact = Self.contact(host: publicHost, port: publicPort),
              let responderContact = Self.contact(host: responderHost, port: responderPort) else {
            error = "Enter a host and a port from 1 to 65535 for both devices."; return
        }
        guard configured, let service, transport.active else { error = "Start the relay host first."; return }
        let run = generation, channel = transport
        flushBusy = true; error = ""
        defer { flushBusy = false }
        let outcome: RelayFlushOutcome
        do {
            outcome = try await service.flush { [weak self] bytes, role in
                guard let self, self.generation == run, self.service === service, channel.active else { throw Failure(description: "Relay host stopped") }
                let response = try await channel.exchange(bytes, to: role == .publicUser ? publicContact : responderContact)
                // Stop may land after the response but before this resumes; RelayService must then keep custody.
                guard self.generation == run, self.service === service, channel.active else { throw Failure(description: "Relay host stopped") }
                return response
            }
        } catch {
            if self.service === service { refreshCount() }
            if run == generation { self.error = "Forward unavailable; held messages stay in relay custody. \(error)" }
            return
        }
        if self.service === service { refreshCount() }
        guard run == generation else { return } // stopped: never publish a stale result
        switch outcome {
        case .empty: status = "Nothing held to forward."
        case .delivered(_, _, let returned):
            status = "Destination device accepted one held message; removed from relay custody."
                + (returned == nil ? "" : " Its device receipt is now held for the sender.")
                + " Holding \(custodyCount)."
        case .failed(_, _, let reason):
            error = "Not accepted by the destination; the message stays in relay custody for a later manual retry. \(reason)"
            status = "Holding \(custodyCount) in relay custody."
        case .dropped: status = "Response ignored; holding \(custodyCount) in relay custody."
        }
    }

    // MARK: Profile files

    private func open(_ url: URL, _ cards: (SecurePairingCard, SecurePairingCard)) throws {
        try open(RelayService(storageURL: url, publicCard: cards.0, responderCard: cards.1), cards)
    }

    private func open(_ opened: RelayService, _ cards: (SecurePairingCard, SecurePairingCard)) throws {
        let count = try opened.count()
        service = opened; publicCard = cards.0; responderCard = cards.1; custodyCount = count; configured = true
        status = "Stopped; \(count) held in relay custody. Not forwarding."
    }

    private func fail(_ message: String) {
        service = nil; configured = false; publicCard = nil; responderCard = nil; custodyCount = 0
        error = message
        status = "Relay not configured"
    }

    private func refreshCount() {
        guard let service else { return }
        do { custodyCount = try service.count() } catch { self.error = "Relay custody count unavailable: \(error)" }
    }

    /// Validated cards and queue URL for a saved profile whose queue already exists.
    private static func existingProfile(_ id: String, in root: URL) throws -> ((SecurePairingCard, SecurePairingCard), URL) {
        let profileURL = root.appendingPathComponent("\(id).json"), queueURL = root.appendingPathComponent("\(id).sqlite")
        guard try regularFile(profileURL) else { throw Failure(description: "Relay profile is missing or not a regular file") }
        let profile: Profile
        do { profile = try JSONDecoder().decode(Profile.self, from: read(profileURL)) }
        catch { throw Failure(description: "Relay profile is unreadable") }
        guard profile.version == 1, let p = try? SecurePairingCard(base64: profile.publicCard),
              let r = try? SecurePairingCard(base64: profile.responderCard), p.role == .publicUser, r.role == .responder,
              profileID(publicCard: p, responderCard: r) == id else { throw Failure(description: "Relay profile does not match its name") }
        guard try regularFile(queueURL), let size = try FileManager.default.attributesOfItem(atPath: queueURL.path)[.size] as? Int,
              size > 0 else { throw Failure(description: "Relay queue for this profile is missing; it was not recreated") }
        return ((p, r), queueURL)
    }

    /// Strict manual contact, matching the endpoint relay-upload policy.
    private static func contact(host: String, port: String) -> NWEndpoint? {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, host.utf8.count <= 253,
              !host.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !port.isEmpty, port.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = UInt16(port), number > 0, let value = NWEndpoint.Port(rawValue: number) else { return nil }
        return .hostPort(host: NWEndpoint.Host(host), port: value)
    }

    private static func validRoot(_ root: URL) -> Bool {
        root.isFileURL && root.path.hasPrefix("/") && root.path.utf8.count <= 4096 && !root.path.contains("\0")
    }

    private static func validID(_ id: String) -> Bool {
        id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    /// Does not follow a final symlink: anything other than a plain file is refused.
    private static func regularFile(_ url: URL) throws -> Bool {
        guard try exists(url) else { return false }
        guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
            throw Failure(description: "\(url.lastPathComponent) is not a regular file")
        }
        return true
    }

    private static func directoryExists(_ url: URL) throws -> Bool {
        guard try exists(url) else { return false }
        guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeDirectory else {
            throw Failure(description: "Relay storage is not a plain folder")
        }
        return true
    }

    /// True for any entry, including a dangling symlink.
    private static func exists(_ url: URL) throws -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maximumFile + 1) ?? Data()
        guard data.count <= maximumFile else { throw Failure(description: "\(url.lastPathComponent) is too large") }
        return data
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }
}
