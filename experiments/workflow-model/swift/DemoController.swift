import Foundation
import Combine
import RescueDemoBridge

private final class CoreHandle {
    let pointer: OpaquePointer?
    init(storageURL: URL?) {
        if let storageURL { pointer = rc_open(storageURL.path) }
        else { pointer = rc_create() }
    }
    deinit { rc_destroy(pointer) }
}
@MainActor public final class DemoController: ObservableObject {
    private let storageURL: URL?
    private var core: CoreHandle?
    @Published public private(set) var snapshot: DemoSnapshot?
    @Published public private(set) var error = ""
    public init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        retrySavedSession()
    }
    public func retrySavedSession() {
        if storageURL == nil, core?.pointer != nil { refresh(); return }
        core = nil
        do {
            if let storageURL {
                guard storageURL.isFileURL else { throw URLError(.badURL) }
                try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            core = CoreHandle(storageURL: storageURL)
            refresh()
        } catch {
            snapshot = nil
            self.error = "Could not access the saved sample session. Retry when storage is available."
        }
    }
    public func perform(_ action: DemoAction, value: String = "", reference: String = "") {
        let result = rc_perform(core?.pointer, Int32(action.rawValue), value, reference)
        refresh()
        if result != 0 && result != 1 && error.isEmpty { error = "Action was not saved (\(result)). Check the current request state." }
    }
    public func setConnected(_ connected: Bool) {
        let result = rc_set_connected(core?.pointer, connected ? 1 : 0)
        refresh()
        if result != 0 && error.isEmpty { error = "Could not save the simulated connection change." }
    }
    public func reset() {
        let result = rc_reset(core?.pointer)
        refresh()
        if result != 0 && error.isEmpty { error = "Could not reset the sample session. Previous data is retained." }
    }
    private func refresh() {
        guard let pointer = core?.pointer else {
            snapshot = nil
            error = storageURL == nil ? "Could not start the sample session." : "Could not open the saved sample session. The file has been preserved."
            return
        }
        guard let data = rc_snapshot(pointer) else { snapshot = nil; error = "Could not read demo state."; return }
        defer { rc_free(data) }
        do { snapshot = try JSONDecoder().decode(DemoSnapshot.self, from: Data(String(cString: data).utf8)); error = snapshot?.error ?? "" }
        catch { snapshot = nil; self.error = "Could not decode demo state." }
    }
}
