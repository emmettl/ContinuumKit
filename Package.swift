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
        .testTarget(
            name: "CADFoundationsTests",
            dependencies: ["SceneModel", "SceneView", "SceneRender", "GeometryImport", "DocumentKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
