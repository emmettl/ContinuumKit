// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "ContinuumKit",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SceneModel", targets: ["SceneModel"]),
    .library(name: "SceneView", targets: ["SceneView"]),
    .library(name: "SceneRender", targets: ["SceneRender"]),
    .library(name: "GeometryImport", targets: ["GeometryImport"]),
    .library(name: "DocumentKit", targets: ["DocumentKit"]),
    .library(name: "ImpulseResponseKit", targets: ["ImpulseResponseKit"]),
    .library(name: "Thermodynamics", targets: ["Thermodynamics"]),
    .library(name: "CompressibleFlow", targets: ["CompressibleFlow"]),
    .library(name: "LinearAcoustics", targets: ["LinearAcoustics"]),
    .library(name: "LinearAcousticsMetal", targets: ["LinearAcousticsMetal"]),
    .library(name: "SpectralTransforms", targets: ["SpectralTransforms"]),
    .library(name: "BenchmarkSupport", targets: ["BenchmarkSupport"]),
    .executable(name: "continuumbench", targets: ["continuumbench"]),
  ],
  targets: [
    .target(name: "SceneModel"),
    .target(name: "SceneView", dependencies: ["SceneModel"]),
    .target(
      name: "SceneRender", dependencies: ["SceneModel", "SceneView"],
      resources: [.copy("Shaders")]
    ),
    .target(name: "GeometryImport"),
    .target(name: "DocumentKit"),
    .target(name: "ImpulseResponseKit"),
    .target(name: "Thermodynamics"),
    .target(name: "CompressibleFlow"),
    .target(name: "SpectralTransforms"),
    .testTarget(name: "SpectralTransformsTests", dependencies: ["SpectralTransforms"]),
    .testTarget(name: "CompressibleFlowTests", dependencies: ["CompressibleFlow"]),
    .target(name: "LinearAcoustics"),
    .target(name: "LinearAcousticsMetal", dependencies: ["LinearAcoustics"], resources: [.copy("Shaders")]),
    .target(name: "BenchmarkSupport", dependencies: ["Thermodynamics"]),
    .executableTarget(name: "continuumbench", dependencies: ["BenchmarkSupport"]),
    .testTarget(name: "LinearAcousticsMetalTests", dependencies: ["LinearAcousticsMetal", "LinearAcoustics", "BenchmarkSupport"]),
    .testTarget(name: "LinearAcousticsTests", dependencies: ["LinearAcoustics", "BenchmarkSupport"]),
    .testTarget(name: "ThermodynamicsTests", dependencies: ["Thermodynamics"]),
    .testTarget(name: "BenchmarkSupportTests", dependencies: ["BenchmarkSupport"]),
    .testTarget(name: "ImpulseResponseKitTests", dependencies: ["ImpulseResponseKit"]),
    .testTarget(
      name: "CADFoundationsTests",
      dependencies: ["SceneModel", "SceneView", "SceneRender", "GeometryImport", "DocumentKit"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
