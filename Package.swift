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
    .library(name: "SolidMechanics", targets: ["SolidMechanics"]),
    .library(name: "ContactSearch", targets: ["ContactSearch"]),
    .library(name: "ContactSearchMetal", targets: ["ContactSearchMetal"]),
    .library(name: "Numerics", targets: ["Numerics"]),
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
    .target(name: "SolidMechanics"),
    .testTarget(name: "SolidMechanicsTests", dependencies: ["SolidMechanics"], resources: [.copy("Fixtures")]),
    .target(name: "ContactSearch"),
    .testTarget(name: "ContactSearchTests", dependencies: ["ContactSearch"]),
    .target(name: "ContactSearchMetal", dependencies: ["ContactSearch"], resources: [.copy("Shaders")]),
    .testTarget(name: "ContactSearchMetalTests", dependencies: ["ContactSearchMetal", "ContactSearch"]),
    .target(name: "Numerics"),
    .testTarget(name: "NumericsTests", dependencies: ["Numerics"]),
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

// Apple's simd and Accelerate modules do not exist on Linux. There, Sources/LinuxSIMD and
// Sources/LinuxAccelerate stand in under the same module names, so the frozen SolidMechanics
// and SpectralTransforms sources build unchanged. Apple platforms never build either.
// Every target that imports simd or tests `canImport(simd)` depends on the stand-in, so that
// test gives the same answer whatever order the targets are built in.
#if os(Linux)
  package.targets += [
    .target(name: "simd", path: "Sources/LinuxSIMD"),
    .target(name: "Accelerate", path: "Sources/LinuxAccelerate"),
  ]
  let simdUsers: Set<String> = [
    "SceneModel", "SceneView", "GeometryImport", "CompressibleFlow", "CompressibleFlowTests",
    "Numerics", "NumericsTests", "SolidMechanics", "SolidMechanicsTests",
  ]
  for target in package.targets {
    if simdUsers.contains(target.name) { target.dependencies.append("simd") }
    if target.name == "SpectralTransforms" { target.dependencies.append("Accelerate") }
  }
  // Metal and AppKit cannot build on Linux, so `swift test` there covers the CPU libraries only.
  // CADFoundationsTests goes too, because it tests SceneRender alongside the portable targets.
  let appleOnly: Set<String> = [
    "SceneRender", "ContactSearchMetal", "ContactSearchMetalTests", "LinearAcousticsMetal",
    "LinearAcousticsMetalTests", "CADFoundationsTests",
  ]
  package.targets.removeAll { appleOnly.contains($0.name) }
  package.products.removeAll { appleOnly.contains($0.name) }
#endif
