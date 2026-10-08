// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContinuumKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ContinuumKit", targets: ["ContinuumKit"])],
    targets: [.target(name: "ContinuumKit")],
    swiftLanguageModes: [.v6]
)
