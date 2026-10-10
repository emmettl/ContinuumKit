import Foundation
import LinearAcoustics
import Testing

@Suite("Prepared CPU pressure forcing") struct WaveForcingTests {
  @Test("Sparse destinations, finite coefficients and duplicate writes are checked")
  func preparation() throws {
    let g = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    for cell in [-1, 2, 8, Int.max] {
      #expect(throws: PressureSourceError.invalidCell(entry: 0, cell: cell)) {
        try PreparedPressureSource(grid: g, cellIndices: [cell], coefficients: [0])
      }
    }
    #expect(throws: PressureSourceError.duplicateCell(1)) {
      try PreparedPressureSource(grid: g, cellIndices: [1, 1], coefficients: [1, 0])
    }
    #expect(throws: WaveError.self) {
      try PreparedPressureSource(grid: g, cellIndices: [1], coefficients: [])
    }
    for value in [Float.nan, .infinity, -.infinity] {
      #expect(throws: PressureSourceError.nonfiniteCoefficient(entry: 0)) {
        try PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [value])
      }
    }
    let signed = try PreparedPressureSource(grid: g, cellIndices: [1, 0], coefficients: [-2, 0])
    #expect(signed.cellIndices == [1, 0] && signed.coefficients == [-2, 0])
  }

  @Test("Plans accept grid copies but reject separately prepared grids before mutation")
  func binding() throws {
    let g = try waveGrid()
    let copied = g
    let source = try PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [1])
    try source.validate(for: copied)
    let s = try CPUWaveStepper(
      grid: waveGrid(), initialFields: waveFields(Array(repeating: 0, count: 8)))
    let before = try s.snapshot()
    #expect(throws: PressureSourceError.gridMismatch) {
      try s.advance(source: source, amplitudes: [])
    }
    #expect(arrays(try s.snapshot()) == arrays(before) && s.pressureStepIndex == 0)
  }

  @Test("Hand-derived binary two-cell forcing follows pressure and precedes clock acknowledgement")
  func phases() throws {
    let g = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    let source = try PreparedPressureSource(grid: g, cellIndices: [1], coefficients: [0.5])
    let s = try CPUWaveStepper(
      grid: g, initialFields: waveFields([1, 0, 100, 100, 100, 100, 100, 100]))
    try s.advance(source: source, amplitudes: [2])
    let a = try s.snapshot()
    #expect(a.pressureOverDensity == [0.984375, 1.015625, 100, 100, 100, 100, 100, 100])
    #expect(a.velocityX == [0.125, 0, 0, 0, 0, 0, 0, 0])
    #expect(a.pressureTime == 0.125 && a.velocityTime == 0.0625)
    try s.advance(source: source, amplitudes: [-1])
    let b = try s.snapshot()
    #expect(b.pressureOverDensity == [0.96923828125, 0.53076171875, 100, 100, 100, 100, 100, 100])
    #expect(b.velocityX == [0.12109375, 0, 0, 0, 0, 0, 0, 0])
    #expect(b.pressureStepIndex == 2 && b.pressureTime == 0.25 && b.velocityTime == 0.1875)
  }

  @Test("Owned input and snapshots, empty batch, and arbitrary chunk composition")
  func composition() throws {
    let g = try waveGrid()
    var cells = [7, 0]
    var coefficients: [Float] = [-0.125, 0.25]
    let source = try PreparedPressureSource(grid: g, cellIndices: cells, coefficients: coefficients)
    cells[0] = 1
    coefficients[0] = 100
    let a = try CPUWaveStepper(grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let b = try CPUWaveStepper(grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let saved = try a.snapshot()
    try a.advance(source: source, amplitudes: [])
    #expect(arrays(try a.snapshot()) == arrays(saved) && a.pressureStepIndex == 0)
    let amplitudes: [Float] = [1, -2, 0.5, 0, 1.25]
    try a.advance(source: source, amplitudes: amplitudes)
    for value in amplitudes { try b.advance(source: source, amplitudes: [value]) }
    #expect(arrays(try a.snapshot()) == arrays(try b.snapshot()) && a.pressureStepIndex == 5)
    #expect(saved.pressureOverDensity.allSatisfy { $0 == 0 })
    #expect(source.cellIndices == [7, 0] && source.coefficients == [-0.125, 0.25])
  }

  @Test("All amplitudes and final clocks reject before any requested batch step")
  func rejectedBatch() throws {
    let g = try waveGrid()
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let source = try PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [1])
    for bad in [Float.nan, .infinity, -.infinity] {
      #expect(throws: PressureSourceError.nonfiniteAmplitude(step: 1)) {
        try s.advance(source: source, amplitudes: [1, bad])
      }
      let current = try s.snapshot()
      #expect(s.pressureStepIndex == 0 && current.pressureOverDensity.allSatisfy { $0 == 0 })
    }
    let enormous = try waveGrid(dt: 1e308, spacing: [1e308, 1e308, 1e308], speed: 1e-20)
    let clock = try CPUWaveStepper(
      grid: enormous, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let empty = try PreparedPressureSource(grid: enormous, cellIndices: [], coefficients: [])
    #expect(throws: WaveError.stepClockOverflow) {
      try clock.advance(source: empty, amplitudes: [0, 0])
    }
    #expect(clock.pressureStepIndex == 0)
  }

  @Test("Source arithmetic overflow invalidates after only acknowledged complete steps")
  func overflow() throws {
    let g = try waveGrid(mask: [1, 0, 0, 0, 0, 0, 0, 0])
    let source = try PreparedPressureSource(
      grid: g, cellIndices: [0], coefficients: [Float.greatestFiniteMagnitude])
    let s = try CPUWaveStepper(grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)))
    #expect(throws: WaveError.nonfiniteOutput) {
      try s.advance(source: source, amplitudes: [0, 2])
    }
    #expect(s.pressureStepIndex == 1)
    #expect(throws: WaveError.invalidatedState) { try s.snapshot() }
    #expect(throws: WaveError.invalidatedState) { try s.advance(source: source, amplitudes: []) }
  }

  @Test("An empty source plan leaves the source-free trajectory bit-exact")
  func emptyPlan() throws {
    let g = try waveGrid()
    let f = waveFields([1, -0.25, 0.5, 0, 0, 0, 0, 0])
    let a = try CPUWaveStepper(grid: g, initialFields: f)
    let b = try CPUWaveStepper(grid: g, initialFields: f)
    let empty = try PreparedPressureSource(grid: g, cellIndices: [], coefficients: [])
    try a.advance(steps: 13)
    try b.advance(source: empty, amplitudes: Array(repeating: -3, count: 13))
    #expect(
      arrays(try a.snapshot()).map { $0.map(\.bitPattern) }
        == arrays(try b.snapshot()).map { $0.map(\.bitPattern) })
  }

  @Test("Isolated damped cell agrees with signed affine recurrence and physical source/wall work")
  func isolated() throws {
    let mask: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]
    let beta: Float = 0.03125
    let g = try waveGrid(mask: mask, density: 1.7, faces: waveFaces([2, 2, 2], mask, loss: beta))
    let source = try PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [0.125])
    let s = try CPUWaveStepper(
      grid: g, initialFields: waveFields([1, 100, 100, 100, 100, 100, 100, 100]))
    let wall = 6 * Double(beta)
    let scale = g.density
    var analytic = 1.0
    var previous = 1.0
    var loss = 0.0
    var work = 0.0
    for amplitude: Float in [2, -3, 1, -0.5, 0, 0.75, -1, 3] {
      let pre = (1 - wall) / (1 + wall) * previous
      let increment = Double(amplitude) * 0.125
      analytic = (1 - wall) / (1 + wall) * analytic + increment
      try s.advance(source: source, amplitudes: [amplitude])
      let h = try s.snapshot()
      let current = Double(h.pressureOverDensity[0])
      #expect(abs(current - analytic) < 3e-7)
      loss += scale * 2 * wall * pow((previous + pre) / 2, 2)
      work += scale * (current - pre) * (current + pre) / 2
      #expect(abs(scale * current * current / 2 + loss - work - scale / 2) < 1e-6)
      #expect(h.pressureOverDensity.dropFirst().allSatisfy { $0 == 100 })
      #expect(
        h.velocityX.allSatisfy { $0 == 0 } && h.velocityY.allSatisfy { $0 == 0 }
          && h.velocityZ.allSatisfy { $0 == 0 })
      previous = current
    }
  }
}

@Suite("Independent forced wave references") struct ForcedWaveReferenceTests {
  @Test(
    "Manufactured anisotropic rigid lattice forcing converges in all four native fields",
    arguments: [CPUWaveExecution.serial, .parallel(slabs: 2)])
  func modal(execution: CPUWaveExecution) throws {
    let d: SIMD3<Int> = [8, 6, 4]
    let modes: SIMD3<Int> = [1, 2, 1]
    let spacing: SIMD3<Double> = [0.4, 0.7, 1.1]
    let speed = 1.3
    let frequency = 1.2
    let duration = 0.7
    let theta = SIMD3(Double.pi / Double(d.x), 2 * Double.pi / Double(d.y), Double.pi / Double(d.z))
    let kappa = SIMD3(
      2 * sin(theta.x / 2) / spacing.x, 2 * sin(theta.y / 2) / spacing.y,
      2 * sin(theta.z / 2) / spacing.z)
    let omegaSquared = speed * speed * (kappa.x * kappa.x + kappa.y * kappa.y + kappa.z * kappa.z)
    let count = d.x * d.y * d.z
    func position(_ at: Int) -> SIMD3<Int> { [at % d.x, at / d.x % d.y, at / (d.x * d.y)] }
    func mode(_ at: Int) -> Double {
      let xyz = position(at)
      return (0..<3).reduce(1.0) {
        $0 * cos(Double.pi * Double(modes[$1]) * (Double(xyz[$1]) + 0.5) / Double(d[$1]))
      }
    }
    func velocity(_ at: Int, _ axis: Int, _ time: Double) -> Double {
      let xyz = position(at)
      if xyz[axis] == d[axis] - 1 { return 0 }
      var shape = sin(theta[axis] * Double(xyz[axis] + 1))
      for other in 0..<3 where other != axis {
        shape *= cos(theta[other] * (Double(xyz[other]) + 0.5))
      }
      return kappa[axis] / frequency * (1 - cos(frequency * time)) * shape
    }
    var errors: [[Double]] = []
    for steps in [32, 64, 128] {
      let dt = duration / Double(steps)
      let g = try waveGrid(d, dt: dt, spacing: spacing, speed: speed)
      let source = try PreparedPressureSource(
        grid: g, cellIndices: Array(0..<count),
        coefficients: (0..<count).map { Float(dt * mode($0)) })
      let initial = waveFields(
        Array(repeating: 0, count: count),
        (0..<3).map { axis in (0..<count).map { Float(velocity($0, axis, -dt / 2)) } })
      let s = try CPUWaveStepper(grid: g, initialFields: initial, execution: execution)
      var num = Array(repeating: 0.0, count: 4)
      var den = num
      for step in 1...steps {
        let midpoint = (Double(step) - 0.5) * dt
        let force =
          frequency * cos(frequency * midpoint) + omegaSquared / frequency
          * (1 - cos(frequency * midpoint))
        try s.advance(source: source, amplitudes: [Float(force)])
        if step % (steps / 8) != 0 { continue }
        let h = try s.snapshot()
        let actual = arrays(h)
        for at in 0..<count {
          let expected =
            [sin(frequency * Double(step) * dt) * mode(at)]
            + (0..<3).map { velocity(at, $0, midpoint) }
          for field in 0..<4 {
            num[field] += pow(Double(actual[field][at]) - expected[field], 2)
            den[field] += expected[field] * expected[field]
          }
        }
        #expect(h.pressureStepIndex == step && h.velocityTime == midpoint)
      }
      errors.append((0..<4).map { sqrt(num[$0] / den[$0]) })
    }
    let orders = (0..<4).map { field in
      (0..<2).map { log2(errors[$0][field] / errors[$0 + 1][field]) }
    }
    print("FORCED_MODAL_ERRORS", errors, "ORDERS", orders)
    for field in 0..<4 {
      #expect(orders[field].allSatisfy { (1.7...2.3).contains($0) })
      #expect(errors[2][field] < 0.0005)
    }
  }

  @Test("Legacy post-wall forcing retains its measured first-order damped-continuum time error")
  func dampedContinuum() throws {
    let rate = 0.8
    let force = 0.7
    let duration = 1.0
    let initial = 0.3
    let expected = initial * exp(-rate * duration) + force / rate * (1 - exp(-rate * duration))
    let mask: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]
    var errors: [Double] = []
    for steps in [32, 64, 128] {
      let dt = duration / Double(steps)
      var faces = waveFaces([2, 2, 2], mask)
      faces[0] = Float(rate * dt / 2)
      let g = try waveGrid(mask: mask, dt: dt, faces: faces)
      let source = try PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [Float(dt)])
      let s = try CPUWaveStepper(
        grid: g, initialFields: waveFields([Float(initial), 0, 0, 0, 0, 0, 0, 0]))
      try s.advance(source: source, amplitudes: Array(repeating: Float(force), count: steps))
      let result = Double(try s.snapshot().pressureOverDensity[0])
      let ratio = (1 - rate * dt / 2) / (1 + rate * dt / 2)
      let discrete =
        pow(ratio, Double(steps)) * initial + dt * force * (1 - pow(ratio, Double(steps)))
        / (1 - ratio)
      #expect(abs(result - discrete) < 2e-6)
      errors.append(abs(result - expected))
    }
    let orders = (0..<2).map { log2(errors[$0] / errors[$0 + 1]) }
    print("FORCED_DAMPED_ERRORS", errors, "ORDERS", orders)
    #expect(orders.allSatisfy { (0.9...1.1).contains($0) })
    #expect(errors[2] < 0.002)
  }

  @Test(
    "Connected heterogeneous walls and signed forcing close the complete modified-energy ledger")
  func ledger() throws {
    let d: SIMD3<Int> = [4, 3, 2]
    let spacing: SIMD3<Double> = [1, 0.8, 1.3]
    let speed = 1.7
    let dt = 0.025
    let density = 1.23
    let mask: [UInt8] = (0..<24).map { [3, 7, 16].contains($0) ? 0 : 1 }
    var faces = waveFaces(d, mask)
    for at in 0..<24 where mask[at] == 1 {
      for side in 0..<6 where faces[side * 24 + at] >= 0 {
        faces[side * 24 + at] = Float(0.1 * Double(side + 1) * dt / 2)
      }
    }
    let g = try waveGrid(
      d, mask: mask, dt: dt, spacing: spacing, speed: speed, density: density, faces: faces)
    let source = try PreparedPressureSource(
      grid: g, cellIndices: [0, 11, 22], coefficients: [0.03125, -0.0625, 0.015625])
    let s = try CPUWaveStepper(
      grid: g,
      initialFields: waveFields(
        (0..<24).map { mask[$0] == 0 ? 100 : Float(cos(Double($0) * 0.43)) }))
    let strides = [1, d.x, d.x * d.y]
    let scale = density * spacing.x * spacing.y * spacing.z
    func energy(_ h: WaveSnapshot) -> Double {
      let f = arrays(h)
      var result = 0.0
      for at in 0..<24 where mask[at] == 1 {
        result += Double(f[0][at]) * Double(f[0][at]) / (2 * speed * speed)
        for axis in 0..<3 where faces[(2 * axis + 1) * 24 + at] == -1 {
          let u = Double(f[axis + 1][at])
          result +=
            u * u / 2 - dt / (2 * spacing[axis]) * u
            * (Double(f[0][at + strides[axis]]) - Double(f[0][at]))
        }
      }
      return scale * result
    }
    var previous = try s.snapshot()
    var loss = 0.0
    var work = 0.0
    var pressureOnly = 0.0
    var maximum = 0.0
    let initial = energy(previous)
    for step in 0..<64 {
      // Observe the actual pre-injection phase using the already independently verified source-free update.
      let phase = try CPUWaveStepper(
        grid: g,
        initialFields: waveFields(previous.pressureOverDensity, Array(arrays(previous).dropFirst()))
      )
      try phase.advance()
      let pre = try phase.snapshot()
      try s.advance(source: source, amplitudes: [Float(0.7 * sin(Double(step) * 0.47) - 0.2)])
      let current = try s.snapshot()
      let velocities = arrays(current)
      let delta = (0..<24).map {
        Double(current.pressureOverDensity[$0]) - Double(pre.pressureOverDensity[$0])
      }
      var jump = 0.0
      var cross = 0.0
      for at in 0..<24 where mask[at] == 1 {
        let wall = (0..<6).reduce(0.0) { $0 + max(0, Double(faces[$1 * 24 + at])) }
        loss +=
          scale * 2 * wall
          * pow(
            (Double(previous.pressureOverDensity[at]) + Double(pre.pressureOverDensity[at])) / 2, 2)
          / (speed * speed)
        jump +=
          delta[at]
          * (Double(current.pressureOverDensity[at]) + Double(pre.pressureOverDensity[at]))
          / (2 * speed * speed)
        for axis in 0..<3 where faces[(2 * axis + 1) * 24 + at] == -1 {
          cross -=
            dt / (2 * spacing[axis]) * Double(velocities[axis + 1][at])
            * (delta[at + strides[axis]] - delta[at])
        }
      }
      pressureOnly += scale * jump
      work += scale * (jump + cross)
      maximum = max(maximum, abs((energy(current) + loss - work) / initial - 1))
      #expect(maximum < 2e-6)
      previous = current
    }
    let omittedCrossError = abs((energy(previous) + loss - pressureOnly) / initial - 1)
    print("FORCED_LEDGER_MAX", maximum, "OMITTED_CROSS_ERROR", omittedCrossError)
    #expect(omittedCrossError > 1e-5)
  }
}
