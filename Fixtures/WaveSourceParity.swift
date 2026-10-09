// Independently chosen numerical control inputs; RoomCAD source is bound separately.
import Foundation
import LinearAcoustics

struct Capture: Codable {
  let step: Int
  let candidate, source: [[Float]]
}
struct Case: Codable {
  let name: String
  let dimensions: [Int], spacing: [Double]
  let speed, density, dt: Double
  let mask: [UInt8], faces: [Float]
  let captures: [Capture]
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
  let candidate = try CPUWaveStepper(grid: g, initialFields: initial)
  let source = SourceCPU(g, initial)
  var captures: [Capture] = []
  for step in 0...64 {
    let h = try candidate.snapshot()
    let actual = [h.pressureOverDensity, h.velocityX, h.velocityY, h.velocityZ]
    let original = source.fields()
    let sameBits = zip(actual.joined(), original.joined()).allSatisfy {
      $0.bitPattern == $1.bitPattern
    }
    guard h.pressureStepIndex == source.pressureStepIndex, sameBits else {
      throw ParityError.mismatch(name, step)
    }
    captures.append(Capture(step: step, candidate: actual, source: original))
    if step < 64 {
      try candidate.advance()
      source.advance(1)
    }
  }
  reports.append(
    Case(
      name: name, dimensions: [d.x, d.y, d.z], spacing: [spacing.x, spacing.y, spacing.z], speed: c,
      density: 1.25, dt: dt, mask: mask, faces: faces, captures: captures))
  print("PASS exact full native fields and clocks:", name, 65, "captures")
}
guard CommandLine.arguments.count == 2 else { throw ParityError.missingOutput }
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
try encoder.encode(reports).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
