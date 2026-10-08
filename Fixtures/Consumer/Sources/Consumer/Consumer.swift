import BenchmarkSupport
import CoreGraphics
import DocumentKit
import Foundation
import GeometryImport
import ImpulseResponseKit
import Metal
import SceneModel
import SceneRender
import SceneView
import Thermodynamics
import simd

@main
enum Consumer {
  static func require(_ condition: Bool, _ message: String) throws {
    if !condition {
      throw NSError(
        domain: "ContinuumConsumer", code: 1,
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
    try require(
      box.intersection(origin: [0, 4, 5], direction: [10, 0, 0], parameters: 0...1) == 0.1...0.5,
      "Fetched segment query changed its entry or exit")
    try require(
      box.intersection(origin: [0, 8, 10], direction: [1, 0, 0]) == 1...5,
      "Fetched ray query changed its closed-boundary convention")
    let grid = Grid(nx: 7, ny: 5, nz: 3, cellSize: 0.25)
    let cell = grid.cell(containing: grid.cellCentre(3, 2, 1))
    try require(cell == (3, 2, 1) && grid.index(3, 2, 1) == 52, "Grid indexing changed")
    let framed = OrbitCamera.framing(box)
    let ray = framed.ray(ndc: .zero, aspectRatio: 4 / 3)
    try require(
      simd_length(simd_cross(ray.direction, simd_normalize(box.min + box.size / 2 - ray.origin)))
        < 1e-6,
      "Centre camera ray misses its target")
    print("PASS SceneModel / SceneView public contracts")

    let obj = Data(
      "o Room\ng Floor\nusemtl Blue\nv 0 0 0\nv 4 0 0\nv 4 3 0\nv 0 3 0\nf 1 2 3 4\n".utf8)
    let mesh = try MeshFile(data: obj, fileExtension: "obj")
    try require(
      mesh.vertices.count == 4
        && mesh.faces == [
          .init(corners: [0, 1, 2, 3], object: "Room", group: "Floor", material: "Blue")
        ], "OBJ grouping or geometry changed")
    print("PASS GeometryImport public contract")

    let asset = ProjectManifest.Asset(path: "assets/floor.obj", data: obj)
    let original = try ProjectArchive(
      manifest: ProjectManifest(
        documentType: "consumer", producer: "ContinuumKit fixture", assets: [asset]),
      files: ["scene.json": savedBounds, "settings.json": Data("{}".utf8), asset.path: obj]
    )
    try require(
      original.manifest.format == "dev.simulationkit.project", "Archive format identifier changed")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let location = folder.appendingPathComponent("fixture.project")
    try original.fileWrapper().write(to: location, options: .atomic, originalContentsURL: nil)
    let reopened = try ProjectArchive.read(from: location)
    try require(reopened == original, "Archive identity or embedded asset changed")
    print("PASS DocumentKit disk round trip and retained format")

    let sourceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let receiverID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let metadata = ResponseMetadata(
      sampleRate: 48_000, frameCount: 4,
      channels: (0..<2).map {
        .init(name: "Path \($0)", sourceID: sourceID, receiverID: receiverID)
      },
      content: .reflectionsOnly, gainConvention: "Pressure relative to source",
      usableBand: .init(lowerHz: 20, upperHz: 20_000), model: "Consumer fixture",
      assumptions: ["Synthetic response"], generator: "ContinuumKit consumer")
    var response = try ImpulseResponse(
      channels: [[0, 0, 0.5, 0], [0, 0, -0.25, 0.125]], metadata: metadata)
    try response.applyCommonGain(2, detail: "Fixture gain")
    try response.removeLeadingFrames(2)
    try require(
      response.channels == [[1, 0], [-0.5, 0.25]] && response.metadata.emissionFrame == -2,
      "Response gain, channel ratios or emission timing changed")
    let responseURL = folder.appendingPathComponent("response.wav")
    try response.write(wav: responseURL)
    try require(
      try ImpulseResponse.read(wav: responseURL) == response,
      "Response samples or metadata changed during disk round trip")
    try require(
      response.metadata.format == "dev.roomcad.impulse-response",
      "Response format identifier changed")
    print("PASS ImpulseResponseKit fetched product, conditioning and WAV/JSON disk round trip")

    var scene = SceneGeometry()
    scene.addPolygon(
      [[0, 0, 0], [4, 0, 0], [4, 3, 0], [0, 3, 0]],
      colour: SIMD4(0.2, 0.4, 0.9, 1), pick: 0)
    try require(
      scene.pick(origin: [2, 1.5, 10], direction: [0, 0, -1]) == 0, "Scene picking changed")
    guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
      throw NSError(
        domain: "ContinuumConsumer", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Offscreen consumer requires Metal"])
    }
    // Constructing the renderer resolves Scene.metal through the fetched package's Bundle.module.
    let renderer = try MeshRenderer(device: device)
    renderer.setGeometry(scene)
    let camera = OrbitCamera(target: [2, 1.5, 0], distance: 9, azimuth: -2.2, elevation: 0.7)
    func pixel() throws -> SIMD3<Float> {
      guard
        let image = renderer.snapshot(commandQueue: queue, width: 64, height: 48, camera: camera),
        let data = image.dataProvider?.data as Data?
      else {
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
    let reservoir = try AdiabaticReservoir(
      referenceVolume: 2, referenceEnergy: 5, heatCapacityRatio: 2)
    let expanded = try reservoir.state(atVolume: 4)
    try require(
      expanded.energy == 2.5 && expanded.pressure == 0.625, "Reservoir golden state changed")
    try require(
      abs(try reservoir.work(fromVolume: 2, toVolume: 4) - 2.5) < 1e-14, "Signed work changed")
    let specification = try AdiabaticCase.standard()[0]
    let metadataEnvironment = BenchmarkEnvironment(
      repository: "consumer", revision: "fixture", sourceHashes: [:],
      hardware: device.name, toolchain: "consumer", operatingSystem: "macOS")
    let series = try AdiabaticBenchmark.resolutions.map { steps in
      try AdiabaticResult.evaluate(
        model: "consumer", caseSpecification: specification,
        environment: metadataEnvironment, steps: steps, runtimeS: 0,
        samples: AdiabaticBenchmark.reservoirSamples(caseSpecification: specification, steps: steps)
      )
    }
    _ = try AdiabaticBenchmark.checkRefinement(series, metric: "work", expectedOrder: 1.8...2.2)
    let savedResult = try JSONEncoder().encode(series.last!)
    let openedResult = try JSONDecoder().decode(AdiabaticResult.self, from: savedResult)
    try require(
      openedResult.caseSpecification == specification && openedResult.schemaVersion == 1,
      "Benchmark result contract changed")
    print("PASS Thermodynamics / BenchmarkSupport fetched public APIs and work refinement")
    let acousticWall = try AcousticCase.standard()[1]
    let reflectedPressure = AcousticOracle.continuum(
      acousticWall, xM: acousticWall.lengthM, timeS: acousticWall.wallHitTimeS)
    precondition(
      abs(reflectedPressure.pressurePa - 2) < 1e-14 && reflectedPressure.velocityMps == 0)
    let lattice = try AcousticOracle.SpatialLattice(
      acousticWall, cells: 192, spacingM: acousticWall.lengthM / 192)
    precondition(lattice.fields(timeS: 0).pressurePa.count == 192)
    print("PASS fetched acoustic reference contract, positive pressure image and fixed-lattice API")
    let impedance = try BoundaryAcousticCase(id: "consumer", kind: .impedancePulse, impedance: 3)
    try require(impedance.reflection == 0.5, "Fetched impedance golden failed")
    print("ContinuumKit clean Git consumer passed.")
  }
}
