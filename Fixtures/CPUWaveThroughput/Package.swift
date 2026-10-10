// swift-tools-version: 6.4
import Foundation
import PackageDescription

let env = ProcessInfo.processInfo.environment
let package = Package(
  name: "CPUWaveThroughput", platforms: [.macOS(.v15)],
  dependencies: [
    .package(
      url: env["CONTINUUMKIT_CONSUMER_SOURCE"]!, revision: env["CONTINUUMKIT_CONSUMER_REVISION"]!)
  ],
  targets: [
    .executableTarget(
      name: "CPUWaveThroughput",
      dependencies: [.product(name: "LinearAcoustics", package: "continuumkit")])
  ],
  swiftLanguageModes: [.v6])
