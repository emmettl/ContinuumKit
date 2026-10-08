import CoreGraphics
import DocumentKit
import Foundation
import GeometryImport
import Metal
import SceneModel
import SceneRender
import SceneView
import simd

@main
enum Consumer {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw NSError(domain: "ContinuumConsumer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor
    static func main() throws {
        let savedBounds = Data(#"{"min":[1,2,3],"max":[5,8,10]}"#.utf8)
        let box = try JSONDecoder().decode(Box.self, from: savedBounds)
        try require(box.size == SIMD3<Float>(4, 6, 7), "Saved bounds changed")
        let roundTrip = try JSONDecoder().decode(Box.self, from: JSONEncoder().encode(box))
        try require(roundTrip == box, "Bounds round trip changed")
        let grid = Grid(nx: 7, ny: 5, nz: 3, cellSize: 0.25)
        let cell = grid.cell(containing: grid.cellCentre(3, 2, 1))
        try require(cell == (3, 2, 1) && grid.index(3, 2, 1) == 52, "Grid indexing changed")
        let framed = OrbitCamera.framing(box)
        let ray = framed.ray(ndc: .zero, aspectRatio: 4 / 3)
        try require(simd_length(simd_cross(ray.direction, simd_normalize(box.min + box.size / 2 - ray.origin))) < 1e-6,
                    "Centre camera ray misses its target")
        print("PASS SceneModel / SceneView public contracts")

        let obj = Data("o Room\ng Floor\nusemtl Blue\nv 0 0 0\nv 4 0 0\nv 4 3 0\nv 0 3 0\nf 1 2 3 4\n".utf8)
        let mesh = try MeshFile(data: obj, fileExtension: "obj")
        try require(mesh.vertices.count == 4 && mesh.faces == [
            .init(corners: [0, 1, 2, 3], object: "Room", group: "Floor", material: "Blue")
        ], "OBJ grouping or geometry changed")
        print("PASS GeometryImport public contract")

        let asset = ProjectManifest.Asset(path: "assets/floor.obj", data: obj)
        let original = try ProjectArchive(
            manifest: ProjectManifest(documentType: "consumer", producer: "ContinuumKit fixture", assets: [asset]),
            files: ["scene.json": savedBounds, "settings.json": Data("{}".utf8), asset.path: obj]
        )
        try require(original.manifest.format == "dev.simulationkit.project", "Archive format identifier changed")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let location = folder.appendingPathComponent("fixture.project")
        try original.fileWrapper().write(to: location, options: .atomic, originalContentsURL: nil)
        let reopened = try ProjectArchive.read(from: location)
        try require(reopened == original, "Archive identity or embedded asset changed")
        print("PASS DocumentKit disk round trip and retained format")

        var scene = SceneGeometry()
        scene.addPolygon([[0, 0, 0], [4, 0, 0], [4, 3, 0], [0, 3, 0]],
                         colour: SIMD4(0.2, 0.4, 0.9, 1), pick: 0)
        try require(scene.pick(origin: [2, 1.5, 10], direction: [0, 0, -1]) == 0, "Scene picking changed")
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "ContinuumConsumer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Offscreen consumer requires Metal"])
        }
        // Constructing the renderer resolves Scene.metal through the fetched package's Bundle.module.
        let renderer = try MeshRenderer(device: device)
        renderer.setGeometry(scene)
        let camera = OrbitCamera(target: [2, 1.5, 0], distance: 9, azimuth: -2.2, elevation: 0.7)
        func pixel() throws -> SIMD3<Float> {
            guard let image = try renderer.snapshot(commandQueue: queue, width: 64, height: 48, camera: camera),
                  let data = image.dataProvider?.data as Data? else {
                throw NSError(domain: "ContinuumConsumer", code: 3)
            }
            try require(image.width == 64 && image.height == 48, "Snapshot dimensions changed")
            let offset = 24 * image.bytesPerRow + 32 * 4
            return SIMD3(Float(data[offset + 2]), Float(data[offset + 1]), Float(data[offset])) / 255
        }
        let plain = try pixel()
        try require(plain.z > plain.x + 0.2, "Fetched renderer did not draw the blue floor")
        renderer.highlighted = 0
        let highlighted = try pixel()
        try require(highlighted.x > plain.x + 0.2, "Fetched renderer highlight changed")
        print("PASS SceneRender fetched shader, picking and offscreen pixels on \(device.name)")
        print("ContinuumKit clean Git consumer passed.")
    }
}
