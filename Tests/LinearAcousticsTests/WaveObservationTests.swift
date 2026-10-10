import Foundation
import LinearAcoustics
import Testing

func receiver(_ cell: Int = 0, velocityCell: Int? = nil, axis: SIMD3<Double>? = nil)
  -> WaveReceiverStencil
{
  WaveReceiverStencil(
    pressureCells: Array(repeating: cell, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0],
    velocityCell: velocityCell, velocityAxis: axis)
}
func observationValues(_ frames: [WaveObservationFrame]) -> [[Double]] {
  frames.map {
    [Double($0.pressureStepIndex), $0.pressureTime, $0.velocityTime] + $0.pressureOverDensity
      + $0.projectedVelocity.map { $0 ?? 0 }
  }
}
@Suite("Prepared CPU wave observations") struct WaveObservationTests {
  @Test("Affine physical fields reproduce prepared trilinear pressure and native-face projection")
  func affine() throws {
    let d: SIMD3<Int> = [4, 4, 4]
    let spacing: SIMD3<Double> = [2, 3, 4]
    let g = try waveGrid(d, dt: 0.125, spacing: spacing)
    var p = [Float](repeating: 0, count: 64)
    var v = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    for at in 0..<64 {
      let xyz = [at % 4, at / 4 % 4, at / 16]
      let x = (Double(xyz[0]) + 0.5) * 2
      let y = (Double(xyz[1]) + 0.5) * 3
      let z = (Double(xyz[2]) + 0.5) * 4
      p[at] = Float(2 + 3 * x - 2 * y + 0.5 * z)
      if xyz[0] < 3 { v[0][at] = Float(4 + 2 * Double(xyz[0] + 1) * 2) }
      if xyz[1] < 3 { v[1][at] = Float(-1 + 0.5 * Double(xyz[1] + 1) * 3) }
      if xyz[2] < 3 { v[2][at] = Float(3 - 0.25 * Double(xyz[2] + 1) * 4) }
    }
    var cells: [Int] = []
    var weights: [Float] = []
    for z in 0...1 {
      for y in 0...1 {
        for x in 0...1 {
          cells.append((x + 1) + 4 * (y + 1) + 16 * (z + 1))
          weights.append(
            Float((x == 0 ? 0.75 : 0.25) * (y == 0 ? 0.5 : 0.5) * (z == 0 ? 0.25 : 0.75)))
        }
      }
    }
    let plan = try PreparedWaveObservation(
      grid: g,
      receivers: [
        WaveReceiverStencil(
          pressureCells: cells, pressureWeights: weights, velocityCell: 21,
          velocityAxis: [0.5, -0.25, 0.75]), receiver(0),
      ])
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields(p, v))
    let saved = try s.snapshot()
    let h = try s.observe(plan)
    #expect(
      h.pressureOverDensity[0] == 5 && h.projectedVelocity[0] == 5.8125
        && h.projectedVelocity[1] == nil)
    #expect(h.pressureStepIndex == 0 && h.pressureTime == 0 && h.velocityTime == -0.0625)
    #expect(arrays(try s.snapshot()) == arrays(saved))
  }

  @Test("Pressure uses ordered Double accumulation; velocity pairs add in Float first")
  func precision() throws {
    let g = try waveGrid([4, 4, 4])
    var p = [Float](repeating: 0, count: 64)
    p[0] = 16_777_216
    p[1] = 1
    p[2] = -16_777_216
    var v = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    v[0][20] = 16_777_216
    v[0][21] = 1
    let stencil = WaveReceiverStencil(
      pressureCells: [0, 1, 2, 0, 0, 0, 0, 0], pressureWeights: [1, 1, 1, 0, 0, 0, 0, 0],
      velocityCell: 21, velocityAxis: [1, 0, 0])
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields(p, v))
    let h = try s.observe(PreparedWaveObservation(grid: g, receivers: [stencil]))
    #expect(h.pressureOverDensity == [1] && h.projectedVelocity == [8_388_608])
  }

  @Test("Stencil shape, zero-weight indices, finite weights/axes and row-safe neighbours validate")
  func validation() throws {
    let g = try waveGrid([3, 3, 3])
    #expect(throws: WaveObservationError.invalidStencil(receiver: 0)) {
      try PreparedWaveObservation(
        grid: g, receivers: [WaveReceiverStencil(pressureCells: [0], pressureWeights: [1])])
    }
    for cell in [-1, 27, Int.max] {
      #expect(throws: WaveObservationError.invalidPressureCell(receiver: 0, entry: 7)) {
        try PreparedWaveObservation(
          grid: g,
          receivers: [
            WaveReceiverStencil(
              pressureCells: [0, 0, 0, 0, 0, 0, 0, cell], pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0])
          ])
      }
    }
    #expect(throws: WaveObservationError.nonfiniteWeight(receiver: 0, entry: 0)) {
      try PreparedWaveObservation(
        grid: g,
        receivers: [
          WaveReceiverStencil(
            pressureCells: Array(repeating: 0, count: 8),
            pressureWeights: [.nan, 0, 0, 0, 0, 0, 0, 0])
        ])
    }
    for cell in [0, 3, 9, 12, 27, -1] {
      #expect(throws: WaveObservationError.invalidVelocityProbe(receiver: 0)) {
        try PreparedWaveObservation(
          grid: g, receivers: [receiver(velocityCell: cell, axis: [1, 0, 0])])
      }
    }
    #expect(throws: WaveObservationError.invalidVelocityProbe(receiver: 0)) {
      try PreparedWaveObservation(grid: g, receivers: [receiver(velocityCell: 13)])
    }
    #expect(throws: WaveObservationError.nonfiniteAxis(receiver: 0)) {
      try PreparedWaveObservation(
        grid: g, receivers: [receiver(velocityCell: 13, axis: [.infinity, 0, 0])])
    }
    // Read-only inactive padding and repeated/signed entries are deliberately legal.
    let inactive = try waveGrid(mask: [1, 0, 0, 0, 0, 0, 0, 0])
    let plan = try PreparedWaveObservation(
      grid: inactive,
      receivers: [
        WaveReceiverStencil(
          pressureCells: Array(repeating: 1, count: 8), pressureWeights: [2, -1, 0, 0, 0, 0, 0, 0])
      ])
    let s = try CPUWaveStepper(
      grid: inactive, initialFields: waveFields([0, 100, 100, 100, 100, 100, 100, 100]))
    #expect(try s.observe(plan).pressureOverDensity == [100])
  }

  @Test(
    "Invalid/bounded observation requests preserve state, and plan/input ownership is independent")
  func bindingAndBounds() throws {
    let g = try waveGrid()
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let foreign = try PreparedWaveObservation(grid: waveGrid(), receivers: [receiver()])
    #expect(throws: WaveObservationError.gridMismatch) { try s.observe(foreign) }
    var cells = Array(repeating: 0, count: 8)
    var weights: [Float] = [1, 0, 0, 0, 0, 0, 0, 0]
    let plan = try PreparedWaveObservation(
      grid: g, receivers: [WaveReceiverStencil(pressureCells: cells, pressureWeights: weights)])
    cells[0] = 7
    weights[0] = 99
    #expect(throws: WaveObservationError.batchTooLarge) {
      try s.advance(steps: 129, observing: plan)
    }
    #expect(throws: WaveError.invalidStepCount) { try s.advance(steps: -1, observing: plan) }
    #expect(
      s.pressureStepIndex == 0 && plan.receivers[0].pressureCells[0] == 0
        && plan.receivers[0].pressureWeights[0] == 1)
    #expect(try s.advance(steps: 0, observing: plan).isEmpty)
  }

  @Test("Sampling overflow is read-only and does not invalidate a finite field state")
  func readFailure() throws {
    let g = try waveGrid([4, 4, 4])
    let maximum = Float.greatestFiniteMagnitude
    var v = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    v[0][20] = maximum
    v[0][21] = maximum
    let s = try CPUWaveStepper(
      grid: g, initialFields: waveFields(Array(repeating: 0, count: 64), v))
    let plan = try PreparedWaveObservation(
      grid: g, receivers: [receiver(velocityCell: 21, axis: [1, 0, 0])])
    #expect(throws: WaveObservationError.nonfiniteResult(receiver: 0)) { try s.observe(plan) }
    let snapshot = try s.snapshot()
    #expect(s.pressureStepIndex == 0 && snapshot.velocityX[20] == maximum)
    #expect(
      try s.observe(PreparedWaveObservation(grid: g, receivers: [receiver()])).projectedVelocity
        == [nil])
  }

  @Test("Observed forced batches retain every complete sample and compose across chunks")
  func history() throws {
    let g = try waveGrid([3, 3, 3])
    let initial = waveFields(Array(repeating: 0, count: 27))
    let source = try PreparedPressureSource(
      grid: g, cellIndices: [0, 13], coefficients: [0.125, -0.25])
    let plan = try PreparedWaveObservation(
      grid: g, receivers: [receiver(13, velocityCell: 13, axis: [0.3, -0.7, 0.1]), receiver(0)])
    let a = try CPUWaveStepper(grid: g, initialFields: initial)
    let b = try CPUWaveStepper(grid: g, initialFields: initial)
    let amplitudes: [Float] = [1, -0.5, 0.75, 0, 1, 0.25, -1]
    let whole = try a.advance(source: source, amplitudes: amplitudes, observing: plan)
    let first = try b.advance(
      source: source, amplitudes: Array(amplitudes.prefix(3)), observing: plan)
    let last = try b.advance(
      source: source, amplitudes: Array(amplitudes.dropFirst(3)), observing: plan)
    #expect(observationValues(whole) == observationValues(first + last) && whole.count == 7)
    #expect(whole.first?.pressureStepIndex == 1 && whole.last?.pressureStepIndex == 7)
    #expect(arrays(try a.snapshot()) == arrays(try b.snapshot()))
    var align = WaveObservationAligner()
    var other = WaveObservationAligner()
    let w = try align.append(whole) + align.finishUsingFinalHalfStep()
    let c = try other.append(first) + other.append(last) + other.finishUsingFinalHalfStep()
    #expect(
      w.map(\.projectedVelocity) == c.map(\.projectedVelocity)
        && w.map(\.pressureOverDensity) == c.map(\.pressureOverDensity))
  }
}
@Suite("Staggered observation lookahead") struct ObservationAlignmentTests {
  func frame(_ step: Int, _ velocity: Double, timeStep: Double = 0.125) -> WaveObservationFrame {
    WaveObservationFrame(
      pressureStepIndex: step, timeStep: timeStep, pressureOverDensity: [Double(step) * 10, 99],
      projectedVelocity: [velocity, nil])
  }
  @Test("Hand clock/ramp reference and explicit terminal fallback survive one-frame chunks")
  func clocks() throws {
    var align = WaveObservationAligner()
    #expect(try align.append([frame(1, -1)]).isEmpty)
    let first = try align.append([frame(2, 3)])[0]
    let second = try align.append([frame(3, 7)])[0]
    let last = try align.finishUsingFinalHalfStep()[0]
    #expect(
      first.pressureOverDensity == [10, 99] && first.projectedVelocity == [1, nil]
        && first.pressureTime == 0.125 && first.velocityTime == 0.125)
    #expect(
      second.projectedVelocity == [5, nil] && second.pressureTime == 0.25
        && !second.usesTerminalHalfStep)
    #expect(
      last.projectedVelocity == [7, nil] && last.pressureTime == 0.375
        && last.velocityTime == 0.3125 && last.usesTerminalHalfStep)
    #expect(throws: WaveObservationError.finished) { try align.append([]) }
    #expect(throws: WaveObservationError.finished) { try align.finishUsingFinalHalfStep() }
  }
  @Test(
    "A rejected whole chunk leaves pending state intact; dimensions, masks and clocks stay consistent"
  )
  func rejection() throws {
    var align = WaveObservationAligner()
    _ = try align.append([frame(1, 1)])
    #expect(throws: WaveObservationError.nonconsecutiveFrames) {
      try align.append([frame(2, 2), frame(4, 4)])
    }
    #expect(throws: WaveObservationError.inconsistentFrames) {
      try align.append([frame(2, 2, timeStep: 0.25)])
    }
    #expect(throws: WaveObservationError.invalidFrame) {
      try align.append([
        WaveObservationFrame(
          pressureStepIndex: 2, timeStep: 0.125, pressureOverDensity: [1], projectedVelocity: [])
      ])
    }
    let result = try align.append([frame(2, 2)])
    #expect(
      result.count == 1 && result[0].pressureStepIndex == 1
        && result[0].projectedVelocity == [1.5, nil])
  }
  @Test("Readout provenance rejects mixing different prepared receiver plans")
  func identity() throws {
    let g = try waveGrid()
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields(Array(repeating: 1, count: 8)))
    let a = try PreparedWaveObservation(grid: g, receivers: [receiver(0)])
    let b = try PreparedWaveObservation(grid: g, receivers: [receiver(1)])
    var align = WaveObservationAligner()
    _ = try align.append([s.observe(a)])
    try s.advance()
    #expect(throws: WaveObservationError.inconsistentFrames) { try align.append([s.observe(b)]) }
    #expect(try align.append([s.observe(a)]).count == 1)
  }
  @Test("Finite inputs cannot silently overflow lookahead averaging")
  func overflow() throws {
    var align = WaveObservationAligner()
    _ = try align.append([frame(1, Double.greatestFiniteMagnitude)])
    #expect(throws: WaveObservationError.nonfiniteResult(receiver: 0)) {
      try align.append([frame(2, Double.greatestFiniteMagnitude)])
    }
    #expect(
      try align.finishUsingFinalHalfStep()[0].projectedVelocity[0] == Double.greatestFiniteMagnitude
    )
  }
}
