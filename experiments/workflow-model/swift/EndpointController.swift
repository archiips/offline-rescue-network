import Foundation
import Combine
import RescueDemoBridge

/// Fixture role for one local endpoint. Not an authenticated identity.
public enum EndpointRole: Int, Sendable { case publicUser = 0, responder = 1 }
public struct EndpointSnapshot: Decodable, Sendable {
    public let role: String
    public let pendingTransfers: Int
    public let error: String
    public let state: DeviceSnapshot
}
public struct EndpointError: Error, Equatable, Sendable {
    /// Bridge result code; -1 when the failure occurred before the C++ endpoint decided.
    public let code: Int32
    public let message: String
    public init(code: Int32 = -1, message: String) { self.code = code; self.message = message }
}

/// One independently saved sample endpoint. Owns its C++ handle; all calls serialize on MainActor.
@MainActor public final class EndpointController: ObservableObject {
    @Published public private(set) var snapshot: EndpointSnapshot?
    @Published public private(set) var error = ""
    /// Invoked after every refresh, including failed operations.
    public var onChange: (() -> Void)?
    public let storageURL: URL
    public let role: EndpointRole
    private let storageBinding: String?
    nonisolated(unsafe) private var handle: OpaquePointer?

    public init(storageURL: URL, role: EndpointRole, storageBinding: String? = nil) {
        self.storageURL = storageURL
        self.role = role
        self.storageBinding = storageBinding
        open()
    }
    deinit { if let handle { rc_endpoint_destroy(handle) } }

    @discardableResult
    public func perform(_ action: DemoAction, value: String = "", reference: String = "") -> Bool {
        var failure: String?
        if let handle {
            if value.contains("\0") || reference.contains("\0") {
                failure = "Rejected text containing NUL"
            } else {
                let code = rc_endpoint_perform(handle, Int32(action.rawValue), value, reference)
                if code != 0 && code != 1 { failure = Self.describe(code) }
            }
        } else { failure = Self.unavailable }
        refresh(failure)
        return failure == nil
    }
    /// Clears only this endpoint's saved exchange; the peer must reset separately.
    public func reset() {
        guard let handle else { refresh(Self.unavailable); return }
        let code = rc_endpoint_reset(handle)
        refresh(code == 0 ? nil : Self.describe(code))
    }
    /// Closes and reopens the saved store, as after a process restart.
    public func reopen() {
        if let handle { rc_endpoint_destroy(handle) }
        handle = nil
        open()
    }
    /// Oldest unconfirmed outgoing event, or nil when nothing is pending.
    public func nextPacket() throws -> Data? {
        guard let handle else { throw fail(-1, Self.unavailable) }
        var length = 0
        guard let bytes = rc_endpoint_next(handle, &length) else {
            if length != 0 || (snapshot?.pendingTransfers ?? 0) > 0 { throw fail(-1, "Pending transfer unavailable") }
            return nil
        }
        defer { rc_free(bytes) }
        guard length > 0 else { throw fail(-1, "Pending transfer was empty") }
        return Data(bytes: bytes, count: length)
    }
    /// Saves an incoming event and returns the committed device receipt for the sender.
    public func accept(_ packet: Data) throws -> Data {
        guard let handle else { throw fail(-1, Self.unavailable) }
        var receipt: UnsafeMutablePointer<UInt8>?
        var length = 0
        let code = packet.withUnsafeBytes { raw in
            rc_endpoint_accept(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &receipt, &length)
        }
        defer { if let receipt { rc_free(receipt) } }
        guard code == 0 || code == 1 else { throw fail(code, Self.describe(code)) }
        guard let receipt, length > 0 else { throw fail(-1, "Saved event returned no receipt") }
        let result = Data(bytes: receipt, count: length)
        refresh(nil)
        return result
    }
    /// Records a peer's device receipt and removes the matching pending original.
    public func confirm(_ receipt: Data) throws {
        guard let handle else { throw fail(-1, Self.unavailable) }
        let code = receipt.withUnsafeBytes { raw in
            rc_endpoint_confirm(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
        }
        guard code == 0 || code == 1 else { throw fail(code, Self.describe(code)) }
        refresh(nil)
    }

    /// Original event only when this exact receipt is already committed. Read-only; used to correlate
    /// a late relay receipt after Direct already confirmed it, without trusting a relay's claimed ID.
    public func confirmedOriginal(for receipt: Data) throws -> Data? {
        guard let handle else { throw EndpointError(message: Self.unavailable) }
        var length = 0
        let bytes = receipt.withUnsafeBytes { raw in
            rc_endpoint_confirmed_original(handle, raw.bindMemory(to: UInt8.self).baseAddress, raw.count, &length)
        }
        guard let bytes else {
            guard length == 0 else { throw EndpointError(message: "Saved receipt lookup failed") }
            return nil
        }
        defer { rc_free(bytes) }
        return Data(bytes: bytes, count: length)
    }

    private static let unavailable = "Local exchange storage unavailable"
    private static func describe(_ code: Int32) -> String {
        switch code {
        case 2: "Rejected invalid sample packet"
        case 3: "Rejected: not permitted for this role"
        case 4: "Rejected: earlier message missing"
        case 5: "Rejected: conflicts with saved state"
        case 6: "Rejected: local storage full"
        case 7: "Local save failed; nothing changed"
        default: "Local exchange bridge failure (\(code))"
        }
    }
    private func fail(_ code: Int32, _ message: String) -> EndpointError {
        refresh(message)
        return EndpointError(code: code, message: message)
    }
    private func open() {
        let url = storageURL
        guard url.isFileURL, url.path.hasPrefix("/"), !url.hasDirectoryPath,
              url.path.utf8.count <= 4096, !url.path.contains("\0") else {
            refresh("Storage location must be a local file path"); return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            refresh("Storage folder unavailable: \(error.localizedDescription)"); return
        }
        if let storageBinding {
            guard !storageBinding.isEmpty, storageBinding.utf8.count <= 256, !storageBinding.contains("\0") else {
                refresh("Invalid storage conversation binding"); return
            }
            handle = rc_endpoint_open_bound(url.path, Int32(role.rawValue), storageBinding)
        } else {
            handle = rc_endpoint_open(url.path, Int32(role.rawValue))
        }
        refresh(handle == nil ? "Saved exchange could not be opened; existing data was not replaced" : nil)
    }
    private func refresh(_ failure: String?) {
        var message = failure
        if let handle, let json = rc_endpoint_snapshot(handle) {
            defer { rc_free(json) }
            do {
                snapshot = try JSONDecoder().decode(EndpointSnapshot.self, from: Data(String(cString: json).utf8))
            } catch {
                snapshot = nil
                message = message ?? "Saved exchange state unreadable"
            }
        } else {
            snapshot = nil
            if handle != nil { message = message ?? "Saved exchange state unavailable" }
        }
        error = message ?? snapshot?.error ?? ""
        onChange?()
    }
}
