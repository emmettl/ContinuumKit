// swift-tools-version: 6.4
import Foundation
import PackageDescription

let env = ProcessInfo.processInfo.environment
let package = Package(
  name: "MetalWaveThroughput", platforms: [.macOS(.v15)],
  dependencies: [
    .package(
      url: env["CONTINUUMKIT_CONSUMER_SOURCE"]!, revision: env["CONTINUUMKIT_CONSUMER_REVISION"]!)
  ],
  targets: [
    .target(
      name: "ProfiledMetal",
      dependencies: [.product(name: "LinearAcoustics", package: "continuumkit")],
      resources: [.copy("Shaders")]),
    .executableTarget(
      name: "MetalWaveThroughput",
      dependencies: [
        "ProfiledMetal", .product(name: "LinearAcoustics", package: "continuumkit"),
        .product(name: "LinearAcousticsMetal", package: "continuumkit"),
      ]),
  ], swiftLanguageModes: [.v6])
