// swift-tools-version: 6.4
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
guard let source = environment["CONTINUUMKIT_CONSUMER_SOURCE"],
  let revision = environment["CONTINUUMKIT_CONSUMER_REVISION"]
else {
  fatalError("Run Scripts/check-metal-wave-consumer.sh")
}
let package = Package(
  name: "WaveConsumer", platforms: [.macOS(.v15)],
  dependencies: [.package(url: URL(fileURLWithPath: source).absoluteString, revision: revision)],
  targets: [
    .executableTarget(
      name: "WaveConsumer",
      dependencies: [
        .product(name: "LinearAcoustics", package: "continuumkit"),
        .product(name: "LinearAcousticsMetal", package: "continuumkit"),
      ])
  ], swiftLanguageModes: [.v6])
