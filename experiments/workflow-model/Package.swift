// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RescueWorkflowDemo",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "RescueDemoState", targets: ["RescueDemoState"])],
    targets: [
        .target(name: "RescueDemoBridge", path: ".", exclude: ["CMakeLists.txt", "README.md", "src/demo.cpp", "tests", "swift", "SwiftTests"],
                sources: ["src/workflow.cpp", "bridge/workflow_bridge.cpp"], publicHeadersPath: "bridge/include", cxxSettings: [.headerSearchPath("include")]),
        .target(name: "RescueDemoState", dependencies: ["RescueDemoBridge"], path: "swift"),
        .testTarget(name: "RescueDemoStateTests", dependencies: ["RescueDemoState"], path: "SwiftTests")
    ], cxxLanguageStandard: .cxx20)
