// swift-tools-version: 6.4
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
guard let source = environment["CONTINUUMKIT_CONSUMER_SOURCE"],
  let revision = environment["CONTINUUMKIT_CONSUMER_REVISION"]
else {
  fatalError("Run Scripts/check-contact-search-consumer.sh")
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
  name: "ContactSearchConsumer", platforms: [.macOS(.v15)],
  dependencies: [dependency],
  targets: [
    .executableTarget(
      name: "ContactSearchConsumer",
      dependencies: [.product(name: "ContactSearch", package: "continuumkit")]),
    .executableTarget(
      name: "ContactSearchMetalConsumer",
      dependencies: [
        .product(name: "ContactSearch", package: "continuumkit"),
        .product(name: "ContactSearchMetal", package: "continuumkit"),
      ]),
  ], swiftLanguageModes: [.v6])
