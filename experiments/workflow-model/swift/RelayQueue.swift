import Foundation
import RescueDemoBridge

public enum RelayPriority: Int32, Sendable { case ordinary = 0, urgent = 1 }
public enum RelayAdmission: Sendable { case admitted, duplicate }

/// Owned copy of one selected custody item. Payload is the opaque sealed packet, byte for byte.
public struct RelayItem: Equatable, Sendable {
    public let id: String
    public let flow: String
    public let priority: RelayPriority
    /// Caller logical time, not a production clock.
    public let expiry: Int64
    /// Stored hop budget minus this forward.
    public let remainingHops: Int
    public let attempts: Int
    public let payload: Data
}

public struct RelayError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Matches rc_relay_result; `nullHandle` also covers bridge failures before the queue decided.
    public enum Code: Int32, Sendable { case nullHandle = -1, invalid = 2, conflict = 5, capacity = 6, storage = 7 }
    public let code: Code
    public let message: String
    public var description: String { message }
}

/// Thin owner of one C++ relay handle. Trusted local callers only; no listener, keys or plaintext.
/// Removing an item is a caller decision after validating the destination receipt; the queue checks no proof.
@MainActor public final class RelayQueue {
    public let storageURL: URL
    nonisolated(unsafe) private let handle: OpaquePointer

    public init(storageURL: URL) throws {
        let path = storageURL.path
        guard storageURL.isFileURL, path.hasPrefix("/"), !storageURL.hasDirectoryPath,
              path.utf8.count <= 4096, !path.contains("\0") else {
            throw RelayError(code: .invalid, message: "Relay storage must be a local file path")
        }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw RelayError(code: .storage, message: "Relay storage folder unavailable: \(error.localizedDescription)")
        }
        guard let handle = rc_relay_open(path) else {
            throw RelayError(code: .storage, message: "Relay store could not be opened; existing data was not replaced")
        }
        self.storageURL = storageURL
        self.handle = handle
    }
    deinit { rc_relay_destroy(handle) }

    public func enqueue(id: String, flow: String, priority: RelayPriority, expiry: Int64, hops: Int,
                        payload: Data, now: Int64) throws -> RelayAdmission {
        guard !id.contains("\0"), !flow.contains("\0"), let hops = Int32(exactly: hops) else { throw Self.error(RC_RELAY_INVALID) }
        let result = payload.withUnsafeBytes { raw in
            rc_relay_enqueue(handle, id, flow, priority.rawValue, expiry, hops,
                             raw.bindMemory(to: UInt8.self).baseAddress, raw.count, now)
        }
        switch result {
        case RC_RELAY_OK: return .admitted
        case RC_RELAY_DUPLICATE: return .duplicate
        default: throw Self.error(result)
        }
    }

    /// Next eligible item, or nil when none is eligible. Attempts are committed before this returns.
    public func select(now: Int64) throws -> RelayItem? {
        var raw: UnsafeMutablePointer<rc_relay_item>?
        let result = rc_relay_select(handle, now, &raw)
        defer { rc_relay_item_free(raw) }
        if result == RC_RELAY_EMPTY { return nil }
        guard result == RC_RELAY_OK else { throw Self.error(result) }
        guard let item = raw?.pointee, let priority = RelayPriority(rawValue: Int32(item.urgency)),
              let payload = item.payload, item.length > 0 else {
            throw RelayError(code: .nullHandle, message: "Relay returned an unreadable item")
        }
        return RelayItem(id: Self.string(item.id), flow: Self.string(item.flow), priority: priority, expiry: item.expiry,
                         remainingHops: Int(item.remaining_hops), attempts: Int(item.attempts),
                         payload: Data(bytes: payload, count: item.length))
    }

    /// Returns false when the ID is not retained.
    @discardableResult public func remove(id: String) throws -> Bool {
        guard !id.contains("\0") else { throw Self.error(RC_RELAY_INVALID) }
        let result = rc_relay_remove(handle, id)
        if result == RC_RELAY_EMPTY { return false }
        guard result == RC_RELAY_OK else { throw Self.error(result) }
        return true
    }

    public func count() throws -> Int {
        var value = 0
        let result = rc_relay_count(handle, &value)
        guard result == RC_RELAY_OK else { throw Self.error(result) }
        return value
    }

    private static func string<T>(_ tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
    }
    private static func error(_ result: rc_relay_result) -> RelayError {
        let code = RelayError.Code(rawValue: result.rawValue) ?? .nullHandle
        let message = switch code {
        case .invalid: "Rejected invalid relay item or argument"
        case .conflict: "Rejected: a different item already uses this relay ID"
        case .capacity: "Relay queue full; nothing was evicted"
        case .storage: "Relay save or validation failed; nothing changed"
        case .nullHandle: "Relay bridge failure (\(result.rawValue))"
        }
        return RelayError(code: code, message: message)
    }
}
