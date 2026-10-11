// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "ThroughOriginComparison", platforms: [.macOS(.v15)],
  dependencies: [.package(url: "https://github.com/emmettl/ContinuumKit", exact: "0.1.0-alpha.19")],
  targets: [
    .executableTarget(
      name: "ThroughOriginComparison",
      dependencies: [.product(name: "Numerics", package: "ContinuumKit")])
  ], swiftLanguageModes: [.v6])
