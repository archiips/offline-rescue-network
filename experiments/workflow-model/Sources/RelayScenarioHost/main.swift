import Foundation
import RescueDemoState

// Runs the process-local encrypted relay custody scenario in a fresh temporary root, then deletes it.
// Contacts are simulated calls in one process; this proves no radio, socket or device isolation.
@MainActor func runRelayScenario() -> Int32 {
    guard CommandLine.arguments.count == 1 else {
        print("Usage: rescue-relay-scenario")
        return 2
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-relay-scenario-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    do {
        let facts = try RelayScenario.run(root: root)
        for fact in facts { print("PASS \(fact.name): \(fact.detail)") }
        print("RELAY SCENARIO COMPLETE \(facts.count) facts; synthetic data, process-local contacts, no radio or socket isolation")
        return 0
    } catch {
        print("RELAY SCENARIO FAILED: \(error)")
        return 1
    }
}

let status = MainActor.assumeIsolated { runRelayScenario() }
exit(status)
