import BenchmarkSupport
import Foundation
import LinearAcoustics
import Testing

// Independently prepared integer adjacency; no application geometry or production helper.
func waveFaces(_ d: SIMD3<Int>, _ mask: [UInt8], loss: Float = 0) -> [Float] {
  let n = mask.count
  let strides = [1, d.x, d.x * d.y]
  guard n == d.x * d.y * d.z else { return [] }
  var faces = [Float](repeating: -1, count: 6 * n)
  for at in 0..<n where mask[at] == 1 {
    let xyz = [at % d.x, at / d.x % d.y, at / (d.x * d.y)]
    for side in 0..<6 {
      let axis = side / 2
      let plus = side % 2 == 1
      let within = plus ? xyz[axis] + 1 < d[axis] : xyz[axis] > 0
      let neighbour = at + (plus ? strides[axis] : -strides[axis])
      faces[side * n + at] = within && mask[neighbour] == 1 ? -1 : loss
    }
  }
  return faces
}
func waveGrid(
  _ d: SIMD3<Int> = [2, 2, 2], mask: [UInt8]? = nil, dt: Double = 0.125,
  spacing: SIMD3<Double> = [1, 1, 1], speed: Double = 1, density: Double = 1,
  faces: [Float]? = nil
) throws -> PreparedWaveGrid {
  let inside = mask ?? [UInt8](repeating: 1, count: d.x * d.y * d.z)
  return try PreparedWaveGrid(
    dimensions: d, spacing: spacing, soundSpeed: speed,
    density: density, timeStep: dt, activeCells: inside,
    boundaryTerms: faces ?? waveFaces(d, inside))
}
func waveFields(_ p: [Float], _ velocities: [[Float]]? = nil) -> WaveInitialFields {
  let u = velocities ?? Array(repeating: [Float](repeating: 0, count: p.count), count: 3)
  return WaveInitialFields(
    pressureOverDensity: p, velocityX: u[0], velocityY: u[1], velocityZ: u[2])
}
func arrays(_ s: WaveSnapshot) -> [[Float]] {
  [s.pressureOverDensity, s.velocityX, s.velocityY, s.velocityZ]
}

@Suite("Checked source-free linear wave CPU") struct WaveStepperTests {
  @Test("Hand-derived two-cell staggered step, clocks and unchanged inactive padding")
  func goldenStep() throws {
    let g = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    let s = try CPUWaveStepper(
      grid: g, initialFields: waveFields([1, 0, 100, 100, 100, 100, 100, 100]))
    #expect(try s.snapshot().velocityTime == -0.0625)
    try s.advance()
    let h = try s.snapshot()
    #expect(h.pressureOverDensity == [0.984375, 0.015625, 100, 100, 100, 100, 100, 100])
    #expect(h.velocityX == [0.125, 0, 0, 0, 0, 0, 0, 0])
    #expect(h.velocityY.allSatisfy { $0 == 0 } && h.velocityZ.allSatisfy { $0 == 0 })
    #expect(h.pressureStepIndex == 1 && h.pressureTime == 0.125 && h.velocityTime == 0.0625)
  }
  @Test("Caller state/grid and retained snapshots do not alias resident fields")
  func ownershipAndComposition() throws {
    var mask: [UInt8] = [1, 1, 0, 0, 0, 0, 0, 0]
    var faces = waveFaces([2, 2, 2], mask)
    let g = try waveGrid(mask: mask, faces: faces)
    var p: [Float] = [1, 0, 100, 100, 100, 100, 100, 100]
    let initial = waveFields(p)
    let a = try CPUWaveStepper(grid: g, initialFields: initial)
    let b = try CPUWaveStepper(grid: g, initialFields: initial)
    let saved = try a.snapshot()
    mask[0] = 0
    faces[0] = 99
    p[0] = 99
    try a.advance(steps: 0)
    #expect(arrays(try a.snapshot()) == arrays(saved))
    try a.advance(steps: 13)
    try b.advance(steps: 5)
    try b.advance(steps: 8)
    #expect(arrays(try a.snapshot()) == arrays(try b.snapshot()))
    #expect(saved.pressureOverDensity[0] == 1 && saved.pressureStepIndex == 0)
    #expect(g.activeCells[0] == 1 && g.boundaryTerms[0] == 0 && initial.pressureOverDensity[0] == 1)
  }
  @Test("Density conversion is caller-owned and coefficients round from Double once")
  func densityAndRounding() throws {
    let d: SIMD3<Int> = [2, 2, 2]
    let spacing: SIMD3<Double> = [0.31, 0.47, 0.83]
    let a = try waveGrid(d, dt: 0.0001234567, spacing: spacing, speed: 319.7, density: 1.25)
    let b = try waveGrid(d, dt: a.timeStep, spacing: spacing, speed: a.soundSpeed, density: 1000)
    for axis in 0..<3 {
      #expect(a.velocityCoefficients[axis] == Float(a.timeStep / spacing[axis]))
      #expect(
        a.pressureCoefficients[axis]
          == Float(a.soundSpeed * a.soundSpeed * a.timeStep / spacing[axis]))
    }
    #expect(
      a.pressureCoefficients.x != Float(a.soundSpeed) * Float(a.soundSpeed) * Float(a.timeStep)
        / Float(spacing.x))
    let p: [Float] = [1, 0, 0.2, -0.3, 0, 0, 0, 0]
    let sa = try CPUWaveStepper(grid: a, initialFields: waveFields(p))
    let sb = try CPUWaveStepper(grid: b, initialFields: waveFields(p))
    try sa.advance(steps: 9)
    try sb.advance(steps: 9)
    #expect(arrays(try sa.snapshot()) == arrays(try sb.snapshot()))
  }
  @Test("Disconnected undriven chamber remains exactly quiet") func disconnected() throws {
    let d: SIMD3<Int> = [5, 2, 2]
    let mask: [UInt8] = (0..<20).map { $0 % 5 == 2 ? 0 : 1 }
    let g = try waveGrid(d, mask: mask)
    let p: [Float] = (0..<20).map { mask[$0] == 0 ? 100 : ($0 % 5 < 2 ? 1 : 0) }
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields(p))
    try s.advance(steps: 50)
    let h = try s.snapshot()
    for at in p.indices where at % 5 >= 2 {
      #expect(h.pressureOverDensity[at] == p[at])
      #expect(h.velocityX[at] == 0 && h.velocityY[at] == 0 && h.velocityZ[at] == 0)
    }
  }
  @Test("Isolated cell trapezoidal decay and full wall work obey modified-energy budget")
  func decayAndWork() throws {
    let mask: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]
    let beta: Float = 0.03125
    let g = try waveGrid(mask: mask, faces: waveFaces([2, 2, 2], mask, loss: beta))
    let s = try CPUWaveStepper(
      grid: g, initialFields: waveFields([1, 100, 100, 100, 100, 100, 100, 100]))
    let wall = Double(6 * beta)
    let ratio = (1 - wall) / (1 + wall)
    var previous = 1.0
    var work = 0.0
    for step in 1...32 {
      try s.advance()
      let h = try s.snapshot()
      let value = Double(h.pressureOverDensity[0])
      #expect(abs(value - pow(ratio, Double(step))) < 2e-7)
      work += 2 * wall * pow((previous + value) / 2, 2)
      #expect(abs(value * value / 2 + work - 0.5) < 2e-7)
      previous = value
      #expect(h.pressureOverDensity.dropFirst().allSatisfy { $0 == 100 })
    }
  }
  @Test("Invalid dimensions and index/byte overflow fail before allocation") func dimensions() {
    for d in [SIMD3<Int>(1, 2, 2), SIMD3<Int>(0, 2, 2), SIMD3<Int>(-1, 2, 2)] {
      #expect(throws: WaveError.invalidDimensions) {
        try PreparedWaveGrid(
          dimensions: d, spacing: [1, 1, 1], soundSpeed: 1, density: 1, timeStep: 0.1,
          activeCells: [], boundaryTerms: [])
      }
    }
    for d in [
      SIMD3<Int>(Int.max, 2, 2), SIMD3<Int>(1_000_000, 1_000_000, 2),
      SIMD3<Int>(50_000, 50_000, 50_000),
    ] {
      #expect(throws: WaveError.dimensionOverflow) {
        try PreparedWaveGrid(
          dimensions: d, spacing: [1, 1, 1], soundSpeed: 1, density: 1, timeStep: 0.1,
          activeCells: [], boundaryTerms: [])
      }
    }
  }
  @Test("Bad physical parameters, Float overflow/underflow and CFL are rejected")
  func parameters() throws {
    for bad in [0.0, -1, .infinity, .nan] {
      #expect(throws: WaveError.invalidParameters) { try waveGrid(dt: bad) }
      #expect(throws: WaveError.invalidParameters) { try waveGrid(spacing: [bad, 1, 1]) }
      #expect(throws: WaveError.invalidParameters) { try waveGrid(speed: bad) }
      #expect(throws: WaveError.invalidParameters) { try waveGrid(density: bad) }
    }
    #expect(throws: WaveError.unstableTimeStep) { try waveGrid(dt: 1) }
    // Physical CFL just below one can still round the actual update to instability.
    #expect(throws: WaveError.unstableTimeStep) {
      try waveGrid(dt: Double(1).nextDown, spacing: [1, 1e9, 1e9])
    }
    #expect(throws: WaveError.unrepresentableCoefficients) { try waveGrid(dt: 1e-100) }
    #expect(throws: WaveError.unrepresentableCoefficients) { try waveGrid(dt: 1e-20, speed: 1e30) }
  }
  @Test("Lengths, masks, empty domains and inactive boundary padding are checked") func layout()
    throws
  {
    #expect(throws: WaveError.self) { try waveGrid(mask: [1]) }
    #expect(throws: WaveError.invalidMask) { try waveGrid(mask: [2, 1, 1, 1, 1, 1, 1, 1]) }
    #expect(throws: WaveError.emptyDomain) { try waveGrid(mask: Array(repeating: 0, count: 8)) }
    let mask: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]
    var f = waveFaces([2, 2, 2], mask)
    f[1] = 0
    #expect(throws: WaveError.invalidBoundaryTerms(cell: 1, face: 0)) {
      try waveGrid(mask: mask, faces: f)
    }
    #expect(throws: WaveError.self) { try waveGrid(faces: []) }
  }
  @Test("Outer open faces, unpaired links, NaN, negative and excessive wall terms fail")
  func boundaries() throws {
    let mask = [UInt8](repeating: 1, count: 8)
    let good = waveFaces([2, 2, 2], mask)
    for (index, value) in [
      (0, Float(-1)), (8, Float(0)), (0, Float(-0.5)), (0, Float.nan), (0, Float.infinity),
    ] {
      var f = good
      f[index] = value
      #expect(throws: WaveError.self) { try waveGrid(faces: f) }
    }
    var f = good
    for side in [0, 2, 4] { f[side * 8] = Float.greatestFiniteMagnitude }
    #expect(throws: WaveError.self) { try waveGrid(faces: f) }
  }
  @Test("Initial arrays, nonfinite fields and closed velocities fail without sanitizing")
  func initialState() throws {
    let g = try waveGrid(mask: [1, 0, 0, 0, 0, 0, 0, 0])
    #expect(throws: WaveError.self) { try CPUWaveStepper(grid: g, initialFields: waveFields([1])) }
    for field in 0..<4 {
      var f = Array(repeating: Array(repeating: Float(0), count: 8), count: 4)
      f[field][0] = .nan
      #expect(throws: WaveError.invalidInitialFields) {
        try CPUWaveStepper(grid: g, initialFields: waveFields(f[0], Array(f.dropFirst())))
      }
    }
    for field in 1...3 {
      var f = Array(repeating: Array(repeating: Float(0), count: 8), count: 3)
      f[field - 1][0] = 1
      #expect(throws: WaveError.closedFaceVelocity(field: field, cell: 0)) {
        try CPUWaveStepper(grid: g, initialFields: waveFields(Array(repeating: 0, count: 8), f))
      }
    }
  }
  @Test("Bad step counts and index overflow preserve completed state") func badSteps() throws {
    let s = try CPUWaveStepper(
      grid: waveGrid(), initialFields: waveFields(Array(repeating: 1, count: 8)))
    try s.advance()
    let saved = try s.snapshot()
    #expect(throws: WaveError.invalidStepCount) { try s.advance(steps: -1) }
    #expect(throws: WaveError.stepIndexOverflow) { try s.advance(steps: Int.max) }
    #expect(arrays(try s.snapshot()) == arrays(saved) && s.pressureStepIndex == 1)
  }
  @Test("Arithmetic failure invalidates partially updated state without advancing clock")
  func arithmeticFailure() throws {
    let g = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    let a = Float.greatestFiniteMagnitude
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields([a, -a, 0, 0, 0, 0, 0, 0]))
    #expect(throws: WaveError.nonfiniteOutput) { try s.advance() }
    #expect(s.pressureStepIndex == 0)
    #expect(throws: WaveError.invalidatedState) { try s.snapshot() }
    #expect(throws: WaveError.invalidatedState) { try s.advance(steps: 0) }
  }
}
