import LinearAcoustics
import Testing

@Suite("Synchronous CPU wave execution") struct WaveExecutionTests {
  func bits(_ snapshot: WaveSnapshot) -> [[UInt32]] {
    arrays(snapshot).map { $0.map(\.bitPattern) }
  }

  @Test("Traversal selection rejects invalid slab counts before field construction")
  func selection() throws {
    let grid = try waveGrid([3, 3, 5])
    let fields = waveFields(Array(repeating: 0, count: grid.cellCount))
    let serial = try CPUWaveStepper(grid: grid, initialFields: fields)
    #expect(serial.execution == .serial && serial.slabCount == 1)
    for count in [0, -1, 6, Int.max] {
      #expect(throws: WaveError.invalidSlabCount) {
        try CPUWaveStepper(grid: grid, initialFields: fields, execution: .parallel(slabs: count))
      }
    }
    let single = try CPUWaveStepper(
      grid: grid, initialFields: fields, execution: .parallel(slabs: 1))
    #expect(single.slabCount == 1 && single.execution == .parallel(slabs: 1))
    let before = try single.snapshot()
    try single.advance(steps: 0)
    #expect(bits(try single.snapshot()) == bits(before) && single.pressureStepIndex == 0)
  }

  @Test("Hand-derived axial pressure ramp crosses every uneven slab boundary")
  func axialRamp() throws {
    let d: SIMD3<Int> = [2, 2, 5]
    let grid = try waveGrid(d, dt: 0.125)
    let pressure = (0..<grid.cellCount).map { Float($0 / 4) }
    let stepper = try CPUWaveStepper(
      grid: grid, initialFields: waveFields(pressure), execution: .parallel(slabs: 3))
    try stepper.advance()
    let result = try stepper.snapshot()
    for at in 0..<grid.cellCount {
      let z = at / 4
      #expect(
        result.pressureOverDensity[at] == pressure[at]
          + (z == 0 ? 0.015625 : z == 4 ? -0.015625 : 0))
      #expect(result.velocityX[at] == 0 && result.velocityY[at] == 0)
      #expect(result.velocityZ[at] == (z == 4 ? 0 : -0.125))
    }
    #expect(
      result.pressureStepIndex == 1 && result.pressureTime == 0.125 && result.velocityTime == 0.0625
    )
  }

  @Test(
    "Every native field and retained forced receiver frame is bit-exact for uneven partitions",
    arguments: [1, 2, 3, 5])
  func completeHistory(slabs: Int) throws {
    let d: SIMD3<Int> = [7, 4, 5]
    let count = d.x * d.y * d.z
    let mask: [UInt8] = (0..<count).map { [8, 31, 40, 61, 96].contains($0) ? 0 : 1 }
    var faces = waveFaces(d, mask)
    for at in 0..<count where mask[at] == 1 {
      for side in 0..<6 where faces[side * count + at] >= 0 {
        faces[side * count + at] = Float((at + side) % 4) / 128
      }
    }
    let grid = try waveGrid(d, mask: mask, dt: 0.03125, spacing: [1, 1.2, 0.9], faces: faces)
    let initial = waveFields(
      (0..<count).map { mask[$0] == 1 ? Float($0 % 9 - 4) / 32 : Float.greatestFiniteMagnitude })
    let serial = try CPUWaveStepper(grid: grid, initialFields: initial)
    let parallel = try CPUWaveStepper(
      grid: grid, initialFields: initial, execution: .parallel(slabs: slabs))
    let source = try PreparedPressureSource(
      grid: grid, cellIndices: [0, 1, 60], coefficients: [0.125, -0.0625, 0])
    let probe = try PreparedWaveObservation(
      grid: grid,
      receivers: [
        WaveReceiverStencil(
          pressureCells: Array(repeating: 0, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0]),
        WaveReceiverStencil(
          pressureCells: [36, 37, 43, 44, 64, 65, 71, 72],
          pressureWeights: [0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125, 0.125],
          velocityCell: 36, velocityAxis: [0.4, -0.7, 0.2]),
      ])
    let saved = try parallel.snapshot()
    for step in 0..<257 {
      let amplitude = Float(step % 7 - 3) / 64
      let a = try serial.advance(source: source, amplitudes: [amplitude], observing: probe)
      let b = try parallel.advance(source: source, amplitudes: [amplitude], observing: probe)
      #expect(bits(try serial.snapshot()) == bits(try parallel.snapshot()))
      #expect(
        a[0].pressureOverDensity.map(\.bitPattern) == b[0].pressureOverDensity.map(\.bitPattern))
      #expect(
        a[0].projectedVelocity.map { $0?.bitPattern }
          == b[0].projectedVelocity.map { $0?.bitPattern })
      #expect(b[0].pressureStepIndex == step + 1 && parallel.pressureStepIndex == step + 1)
      for at in 0..<count where mask[at] == 0 {
        #expect((try parallel.snapshot()).pressureOverDensity[at] == Float.greatestFiniteMagnitude)
      }
    }
    #expect(
      saved.pressureStepIndex == 0 && saved.pressureOverDensity == initial.pressureOverDensity)
  }

  @Test("Merged finite certificate rejects velocity overflow before clock acknowledgement")
  func velocityFailure() throws {
    let grid = try waveGrid([3, 3, 5])
    var p = [Float](repeating: 0, count: grid.cellCount)
    p[27] = .greatestFiniteMagnitude
    p[28] = -.greatestFiniteMagnitude
    for execution in [CPUWaveExecution.serial, .parallel(slabs: 3)] {
      let s = try CPUWaveStepper(grid: grid, initialFields: waveFields(p), execution: execution)
      #expect(throws: WaveError.nonfiniteOutput) { try s.advance() }
      #expect(s.pressureStepIndex == 0)
      #expect(throws: WaveError.invalidatedState) { try s.snapshot() }
      #expect(throws: WaveError.invalidatedState) { try s.advance(steps: 0) }
    }
  }

  @Test("Pressure overflow remains rejected after all parallel phases")
  func pressureFailure() throws {
    let d: SIMD3<Int> = [3, 3, 5]
    let count = 45
    var mask = [UInt8](repeating: 0, count: count)
    mask[22] = 1
    var faces = waveFaces(d, mask)
    for side in 0..<6 { faces[side * count + 22] = 2 }
    let grid = try waveGrid(d, mask: mask, faces: faces)
    var p = [Float](repeating: 0, count: count)
    p[22] = .greatestFiniteMagnitude
    let s = try CPUWaveStepper(
      grid: grid, initialFields: waveFields(p), execution: .parallel(slabs: 3))
    #expect(throws: WaveError.nonfiniteOutput) { try s.advance() }
    #expect(s.pressureStepIndex == 0)
    #expect(throws: WaveError.invalidatedState) { try s.snapshot() }
  }

  @Test("Sparse source overflow preserves only earlier acknowledged steps")
  func sourceFailure() throws {
    let grid = try waveGrid([3, 3, 5])
    let source = try PreparedPressureSource(
      grid: grid, cellIndices: [36], coefficients: [.greatestFiniteMagnitude])
    let s = try CPUWaveStepper(
      grid: grid, initialFields: waveFields(Array(repeating: 0, count: grid.cellCount)),
      execution: .parallel(slabs: 3))
    #expect(throws: WaveError.nonfiniteOutput) {
      try s.advance(source: source, amplitudes: [0, .greatestFiniteMagnitude])
    }
    #expect(s.pressureStepIndex == 1)
    #expect(throws: WaveError.invalidatedState) { try s.snapshot() }
  }

  @Test("Finite field certification stays distinct from sparse readout overflow")
  func readoutFailure() throws {
    let grid = try waveGrid([3, 3, 5], dt: 0.001)
    let count = grid.cellCount
    var u = [Float](repeating: 0, count: count)
    u[12] = .greatestFiniteMagnitude
    u[13] = .greatestFiniteMagnitude
    let s = try CPUWaveStepper(
      grid: grid,
      initialFields: waveFields(
        Array(repeating: 0, count: count),
        [u, Array(repeating: 0, count: count), Array(repeating: 0, count: count)]),
      execution: .parallel(slabs: 3))
    let observation = try PreparedWaveObservation(
      grid: grid,
      receivers: [
        WaveReceiverStencil(
          pressureCells: Array(repeating: 13, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0],
          velocityCell: 13, velocityAxis: [1, 0, 0])
      ])
    #expect(throws: WaveObservationError.nonfiniteResult(receiver: 0)) {
      try s.advance(steps: 1, observing: observation)
    }
    #expect(s.pressureStepIndex == 1)
    #expect(arrays(try s.snapshot()).allSatisfy { $0.allSatisfy(\.isFinite) })
  }

  @Test("Whole-batch input rejection and retained multi-call histories preserve parallel state")
  func batchContract() throws {
    let grid = try waveGrid([3, 3, 5])
    let initial = waveFields(Array(repeating: 0, count: grid.cellCount))
    let s = try CPUWaveStepper(grid: grid, initialFields: initial, execution: .parallel(slabs: 3))
    let source = try PreparedPressureSource(grid: grid, cellIndices: [0], coefficients: [1])
    let observation = try PreparedWaveObservation(
      grid: grid,
      receivers: [
        WaveReceiverStencil(
          pressureCells: Array(repeating: 0, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0])
      ])
    let before = try s.snapshot()
    #expect(throws: PressureSourceError.nonfiniteAmplitude(step: 1)) {
      try s.advance(source: source, amplitudes: [1, .nan], observing: observation)
    }
    #expect(throws: WaveObservationError.batchTooLarge) {
      try s.advance(steps: 129, observing: observation)
    }
    #expect(bits(try s.snapshot()) == bits(before) && s.pressureStepIndex == 0)
    let retained = try s.advance(source: source, amplitudes: [1, -1], observing: observation)
    let firstBits = retained.map { $0.pressureOverDensity.map(\.bitPattern) }
    _ = try s.advance(steps: 128, observing: observation)
    #expect(retained.map { $0.pressureOverDensity.map(\.bitPattern) } == firstBits)
    #expect(s.pressureStepIndex == 130)
  }
}
