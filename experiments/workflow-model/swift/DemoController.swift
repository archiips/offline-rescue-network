import Foundation
import Combine
import RescueDemoBridge

private final class CoreHandle {
    let pointer: OpaquePointer?
    init() { pointer = rc_create() }
    deinit { rc_destroy(pointer) }
}
@MainActor public final class DemoController: ObservableObject {
    private var core = CoreHandle()
    @Published public private(set) var snapshot: DemoSnapshot?
    @Published public private(set) var error = ""
    public init() { refresh() }
    public func perform(_ action: DemoAction, value: String = "", reference: String = "") {
        let result = rc_perform(core.pointer, Int32(action.rawValue), value, reference)
        refresh()
        if result != 0 && result != 1 && error.isEmpty { error = "Action rejected (\(result)). Check the current request state." }
    }
    public func setConnected(_ connected: Bool) {
        let result = rc_set_connected(core.pointer, connected ? 1 : 0)
        refresh()
        if result != 0 && error.isEmpty { error = "Could not change the simulated connection." }
    }
    public func reset() { core = CoreHandle(); refresh() }
    private func refresh() {
        guard let data = rc_snapshot(core.pointer) else { snapshot = nil; error = "Could not read demo state."; return }
        defer { rc_free(data) }
        do { snapshot = try JSONDecoder().decode(DemoSnapshot.self, from: Data(String(cString: data).utf8)); error = snapshot?.error ?? "" }
        catch { snapshot = nil; self.error = "Could not decode demo state." }
    }
}
