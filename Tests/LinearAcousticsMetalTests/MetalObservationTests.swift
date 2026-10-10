import Foundation
import LinearAcoustics
import Metal
import Testing

@testable import LinearAcousticsMetal

func metalReceiver(_ cell: Int = 0, velocityCell: Int? = nil, axis: SIMD3<Double>? = nil)
  -> WaveReceiverStencil
{
  WaveReceiverStencil(
    pressureCells: Array(repeating: cell, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0],
    velocityCell: velocityCell, velocityAxis: axis)
}
@Suite("Resident Metal receiver observations") struct MetalObservationTests {
  @Test("Affine field reference and mixed channel order require actual packaged sampling")
  func affine() throws {
    let g = try waveGrid([4, 4, 4], spacing: [2, 3, 4])
    let device = try waveDevice()
    var p = [Float](repeating: 0, count: 64)
    var v = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    for at in 0..<64 {
      let x = at % 4
      let y = at / 4 % 4
      let z = at / 16
      p[at] = Float(
        2 + 3 * (Double(x) + 0.5) * 2 - 2 * (Double(y) + 0.5) * 3 + 0.5 * (Double(z) + 0.5) * 4)
      if x < 3 { v[0][at] = Float(4 + 2 * Double(x + 1) * 2) }
      if y < 3 { v[1][at] = Float(-1 + 0.5 * Double(y + 1) * 3) }
      if z < 3 { v[2][at] = Float(3 - 0.25 * Double(z + 1) * 4) }
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
        metalReceiver(0),
        WaveReceiverStencil(
          pressureCells: cells, pressureWeights: weights, velocityCell: 21,
          velocityAxis: [0.5, -0.25, 0.75]), metalReceiver(21),
      ])
    let gpu = try MetalWaveStepper(device: device, grid: g, initialFields: waveFields(p, v))
    let prepared = try gpu.prepareObservation(plan)
    let saved = try gpu.snapshot()
    let h = try gpu.observe(prepared)
    #expect(h.pressureOverDensity[1] == 5 && h.projectedVelocity == [nil, 5.8125, nil])
    #expect(
      h.arithmetic == .metalFloat && h.pressureStepIndex == 0 && h.velocityTime == -g.timeStep / 2)
    #expect(arrays(try gpu.snapshot()) == arrays(saved))
  }

  @Test("Float pressure reduction and Float axis conversion retain distinct backend precision")
  func precision() throws {
    let g = try waveGrid([4, 4, 4])
    let device = try waveDevice()
    var p = [Float](repeating: 0, count: 64)
    p[0] = 16_777_216
    p[1] = 1
    p[2] = -16_777_216
    var v = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    v[0][20] = 1
    v[0][21] = 1
    let axis: SIMD3<Double> = [1 + 1e-8, 0, 0]
    let stencil = WaveReceiverStencil(
      pressureCells: [0, 1, 2, 0, 0, 0, 0, 0], pressureWeights: [1, 1, 1, 0, 0, 0, 0, 0],
      velocityCell: 21, velocityAxis: axis)
    let plan = try PreparedWaveObservation(grid: g, receivers: [stencil])
    let initial = waveFields(p, v)
    let gpu = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let cpu = try CPUWaveStepper(grid: g, initialFields: initial)
    let actual = try gpu.observe(gpu.prepareObservation(plan))
    let other = try cpu.observe(plan)
    #expect(actual.pressureOverDensity == [0] && other.pressureOverDensity == [1])
    #expect(actual.projectedVelocity == [1] && other.projectedVelocity == [1 + 1e-8])
  }

  @Test(
    "Pressure-only minimal grid avoids velocity reads, even when face-pair arithmetic overflows")
  func pressureOnly() throws {
    let g = try waveGrid()
    let device = try waveDevice()
    let maximum = Float.greatestFiniteMagnitude
    // The three negative neighbours of cell 7 have live faces; the positive slots are closed.
    // Use a larger grid for two live neighbouring faces that overflow their Float sum.
    let wide = try waveGrid([4, 4, 4])
    var v = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    v[0][20] = maximum
    v[0][21] = maximum
    let gpu = try MetalWaveStepper(
      device: device, grid: wide, initialFields: waveFields(Array(repeating: 0, count: 64), v))
    let both = try gpu.prepareObservation(
      PreparedWaveObservation(
        grid: wide, receivers: [metalReceiver(21, velocityCell: 21, axis: [1, 0, 0])]))
    #expect(throws: WaveObservationError.nonfiniteResult(receiver: 0)) { try gpu.observe(both) }
    let pressure = try gpu.prepareObservation(
      PreparedWaveObservation(grid: wide, receivers: [metalReceiver(21)]))
    #expect(try gpu.observe(pressure).projectedVelocity == [nil])
    #expect(try gpu.snapshot().velocityX[20] == maximum)
    let small = try MetalWaveStepper(
      device: device, grid: g, initialFields: waveFields(Array(repeating: 2, count: 8)))
    let probe = try small.prepareObservation(
      PreparedWaveObservation(grid: g, receivers: [metalReceiver(0)]))
    #expect(try small.observe(probe).pressureOverDensity == [2])
  }

  @Test(
    "Whole-request plan, Float representability, step/clock and amplitude rejection precede field work"
  )
  func validation() throws {
    let g = try waveGrid([3, 3, 3])
    let device = try waveDevice()
    let initial = waveFields(Array(repeating: 0, count: 27))
    let gpu = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let foreign = try PreparedWaveObservation(
      grid: waveGrid([3, 3, 3]), receivers: [metalReceiver()])
    #expect(throws: WaveObservationError.gridMismatch) { try gpu.prepareObservation(foreign) }
    let enormous = try PreparedWaveObservation(
      grid: g, receivers: [metalReceiver(13, velocityCell: 13, axis: [1e100, 0, 0])])
    #expect(throws: MetalWaveError.unrepresentableObservationAxis(receiver: 0)) {
      try gpu.prepareObservation(enormous)
    }
    let prepared = try gpu.prepareObservation(
      PreparedWaveObservation(grid: g, receivers: [metalReceiver()]))
    #expect(try gpu.advance(steps: 0, observing: prepared).isEmpty)
    #expect(gpu.observationBufferIdentities.isEmpty)
    #expect(throws: WaveObservationError.batchTooLarge) {
      try gpu.advance(steps: 129, observing: prepared)
    }
    #expect(throws: WaveError.invalidStepCount) { try gpu.advance(steps: -1, observing: prepared) }
    let source = try gpu.prepareSource(
      PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [1]))
    #expect(throws: PressureSourceError.nonfiniteAmplitude(step: 1)) {
      try gpu.advance(source: source, amplitudes: [1, .nan], observing: prepared)
    }
    #expect(gpu.pressureStepIndex == 0 && gpu.observationBufferIdentities.isEmpty)
    let huge = try waveGrid(dt: 1e308, spacing: [1e308, 1e308, 1e308], speed: 1e-20)
    let clock = try MetalWaveStepper(
      device: device, grid: huge, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let empty = try clock.prepareObservation(PreparedWaveObservation(grid: huge, receivers: []))
    #expect(throws: WaveError.stepClockOverflow) { try clock.advance(steps: 2, observing: empty) }
    #expect(clock.pressureStepIndex == 0)
  }

  @Test(
    "Read-only sampling retains native trajectory, resident storage and owned 257-step histories")
  func history() throws {
    let d: SIMD3<Int> = [4, 3, 2]
    let g = try waveGrid(d, dt: 0.03125, spacing: [1, 0.8, 1.3], speed: 1.7)
    let device = try waveDevice()
    let initial = waveFields((0..<24).map { Float(sin(Double($0) * 0.3)) })
    let gpu = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let split = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let untouched = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let source = try gpu.prepareSource(
      PreparedPressureSource(grid: g, cellIndices: [0, 17], coefficients: [0.125, -0.25]))
    let plan = try PreparedWaveObservation(
      grid: g,
      receivers: [
        metalReceiver(0), metalReceiver(17, velocityCell: 17, axis: [0.3, -0.7, 0.1]),
        metalReceiver(5),
      ])
    let prepared = try gpu.prepareObservation(plan)
    let mapped = prepared.bufferIdentities
    let fields = gpu.fieldBufferIdentities
    let saved = try gpu.observe(prepared)
    let output = gpu.observationBufferIdentities
    #expect(Set(mapped + fields + output).count == mapped.count + fields.count + output.count)
    let amplitudes: [Float] = (0..<257).map { Float(cos(Double($0) * 0.23) * 0.1) }
    var frames: [WaveObservationFrame] = []
    for start in stride(from: 0, to: 257, by: 128) {
      frames += try gpu.advance(
        source: source, amplitudes: Array(amplitudes[start..<min(start + 128, 257)]),
        observing: prepared)
    }
    var other: [WaveObservationFrame] = []
    for start in stride(from: 0, to: 257, by: 37) {
      other += try split.advance(
        source: source, amplitudes: Array(amplitudes[start..<min(start + 37, 257)]),
        observing: prepared)
    }
    try untouched.advance(source: source, amplitudes: amplitudes)
    #expect(
      frames.map(\.pressureOverDensity) == other.map(\.pressureOverDensity)
        && frames.map(\.projectedVelocity) == other.map(\.projectedVelocity))
    #expect(
      frames.count == 257 && frames[0].pressureStepIndex == 1
        && frames[256].pressureStepIndex == 257)
    #expect(
      arrays(try gpu.snapshot()).map { $0.map(\.bitPattern) }
        == arrays(try untouched.snapshot()).map { $0.map(\.bitPattern) })
    #expect(
      prepared.bufferIdentities == mapped && gpu.fieldBufferIdentities == fields
        && gpu.observationBufferIdentities == output)
    #expect(
      saved.pressureStepIndex == 0
        && saved.pressureOverDensity[0] == Double(initial.pressureOverDensity[0]))
    var a = WaveObservationAligner()
    var b = WaveObservationAligner()
    let first = try a.append(frames) + a.finishUsingFinalHalfStep()
    let second =
      try b.append(Array(other.prefix(11))) + b.append(Array(other.dropFirst(11)))
      + b.finishUsingFinalHalfStep()
    #expect(
      first.map(\.projectedVelocity) == second.map(\.projectedVelocity)
        && first.last?.usesTerminalHalfStep == true)
    let alternate = try gpu.prepareObservation(
      PreparedWaveObservation(grid: g, receivers: [metalReceiver(3)]))
    let changed = try gpu.observe(alternate)
    #expect(changed.pressureOverDensity.count == 1 && changed.projectedVelocity == [nil])
  }

  @Test(
    "Sparse nonfinite readout keeps completed clock and does not promise global finite certification"
  )
  func readFailure() throws {
    let g = try waveGrid()
    let device = try waveDevice()
    let maximum = Float.greatestFiniteMagnitude
    let gpu = try MetalWaveStepper(
      device: device, grid: g, initialFields: waveFields(Array(repeating: maximum, count: 8)))
    let receiver = WaveReceiverStencil(
      pressureCells: Array(repeating: 0, count: 8), pressureWeights: [2, 0, 0, 0, 0, 0, 0, 0])
    let plan = try gpu.prepareObservation(PreparedWaveObservation(grid: g, receivers: [receiver]))
    #expect(throws: WaveObservationError.nonfiniteResult(receiver: 0)) {
      try gpu.advance(steps: 1, observing: plan)
    }
    #expect(gpu.pressureStepIndex == 1)
    #expect(try gpu.snapshot().pressureOverDensity.allSatisfy { $0.isFinite })
  }

  @Test("Actual sampled submission failure acknowledges no unconfirmed batch")
  func completionFailure() throws {
    let g = try waveGrid()
    let device = try waveDevice()
    let gpu = try MetalWaveStepper(
      device: device, grid: g, initialFields: waveFields(Array(repeating: 1, count: 8)),
      completion: { commands in
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else {
          throw MetalWaveError.commandFailed("actual error")
        }
        throw MetalWaveError.commandFailed("injected sampled completion failure")
      })
    let plan = try gpu.prepareObservation(
      PreparedWaveObservation(grid: g, receivers: [metalReceiver()]))
    #expect(throws: MetalWaveError.commandFailed("injected sampled completion failure")) {
      try gpu.advance(steps: 7, observing: plan)
    }
    #expect(gpu.pressureStepIndex == 0)
    #expect(throws: WaveError.invalidatedState) { try gpu.observe(plan) }
  }

  @Test("Temporal alignment rejects combining different backend arithmetic")
  func precisionIdentity() throws {
    let g = try waveGrid()
    let device = try waveDevice()
    let initial = waveFields(Array(repeating: 1, count: 8))
    let raw = try PreparedWaveObservation(grid: g, receivers: [metalReceiver()])
    let gpu = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let cpu = try CPUWaveStepper(grid: g, initialFields: initial)
    let plan = try gpu.prepareObservation(raw)
    var align = WaveObservationAligner()
    _ = try align.append([cpu.observe(raw)])
    try gpu.advance()
    #expect(throws: WaveObservationError.inconsistentFrames) {
      try align.append([gpu.observe(plan)])
    }
  }
}
