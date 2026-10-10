import Foundation
import LinearAcoustics
import LinearAcousticsMetal
import Metal

@testable import ProfiledMetal

enum Failure: Error { case invalid(String) }
func require(_ b: Bool, _ s: String) throws { if !b { throw Failure.invalid(s) } }
func seconds(_ start: ContinuousClock.Instant) -> Double {
  let d = start.duration(to: ContinuousClock().now).components
  return Double(d.seconds) + Double(d.attoseconds) / 1e18
}
func fieldBits(_ s: WaveSnapshot) -> [[UInt32]] {
  [s.pressureOverDensity, s.velocityX, s.velocityY, s.velocityZ].map { $0.map(\.bitPattern) }
}
func frameBits(_ f: WaveObservationFrame) -> [UInt64] {
  f.pressureOverDensity.map(\.bitPattern) + f.projectedVelocity.map { $0?.bitPattern ?? UInt64.max }
}
func faces(_ d: SIMD3<Int>, _ mask: [UInt8], _ loss: Float) -> [Float] {
  let n = mask.count
  let strides = [1, d.x, d.x * d.y]
  var result = [Float](repeating: -1, count: 6 * n)
  for at in 0..<n where mask[at] == 1 {
    let xyz = [at % d.x, at / d.x % d.y, at / (d.x * d.y)]
    for side in 0..<6 {
      let axis = side / 2
      let plus = side % 2 == 1
      let inside = plus ? xyz[axis] + 1 < d[axis] : xyz[axis] > 0
      let adjacent = at + (plus ? strides[axis] : -strides[axis])
      result[side * n + at] = inside && mask[adjacent] == 1 ? -1 : loss
    }
  }
  return result
}
struct Run: Encodable {
  let mode: String, repetition: Int, fieldFile: String
  let clock: Int, wallSeconds, setupSeconds, advanceSeconds, mixingSeconds: Double
  let decodeSeconds: Double?
  let commands: [ProfileCommand]?
  let frameIndices: [Int]
  let frames: [[UInt64]], mixed: [[UInt64]]
}
struct Case: Encodable {
  let frequency, timeStep, speed: Double
  let dimensions: [Int], spacing: [Double], sourceCells: [Int], sourceCoefficients: [Float],
    amplitudes: [Float]
  let inside: [UInt8], faces: [Float], initialFieldFile: String, pressureCells: [[Int]],
    pressureWeights: [[Float]], velocityCells: [Int?], axes: [[Double]?]
  let maximumThreads: Int
  let runs: [Run]
}
struct Report: Encodable {
  let candidate, device: String
  let registryID: UInt64
  let cases: [Case]
  let handOracle: [[UInt32]]
}
@main struct Main {
  static func writeFields(_ fields: [[UInt32]], _ name: String, _ output: URL) throws {
    let words = fields.flatMap { $0.map(\.littleEndian) }
    try words.withUnsafeBytes { try Data($0).write(to: output.appendingPathComponent(name)) }
  }
  static func main() throws {
    guard let flag = CommandLine.arguments.firstIndex(of: "--output"),
      flag + 1 < CommandLine.arguments.count, let device = MTLCreateSystemDefaultDevice()
    else { throw Failure.invalid("device/output") }
    let output = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let baselineContext = try LinearAcousticsMetal.MetalWaveContext(device: device)
    let profileContext = try ProfiledMetal.MetalWaveContext(device: device)
    // Independent two-cell signed forcing oracle, with inactive pressure slots retained.
    let mask: [UInt8] = [1, 1, 0, 0, 0, 0, 0, 0]
    let handGrid = try PreparedWaveGrid(
      dimensions: [2, 2, 2], spacing: [1, 1, 1], soundSpeed: 1, density: 1, timeStep: 0.125,
      activeCells: mask, boundaryTerms: faces([2, 2, 2], mask, 0))
    let handFields = WaveInitialFields(
      pressureOverDensity: [1, 0, 100, 100, 100, 100, 100, 100],
      velocityX: Array(repeating: 0, count: 8), velocityY: Array(repeating: 0, count: 8),
      velocityZ: Array(repeating: 0, count: 8))
    let handSource = try PreparedPressureSource(
      grid: handGrid, cellIndices: [1], coefficients: [0.5])
    let expected: [[Float]] = [
      [0.96923828125, 0.53076171875, 100, 100, 100, 100, 100, 100],
      [0.12109375, 0, 0, 0, 0, 0, 0, 0], Array(repeating: 0, count: 8),
      Array(repeating: 0, count: 8),
    ]
    for group in [SIMD3<Int>(32, 1, 1), SIMD3<Int>(32, 4, 2)] {
      let hand = try ProfiledMetal.MetalWaveStepper(
        context: profileContext, grid: handGrid, initialFields: handFields)
      hand.profileGroup = group
      try hand.advance(source: hand.prepareSource(handSource), amplitudes: [2, -1])
      try require(
        fieldBits(hand.snapshot()) == expected.map { $0.map(\.bitPattern) },
        "independent forcing oracle")
    }
    var cases: [Case] = []
    for frequency in [100.0, 200.0, 450.0] {
      let speed = 331.3 * sqrt((20 + 273.15) / 273.15)
      let size = SIMD3<Double>(8, 6, 3)
      let d = SIMD3<Int>(
        Int(ceil(size.x / (speed / (frequency * 10)))),
        Int(ceil(size.y / (speed / (frequency * 10)))),
        Int(ceil(size.z / (speed / (frequency * 10)))))
      let h = size / SIMD3<Double>(Double(d.x), Double(d.y), Double(d.z))
      let limit = 0.95 / (speed * sqrt(1 / (h.x * h.x) + 1 / (h.y * h.y) + 1 / (h.z * h.z)))
      var decimation = 1
      while Double(2 * decimation) / 48000 <= limit { decimation *= 2 }
      let dt = Double(decimation) / 48000
      let n = d.x * d.y * d.z
      let mask = [UInt8](repeating: 1, count: n)
      let boundary = faces(d, mask, 0.001)
      let g = try PreparedWaveGrid(
        dimensions: d, spacing: h, soundSpeed: speed, density: 1, timeStep: dt, activeCells: mask,
        boundaryTerms: boundary)
      let p = (0..<n).map { Float($0 % 17 - 8) / 512 }
      let zero = [Float](repeating: 0, count: n)
      let initial = WaveInitialFields(
        pressureOverDensity: p, velocityX: zero, velocityY: zero, velocityZ: zero)
      let source = try PreparedPressureSource(
        grid: g, cellIndices: [n / 3, n / 3 + 1], coefficients: [0.25, -0.125])
      let cell = 1 + d.x * (1 + d.y)
      let pressureCells = [Array(repeating: cell, count: 8), Array(repeating: cell + 1, count: 8)]
      let weights = Array(repeating: [Float](arrayLiteral: 1, 0, 0, 0, 0, 0, 0, 0), count: 2)
      let observation = try PreparedWaveObservation(
        grid: g,
        receivers: [
          WaveReceiverStencil(pressureCells: pressureCells[0], pressureWeights: weights[0]),
          WaveReceiverStencil(
            pressureCells: pressureCells[1], pressureWeights: weights[1], velocityCell: cell,
            velocityAxis: [0.5, -0.25, 0.75]),
        ])
      let q = (0..<1024).map { Float($0 % 7 - 3) / 2048 }
      let initialFile = "initial-\(Int(frequency)).bin"
      try writeFields([p, zero, zero, zero].map { $0.map(\.bitPattern) }, initialFile, output)
      let probe = try ProfiledMetal.MetalWaveStepper(
        context: profileContext, grid: g, initialFields: initial)
      let maximum = probe.profileMaximumThreads
      try require(maximum >= 256, "physical device supports all selected groups")
      var runs: [Run] = []
      var controlFields: [[UInt32]] = []
      var controlFrames: [[UInt64]] = []
      var controlMixed: [[UInt64]] = []
      for repetition in -1..<3 {
        let modes = ["candidate", "profile32", "profile256"]
        let ordered = Array(modes[max(repetition, 0)...]) + Array(modes[..<max(repetition, 0)])
        for mode in ordered {
          let allStart = ContinuousClock().now
          let setupStart = allStart
          let profile: ProfiledMetal.MetalWaveStepper?
          let released: LinearAcousticsMetal.MetalWaveStepper?
          if mode == "candidate" {
            profile = nil
            released = try LinearAcousticsMetal.MetalWaveStepper(
              context: baselineContext, grid: g, initialFields: initial)
          } else {
            released = nil
            profile = try ProfiledMetal.MetalWaveStepper(
              context: profileContext, grid: g, initialFields: initial)
            profile!.profileGroup = mode == "profile32" ? [32, 1, 1] : [32, 4, 2]
          }
          let rs = try released?.prepareSource(source)
          let ro = try released?.prepareObservation(observation)
          let ps = try profile?.prepareSource(source)
          let po = try profile?.prepareObservation(observation)
          let setup = seconds(setupStart)
          var advance = 0.0
          var mixing = 0.0
          var frames: [WaveObservationFrame] = []
          var aligned: [AlignedWaveObservationFrame] = []
          var aligner = WaveObservationAligner()
          for start in stride(from: 0, to: 1024, by: 128) {
            let batch = Array(q[start..<(start + 128)])
            let t = ContinuousClock().now
            let captured =
              try released?.advance(source: rs!, amplitudes: batch, observing: ro!)
              ?? profile!.advance(source: ps!, amplitudes: batch, observing: po!)
            advance += seconds(t)
            frames += captured
            let a = ContinuousClock().now
            aligned += try aligner.append(captured)
            mixing += seconds(a)
          }
          let t = ContinuousClock().now
          aligned += try aligner.finishUsingFinalHalfStep()
          let mixed = aligned.map { f in
            [
              f.pressureOverDensity[0],
              0.5 * f.pressureOverDensity[1] - 0.5 * speed * f.projectedVelocity[1]!,
            ]
          }.map { $0.map(\.bitPattern) }
          mixing += seconds(t)
          let wall = seconds(allStart)
          let snapshot = try released?.snapshot() ?? profile!.snapshot()
          let fields = fieldBits(snapshot)
          let rawFrames = frames.map(frameBits)
          try require(
            snapshot.pressureStepIndex == 1024 && frames.count == 1024 && aligned.count == 1024,
            "complete histories")
          if controlFields.isEmpty {
            controlFields = fields
            controlFrames = rawFrames
            controlMixed = mixed
          }
          try require(
            fields == controlFields && rawFrames == controlFrames && mixed == controlMixed,
            "complete released/profile/group bit equivalence")
          if repetition < 0 { continue }
          let name = "fields-\(Int(frequency))-\(mode)-\(repetition).bin"
          try writeFields(fields, name, output)
          runs.append(
            Run(
              mode: mode, repetition: repetition, fieldFile: name,
              clock: snapshot.pressureStepIndex, wallSeconds: wall, setupSeconds: setup,
              advanceSeconds: advance, mixingSeconds: mixing,
              decodeSeconds: profile?.profileDecodeSeconds,
              commands: profile?.profileCommands, frameIndices: frames.map(\.pressureStepIndex),
              frames: rawFrames, mixed: mixed))
        }
      }
      cases.append(
        Case(
          frequency: frequency, timeStep: dt, speed: speed, dimensions: [d.x, d.y, d.z],
          spacing: [h.x, h.y, h.z], sourceCells: source.cellIndices,
          sourceCoefficients: source.coefficients, amplitudes: q, inside: mask, faces: boundary,
          initialFieldFile: initialFile, pressureCells: pressureCells, pressureWeights: weights,
          velocityCells: [nil, cell], axes: [nil, [0.5, -0.25, 0.75]], maximumThreads: maximum,
          runs: runs))
    }
    let report = Report(
      candidate: ProcessInfo.processInfo.environment["CONTINUUMKIT_CONSUMER_REVISION"]!,
      device: device.name, registryID: device.registryID, cases: cases,
      handOracle: expected.map { $0.map(\.bitPattern) })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(report).write(to: output.appendingPathComponent("metal-throughput.json"))
    print(
      "PASS 27 complete candidate/profiled/group runs; every field and receiver bit retained; barriers unchanged"
    )
  }
}
