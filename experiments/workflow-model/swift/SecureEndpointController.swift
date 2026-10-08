import Foundation
import CryptoKit
import Security

/// Holds one role's private secure record. Implementations must not log, print or write it elsewhere.
public protocol SecureRecordStore {
    /// Saved record, or nil only when none exists. Read failures throw.
    func read() throws -> Data?
    /// Replaces the saved record atomically or throws without partial change.
    func write(_ data: Data) throws
}

/// Keychain-only record: generic password, non-synchronizing, WhenUnlockedThisDeviceOnly.
/// iOS uses a fixed app-scoped namespace plus role; Mac uses a stable canonical root plus role. No Secure Enclave claim.
/// iOS uses the data-protection keychain. macOS deliberately uses the login keychain because unsigned
/// SwiftPM tests and the Mac sample host lack the data-protection entitlement (-34018); that keychain
/// does not enforce the accessibility class. There is no fallback between the two.
public struct DefaultKeychainStore: SecureRecordStore {
    private static let service = "offline-rescue.secure-sample-endpoint"
    private let account: String

    public init(rootURL: URL, role: EndpointRole, namespace: String? = nil) {
        let stableNamespace: String?
        #if os(iOS)
        // Keychain is already app-scoped. Container UUIDs may change on an app update.
        stableNamespace = namespace ?? "native-rescue-v1"
        #else
        stableNamespace = namespace
        #endif
        if let stableNamespace {
            account = SHA256.hash(data: Data((stableNamespace + "\u{0}role=\(role.rawValue)").utf8)).map { String(format: "%02x", $0) }.joined()
            return
        }
        // Resolve the nearest existing ancestor, then append missing components. Foundation's
        // full-path resolution changes when the leaf is created (e.g. /private/tmp -> /tmp).
        var ancestor = rootURL.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            missing.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        var canonical = ancestor.resolvingSymlinksInPath()
        for component in missing.reversed() { canonical.appendPathComponent(component) }
        let root = canonical.path
        let name = Data((root + "\u{0}role=\(role.rawValue)").utf8)
        account = SHA256.hash(data: name).map { String(format: "%02x", $0) }.joined()
    }

    var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    public func read() throws -> Data? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureExchangeError.recordStore(status) }
        guard let data = result as? Data else { throw SecureExchangeError.recordInvalid }
        return data
    }

    public func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
            // Lost a race with another writer: update the item it added.
            if status == errSecDuplicateItem { status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary) }
        }
        guard status == errSecSuccess else { throw SecureExchangeError.recordStore(status) }
    }
}

/// Persisted private record. Validated strictly on load; never replaced on failure.
private struct SecureRecord: Codable {
    static let currentFormat = 1
    var format: Int
    var role: Int
    var epoch: UUID
    var signingKey: Data
    var agreementKey: Data
    var peerCard: Data?

    init(_ identity: SecureIdentity, peer: SecurePairingCard?) {
        format = Self.currentFormat
        role = identity.role.rawValue
        epoch = identity.epoch
        signingKey = identity.signingKey.rawRepresentation
        agreementKey = identity.agreementKey.rawRepresentation
        peerCard = peer?.bytes
    }

    static func decode(_ data: Data, role: EndpointRole) throws -> (SecureIdentity, SecurePairingCard?) {
        guard data.count <= 2048, let record = try? JSONDecoder().decode(Self.self, from: data),
              record.format == currentFormat, record.role == role.rawValue,
              record.signingKey.count == 32, record.agreementKey.count == 32,
              let signing = try? Curve25519.Signing.PrivateKey(rawRepresentation: record.signingKey),
              let agreement = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: record.agreementKey),
              let identity = try? SecureIdentity(role: role, epoch: record.epoch, signingKey: signing, agreementKey: agreement)
        else { throw SecureExchangeError.recordInvalid }
        guard let peerBytes = record.peerCard else { return (identity, nil) }
        guard let peer = try? SecurePairingCard(bytes: peerBytes), (try? SecureEnvelope(identity: identity, peer: peer)) != nil
        else { throw SecureExchangeError.recordInvalid }
        return (identity, peer)
    }

    func encoded() throws -> Data {
        do { return try JSONEncoder().encode(self) } catch { throw SecureExchangeError.recordInvalid }
    }
}

/// One secure sample endpoint: Keychain-held keys and pinned peer, plus a per-epoch C++ store at
/// `rootURL/secure-{public|responder}/{epoch}.sqlite`. Every packet in or out is a sealed ORS1 envelope.
/// Use `.endpoint` for actions and snapshots; `resetSession()` replaces it.
@MainActor public final class SecureEndpointController {
    public let rootURL: URL
    public let role: EndpointRole
    public private(set) var endpoint: EndpointController
    public private(set) var peerCard: SecurePairingCard?
    public var card: SecurePairingCard { identity.card }

    private(set) var identity: SecureIdentity
    private var envelope: SecureEnvelope?
    private let store: any SecureRecordStore
    private let folder: URL
    /// Exactly what this controller last read or wrote; a different saved record makes it stale.
    private var savedRecord: Data

    /// Loads this role's record, or creates one only when no prior secure database exists.
    public init(rootURL: URL, role: EndpointRole, recordStore: (any SecureRecordStore)? = nil) throws {
        try Self.validateRoot(rootURL)
        let folder = rootURL.appendingPathComponent(role == .publicUser ? "secure-public" : "secure-responder", isDirectory: true)
        let store = recordStore ?? DefaultKeychainStore(rootURL: rootURL, role: role)
        let identity: SecureIdentity, peer: SecurePairingCard?, saved: Data
        if let data = try Self.read(store) {
            (identity, peer) = try SecureRecord.decode(data, role: role)
            saved = data
            if peer != nil, !FileManager.default.fileExists(atPath: Self.database(folder, identity.epoch).path) {
                throw SecureExchangeError.historyMissing
            }
        } else {
            guard try Self.isEmpty(folder) else { throw SecureExchangeError.recordMissing }
            identity = SecureIdentity(role: role)
            peer = nil
            saved = try SecureRecord(identity, peer: nil).encoded()
            try Self.write(saved, to: store)
        }
        self.rootURL = rootURL
        self.role = role
        self.folder = folder
        self.store = store
        self.identity = identity
        savedRecord = saved
        peerCard = peer
        envelope = try peer.map { try SecureEnvelope(identity: identity, peer: $0) }
        endpoint = EndpointController(storageURL: Self.database(folder, identity.epoch), role: role)
    }

    /// Explicit recovery rotates identity and preserves previous sample files.
    public static func newSession(rootURL: URL, role: EndpointRole, recordStore: (any SecureRecordStore)? = nil) throws -> SecureEndpointController {
        try validateRoot(rootURL)
        let store = recordStore ?? DefaultKeychainStore(rootURL: rootURL, role: role)
        _ = try read(store) // A locked or inaccessible Keychain is never treated as absent.
        let identity = SecureIdentity(role: role)
        try write(SecureRecord(identity, peer: nil).encoded(), to: store)
        return try SecureEndpointController(rootURL: rootURL, role: role, recordStore: store)
    }

    /// Pins the opposite role's card. An identical repeat is harmless; a different card needs a new session.
    public func pair(_ base64: String) throws {
        let peer = try SecurePairingCard(base64: base64)
        let envelope = try SecureEnvelope(identity: identity, peer: peer)
        try requireCurrent()
        if let peerCard {
            guard peerCard == peer else { throw SecureExchangeError.peerAlreadyPinned }
            return
        }
        let record = try SecureRecord(identity, peer: peer).encoded()
        try Self.write(record, to: store)
        savedRecord = record
        peerCard = peer
        self.envelope = envelope
    }

    /// Rotates keys and epoch, clears trust and opens a fresh database. The new record is saved first;
    /// afterward the active endpoint always belongs to the new epoch, even if its database fails to open.
    /// Earlier sample databases stay on disk, unencrypted by this layer.
    public func resetSession() throws {
        try requireCurrent()
        let fresh = SecureIdentity(role: role)
        let record = try SecureRecord(fresh, peer: nil).encoded()
        try Self.write(record, to: store)
        savedRecord = record
        identity = fresh
        peerCard = nil
        envelope = nil
        let handler = endpoint.onChange
        endpoint = EndpointController(storageURL: Self.database(folder, fresh.epoch), role: role)
        endpoint.onChange = handler
        handler?()
    }

    @discardableResult public func perform(_ action: DemoAction, value: String = "", reference: String = "") throws -> Bool {
        try requireCurrent()
        try requireHistory()
        return endpoint.perform(action, value: value, reference: reference)
    }

    /// Sealed oldest unconfirmed event, or nil when nothing is pending.
    public func nextPacket() throws -> Data? {
        let envelope = try paired()
        return try endpoint.nextPacket().map(envelope.seal)
    }

    /// Opens a sealed event, saves it in C++ and returns the sealed committed receipt.
    public func accept(_ packet: Data) throws -> Data {
        let envelope = try paired()
        return try envelope.seal(try endpoint.accept(try envelope.open(packet)))
    }

    /// Opens a sealed device receipt and confirms the matching pending original.
    public func confirm(_ packet: Data) throws {
        let envelope = try paired()
        try endpoint.confirm(try envelope.open(packet))
    }

    /// Reopens the saved database after checking this controller's keys are still the saved ones.
    public func reopen() throws {
        try requireCurrent()
        try requireHistory()
        endpoint.reopen()
    }

    private func paired() throws -> SecureEnvelope {
        try requireCurrent()
        try requireHistory()
        guard let envelope else { throw SecureExchangeError.notPaired }
        return envelope
    }

    private func requireHistory() throws {
        if peerCard != nil, !FileManager.default.fileExists(atPath: endpoint.storageURL.path) {
            throw SecureExchangeError.historyMissing
        }
    }

    private func requireCurrent() throws {
        guard try Self.read(store) == savedRecord else { throw SecureExchangeError.staleSession }
    }

    private static func validateRoot(_ rootURL: URL) throws {
        guard rootURL.isFileURL, rootURL.path.hasPrefix("/"), !rootURL.path.contains("\0"),
              rootURL.path.utf8.count <= 3800 else { throw SecureExchangeError.storageLocation }
    }

    private static func database(_ folder: URL, _ epoch: UUID) -> URL {
        folder.appendingPathComponent(epoch.uuidString.lowercased() + ".sqlite", isDirectory: false)
    }

    /// True when the secure-role folder is absent or holds nothing but Finder metadata.
    private static func isEmpty(_ folder: URL) throws -> Bool {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { $0 == ".DS_Store" }
        } catch CocoaError.fileReadNoSuchFile {
            return true
        } catch {
            throw SecureExchangeError.storageLocation
        }
    }

    private static func read(_ store: any SecureRecordStore) throws -> Data? {
        do { return try store.read() }
        catch let error as SecureExchangeError { throw error }
        catch { throw SecureExchangeError.recordStore(-1) }
    }

    private static func write(_ data: Data, to store: any SecureRecordStore) throws {
        do { try store.write(data) }
        catch let error as SecureExchangeError { throw error }
        catch { throw SecureExchangeError.recordStore(-1) }
    }
}
