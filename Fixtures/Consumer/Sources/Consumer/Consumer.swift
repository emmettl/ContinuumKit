import BenchmarkSupport
import CoreGraphics
import DocumentKit
import Foundation
import GeometryImport
import ImpulseResponseKit
import LinearAcoustics
import LinearAcousticsMetal
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
    let isolatedMask: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]
    var waveFaces = [Float](repeating: -1, count: 48)
    for side in 0..<6 { waveFaces[side * 8] = 0 }
    let waveGrid = try PreparedWaveGrid(
      dimensions: [2, 2, 2], spacing: [1, 1, 1],
      soundSpeed: 1, density: 1, timeStep: 0.125, activeCells: isolatedMask,
      boundaryTerms: waveFaces)
    let waveZero = [Float](repeating: 0, count: 8)
    let wave = try CPUWaveStepper(
      grid: waveGrid,
      initialFields: WaveInitialFields(
        pressureOverDensity: [1, 100, 100, 100, 100, 100, 100, 100], velocityX: waveZero,
        velocityY: waveZero, velocityZ: waveZero))
    try wave.advance(steps: 3)
    try require(
      try wave.snapshot().pressureOverDensity == [1, 100, 100, 100, 100, 100, 100, 100],
      "Fetched rigid wave changed")
    print("PASS LinearAcoustics public product")
    guard let waveDevice = MTLCreateSystemDefaultDevice() else {
      throw NSError(domain: "ContinuumConsumer", code: 2)
    }
    let gpuWave = try MetalWaveStepper(
      device: waveDevice, grid: waveGrid,
      initialFields: WaveInitialFields(
        pressureOverDensity: [1, 100, 100, 100, 100, 100, 100, 100], velocityX: waveZero,
        velocityY: waveZero, velocityZ: waveZero))
    try gpuWave.advance(steps: 3)
    try require(
      try gpuWave.snapshot().pressureOverDensity == [1, 100, 100, 100, 100, 100, 100, 100],
      "Fetched Metal wave changed")
    print("PASS LinearAcousticsMetal packaged kernels")

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
    let diagonal = try RigidModeCase.standard()[0]
    let quarter = diagonal.state([0.03125, 0.03125, 0.03125], time: diagonal.duration / 4)
    try require(
      quarter.dropFirst().allSatisfy { abs($0 - 1 / (sqrt(24.0) * 400)) < 1e-14 },
      "Fetched 3D velocity contract failed")
    let volumeResolution = RigidModeResolution(axis: "time", nx: 8, ny: 4, nz: 4, steps: 64)
    let volumeHistory = RigidModeOracle.history(diagonal, volumeResolution)
    try require(
      volumeHistory.frames.count == 9 && volumeHistory.frames[0].w.count == 160,
      "Fetched native z-face history failed")
    print("PASS fetched three-dimensional rigid-mode reference and native z faces")
    let obliqueCase = try ObliqueModeCase(id: "consumer", impedance: 3)
    let oblique = try ObliqueModeReference(obliqueCase)
    let wall = oblique.state(x: 0.25, y: 0.03125, time: oblique.duration / 4)
    try require(
      abs(wall.p - 1200 * wall.u) < 1e-12,
      "Fetched oblique wall condition failed")
    try require(
      abs(oblique.reflection.real - 0.36160025261824914) < 1e-12,
      "Fetched complex reflection failed")
    print("PASS fetched damped oblique mode and complex reflection reference")
    let masked = try MaskedModeCase.standard()[1]
    let maskedResolution = MaskedModeResolution(axis: "time", nx: 16, ny: 8, nz: 8, steps: 64)
    let maskedGrid = try MaskedGrid(masked, maskedResolution)
    precondition(maskedGrid.labels.filter { $0 >= 0 }.count == 360)
    precondition(maskedGrid.label([7, 3, 3]) == -1)
    let maskedHistory = try MaskedModeOracle.history(masked, maskedResolution)
    precondition(maskedHistory.frames[0].p[0] == 100)
    precondition(maskedHistory.frames[0].w.count == 16 * 8 * 9)
    print("PASS fetched masked-domain occupancy and native fields")
    let cylinder = CylinderCase()
    try require(
      abs(cylinder.energy / 1.0935127186193479175e-9 - 1) < 1e-14, "Fetched cylinder energy failed")
    let graph = try MaskedLattice(
      dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3)
    let graphQuarter = try graph.evolve([1, -1, 0], time: Double.pi / (6 * sqrt(2)))
    try require(abs(graphQuarter[2] - sqrt(2)) < 1e-14, "Fetched masked graph oscillator failed")
    let wallCalibration = AdmittanceCase(kind: .cylinder)
    try require(
      abs(wallCalibration.sideArea - 0.07363107781851078) < 1e-15, "Fetched wall area failed")
    let auditResolution = AdmittanceResolution(axis: "space", nx: 16, courant: 0.2)
    let wallHistory = try AdmittanceOracle.reference(wallCalibration, auditResolution)
    let wallAudit = try AdmittanceResult.evaluate(
      model: "consumer", c: wallCalibration, r: auditResolution,
      environment: BenchmarkEnvironment(
        repository: "consumer", revision: "test", sourceHashes: [:], hardware: "test",
        toolchain: "test", operatingSystem: "test"), h: wallHistory, runtime: 0, reference: true)
    try require(wallAudit.physicalStatus == "gap", "Fetched geometry gap was concealed")
    let absorbing = try AbsorbingCylinderReference(AbsorbingCylinderCase())
    try require(
      abs(absorbing.root.real - 3.821751618059804487) < 1e-13, "Fetched Robin Bessel root failed")
    try require(
      abs(
        (absorbing.energy(time: absorbing.duration) + absorbing.dissipated(time: absorbing.duration))
          / absorbing.energy(time: 0) - 1) < 1e-13, "Fetched coupled wall energy failed")
    let damped = try MaskedLattice(
      dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3, wallRates: [2, 2])
    let decay = try damped.evolve([1, 1, 0], time: 0.3)
    try require(abs(decay[0] - exp(-0.6)) < 1e-14 && decay[2] == 0, "Fetched damped graph failed")
    let tilted = TiltedPulseCase()
    try require(
      abs(tilted.reflection - 0.4570059441936298) < 1e-15, "Fetched tilted reflection failed")
    try require(tilted.travel < tilted.cornerArrivalTravel, "Fetched plane region is not causal")
    try require(
      abs(
        tilted.patchWork(time: tilted.duration) / tilted.patchEnergy
          - (1 - tilted.reflection * tilted.reflection)) < 1e-13, "Fetched tilted patch work failed"
    )
    print("ContinuumKit clean Git consumer passed.")
  }
}
