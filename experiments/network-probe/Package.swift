// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "RescueNetworkProbe",
    platforms: [.macOS(.v14), .iOS(.v18)],
    products: [.library(name: "ProbeTransport", targets: ["ProbeTransport"]),
               .executable(name: "rescue-probe-host", targets: ["ProbeHost"])],
    targets: [.target(name: "ProbeWire", publicHeadersPath: "include"),
              .target(name: "ProbeTransport", dependencies: ["ProbeWire"]),
              .executableTarget(name: "ProbeHost", dependencies: ["ProbeTransport"]),
              .testTarget(name: "ProbeTests", dependencies: ["ProbeTransport", "ProbeWire"])],
    cxxLanguageStandard: .cxx20)
