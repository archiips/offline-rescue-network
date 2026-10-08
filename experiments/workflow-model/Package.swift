// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RescueWorkflowDemo",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "RescueDemoState", targets: ["RescueDemoState"]), .executable(name: "rescue-exchange-host", targets: ["ExchangeHost"]), .executable(name: "rescue-secure-host", targets: ["SecureHost"])],
    targets: [
        .target(name: "RescueDemoBridge", path: ".", exclude: ["CMakeLists.txt", "README.md", "src/demo.cpp", "tests", "swift", "SwiftTests", "Sources"],
                sources: ["src/workflow.cpp", "bridge/workflow_bridge.cpp", "bridge/session_store.cpp", "bridge/endpoint.cpp", "bridge/event_wire.cpp"], publicHeadersPath: "bridge/include", cxxSettings: [.headerSearchPath("include")], linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "RescueDemoState", dependencies: ["RescueDemoBridge"], path: "swift"),
        .executableTarget(name: "ExchangeHost", dependencies: ["RescueDemoState"], path: "Sources/ExchangeHost"),
        .executableTarget(name: "SecureHost", dependencies: ["RescueDemoState"], path: "Sources/SecureHost"),
        .testTarget(name: "RescueDemoStateTests", dependencies: ["RescueDemoState"], path: "SwiftTests")
    ], cxxLanguageStandard: .cxx20)
