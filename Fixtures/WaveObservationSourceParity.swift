// Independently chosen numerical control inputs; RoomCAD source is bound separately.
import Foundation
import LinearAcoustics

struct Capture: Codable {
  let step: Int
  let candidate, source: [[Float]]
  let pressureTime, velocityTime: Double
  let candidatePressure, sourcePressure: [Double]
  let candidateVelocity, sourceVelocity: [Double?]
}
struct Case: Codable {
  let name: String
  let dimensions: [Int], spacing: [Double]
  let speed, density, dt: Double
  let mask: [UInt8], faces: [Float]
  let sourceCells: [Int], sourceWeights: [Float], amplitudes: [Double]
  let captures: [Capture]
  let pressureCells: [[Int]], pressureWeights: [[Float]], velocityCells: [Int?], axes: [[Double]?]
  let candidateMixed, sourceMixed: [[Double]]
}
enum ParityError: Error {
  case mismatch(String, Int)
  case missingOutput
}
var reports: [Case] = []
for (name, d) in [
  ("all-active-rigid", SIMD3(5, 4, 3)), ("all-active-lossy", SIMD3(5, 4, 3)),
  ("masked-lossy", SIMD3(5, 4, 3)), ("split-chambers", SIMD3(7, 3, 2)),
] {
  let n = d.x * d.y * d.z
  let spacing: SIMD3<Double> = [0.03, 0.049, 0.08]
  let c = 319.7
  let dt = 0.000025
  let mask: [UInt8] = (0..<n).map { at in
    name == "masked-lossy" && at % 7 == 3 || name == "split-chambers" && at % d.x == 3 ? 0 : 1
  }
  let strides = [1, d.x, d.x * d.y]
  var faces = [Float](repeating: -1, count: 6 * n)
  for at in 0..<n where mask[at] == 1 {
    let xyz = [at % d.x, at / d.x % d.y, at / (d.x * d.y)]
    for side in 0..<6 {
      let axis = side / 2
      let plus = side % 2 == 1
      let within = plus ? xyz[axis] + 1 < d[axis] : xyz[axis] > 0
      let neighbour = at + (plus ? strides[axis] : -strides[axis])
      if !(within && mask[neighbour] == 1) {
        faces[side * n + at] =
          name.contains("lossy") ? Float(0.01 * Double(1 + (at + side) % 9)) : 0
      }
    }
  }
  let p: [Float] = (0..<n).map { mask[$0] == 1 ? Float(sin(Double($0) * 0.371) * 0.7) : 100 }
  let velocities = (0..<3).map { axis in
    (0..<n).map { at -> Float in
      mask[at] == 1 && faces[(2 * axis + 1) * n + at] == (-1)
        ? Float(0.015 * cos(Double(at + axis) * 0.253)) : 0
    }
  }
  let g = try PreparedWaveGrid(
    dimensions: d, spacing: spacing, soundSpeed: c, density: 1.25, timeStep: dt, activeCells: mask,
    boundaryTerms: faces)
  let initial = WaveInitialFields(
    pressureOverDensity: p, velocityX: velocities[0], velocityY: velocities[1],
    velocityZ: velocities[2])
  let cells = Array((0..<n).filter { mask[$0] == 1 }.prefix(3))
  let volume = spacing.x * spacing.y * spacing.z
  let scale = Float(c * c * dt / volume)
  let weights: [Float] = [0.5, 0.25, 0.25].map { $0 * scale }
  let amplitudes = (0..<257).map {
    0.37 * sin((Double($0) + 0.5) * 0.31) - 0.2 * cos((Double($0) + 0.5) * 0.11)
  }
  let plan = try PreparedPressureSource(grid: g, cellIndices: cells, coefficients: weights)
  let candidate = try CPUWaveStepper(grid: g, initialFields: initial)
  let source = SourceCPU(g, initial)
  let at = 1 + d.x + d.x * d.y
  var pc: [Int] = []
  var pw: [Float] = []
  for z in 0...1 {
    for y in 0...1 {
      for x in 0...1 {
        pc.append((x + 1) + d.x * (y + 1) + d.x * d.y * (z + min(1, d.z - 2)))
        pw.append(Float((x == 0 ? 0.75 : 0.25) * (y == 0 ? 0.5 : 0.5) * (z == 0 ? 0.25 : 0.75)))
      }
    }
  }
  let receivers = [
    WaveReceiverStencil(pressureCells: pc, pressureWeights: pw),
    WaveReceiverStencil(
      pressureCells: pc, pressureWeights: pw, velocityCell: at,
      velocityAxis: [0.372181992918271, -0.9177318281837, 0.735319212173]),
    WaveReceiverStencil(
      pressureCells: Array(repeating: at, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0],
      velocityCell: at, velocityAxis: [-0.3, 0.7, -0.1]),
  ]
  let observations = try PreparedWaveObservation(grid: g, receivers: receivers)
  var current = try candidate.observe(observations)
  var frames: [WaveObservationFrame] = []
  var captures: [Capture] = []
  var sourcePressure = Array(repeating: [Double](), count: 3)
  var sourceVelocity = Array(repeating: [Double?](), count: 3)
  for step in 0...257 {
    let h = try candidate.snapshot()
    let actual = [h.pressureOverDensity, h.velocityX, h.velocityY, h.velocityZ]
    let original = source.fields()
    let sameBits = zip(actual.joined(), original.joined()).allSatisfy {
      $0.bitPattern == $1.bitPattern
    }
    guard h.pressureStepIndex == source.pressureStepIndex, sameBits else {
      throw ParityError.mismatch(name, step)
    }
    let readout = source.observe(observations)
    guard current.pressureStepIndex == step, current.pressureTime == Double(step) * dt,
      current.velocityTime == (Double(step) - 0.5) * dt,
      zip(current.pressureOverDensity, readout.pressure).allSatisfy({
        $0.bitPattern == $1.bitPattern
      }),
      zip(current.projectedVelocity, readout.velocity).allSatisfy({
        $0?.bitPattern == $1?.bitPattern
      })
    else { throw ParityError.mismatch(name, step) }
    captures.append(
      Capture(
        step: step, candidate: actual, source: original, pressureTime: current.pressureTime,
        velocityTime: current.velocityTime, candidatePressure: current.pressureOverDensity,
        sourcePressure: readout.pressure,
        candidateVelocity: current.projectedVelocity, sourceVelocity: readout.velocity))
    if step > 0 {
      frames.append(current)
      for r in 0..<3 {
        sourcePressure[r].append(readout.pressure[r])
        sourceVelocity[r].append(readout.velocity[r])
      }
    }
    if step < 257 {
      current = try candidate.advance(
        source: plan, amplitudes: [Float(amplitudes[step])], observing: observations)[0]
      source.advance([amplitudes[step]], sourceWeights: Array(zip(cells, weights)))
    }
  }
  let batched = try CPUWaveStepper(grid: g, initialFields: initial)
  var batchFrames: [WaveObservationFrame] = []
  for start in stride(from: 0, to: 257, by: 128) {
    let end = min(start + 128, 257)
    batchFrames += try batched.advance(
      source: plan, amplitudes: amplitudes[start..<end].map(Float.init), observing: observations)
  }
  guard
    zip(frames, batchFrames).allSatisfy({
      $0.pressureStepIndex == $1.pressureStepIndex
        && $0.pressureOverDensity == $1.pressureOverDensity
        && $0.projectedVelocity == $1.projectedVelocity
    })
  else { throw ParityError.mismatch(name, 257) }
  var aligner = WaveObservationAligner()
  var aligned: [AlignedWaveObservationFrame] = []
  for start in stride(from: 0, to: 257, by: 37) {
    aligned += try aligner.append(Array(batchFrames[start..<min(start + 37, 257)]))
  }
  aligned += try aligner.finishUsingFinalHalfStep()
  let originalMixed = source.mix(observations, sourcePressure, sourceVelocity)
  var mixed = Array(repeating: [Double](), count: 3)
  for frame in aligned {
    for r in 0..<3 {
      let share = r == 0 ? 1.0 : (r == 1 ? 0.0 : 0.3)
      mixed[r].append(
        r == 0
          ? frame.pressureOverDensity[r]
          : share * frame.pressureOverDensity[r] - (1 - share) * c * frame.projectedVelocity[r]!)
    }
  }
  guard mixed.count == 3,
    zip(mixed.joined(), originalMixed.joined()).allSatisfy({ $0.bitPattern == $1.bitPattern })
  else { throw ParityError.mismatch(name, 257) }
  reports.append(
    Case(
      name: name, dimensions: [d.x, d.y, d.z], spacing: [spacing.x, spacing.y, spacing.z], speed: c,
      density: 1.25, dt: dt, mask: mask, faces: faces, sourceCells: cells, sourceWeights: weights,
      amplitudes: amplitudes, captures: captures, pressureCells: receivers.map(\.pressureCells),
      pressureWeights: receivers.map(\.pressureWeights),
      velocityCells: receivers.map(\.velocityCell),
      axes: receivers.map { $0.velocityAxis.map { [$0.x, $0.y, $0.z] } }, candidateMixed: mixed,
      sourceMixed: originalMixed))
  print(
    "PASS exact forced native fields and clocks:", name, 258,
    "complete field/receiver captures; exact original mixed output and chunked timing")
}
guard CommandLine.arguments.count == 2 else { throw ParityError.missingOutput }
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
struct Envelope: Codable {
  let schemaVersion: Int
  let coreRevision: String
  let roomRevision: String
  let reports: [Case]
}
let envelope = Envelope(
  schemaVersion: 1,
  coreRevision: ProcessInfo.processInfo.environment["CONTINUUMKIT_CONSUMER_REVISION"]!,
  roomRevision: "f2f6465d0d845af9adda596c004b18ca15a77edd", reports: reports)
try encoder.encode(envelope).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
