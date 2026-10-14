// swift-tools-version: 6.4
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
guard let source = environment["CONTINUUMKIT_CONSUMER_SOURCE"],
  let revision = environment["CONTINUUMKIT_CONSUMER_REVISION"]
else {
  fatalError("Run Scripts/check-isotropic-tet-consumer.sh")
}
let version = environment["CONTINUUMKIT_CONSUMER_VERSION"] ?? ""
let dependency: Package.Dependency
if version.isEmpty {
  dependency = .package(url: URL(fileURLWithPath: source).absoluteString, revision: revision)
} else {
  guard let semanticVersion = Version(version) else { fatalError("Invalid semantic version") }
  dependency = .package(url: URL(fileURLWithPath: source).absoluteString, exact: semanticVersion)
}
let package = Package(
  name: "IsotropicTetConsumer", platforms: [.macOS(.v15)],
  dependencies: [dependency],
  targets: [
    .target(name: "FrozenTet"),
    .executableTarget(
      name: "IsotropicTetConsumer",
      dependencies: [
        .product(name: "SolidMechanics", package: "continuumkit"), "FrozenTet"
      ])
  ], swiftLanguageModes: [.v6])
