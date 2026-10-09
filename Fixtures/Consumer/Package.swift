// swift-tools-version: 6.4
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
guard let sourcePath = environment["CONTINUUMKIT_CONSUMER_SOURCE"],
  let revision = environment["CONTINUUMKIT_CONSUMER_REVISION"]
else {
  fatalError("Run this fixture through Scripts/check-consumer.sh")
}
let source = URL(fileURLWithPath: sourcePath).absoluteString
let version = environment["CONTINUUMKIT_CONSUMER_VERSION"] ?? ""
let dependency: Package.Dependency
if version.isEmpty {
  dependency = .package(url: source, revision: revision)
} else {
  guard let semanticVersion = Version(version) else { fatalError("Invalid semantic version") }
  dependency = .package(url: source, exact: semanticVersion)
}

let package = Package(
  name: "ContinuumConsumer",
  platforms: [.macOS(.v15)],
  dependencies: [dependency],
  targets: [
    .executableTarget(
      name: "Consumer",
      dependencies: [
        .product(name: "SceneModel", package: "continuumkit"),
        .product(name: "SceneView", package: "continuumkit"),
        .product(name: "SceneRender", package: "continuumkit"),
        .product(name: "GeometryImport", package: "continuumkit"),
        .product(name: "DocumentKit", package: "continuumkit"),
        .product(name: "ImpulseResponseKit", package: "continuumkit"),
        .product(name: "Thermodynamics", package: "continuumkit"),
        .product(name: "LinearAcoustics", package: "continuumkit"),
        .product(name: "BenchmarkSupport", package: "continuumkit"),
      ]
    )
  ],
  swiftLanguageModes: [.v6]
)
