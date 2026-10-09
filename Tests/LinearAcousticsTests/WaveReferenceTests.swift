import BenchmarkSupport
import Foundation
import LinearAcoustics
import Testing

func nativeVelocity(_ field: Int, _ values: [Double], _ d: SIMD3<Int>) -> [Float] {
  var shape = d
  shape[field] += 1
  return (0..<(d.x * d.y * d.z)).map { at in
    var xyz = SIMD3(at % d.x, at / d.x % d.y, at / (d.x * d.y))
    xyz[field] += 1
    return Float(values[xyz.x + shape.x * (xyz.y + shape.y * xyz.z)])
  }
}
func referenceFields(_ initial: RigidModeFrame, _ d: SIMD3<Int>, _ density: Double)
  -> WaveInitialFields
{
  waveFields(
    initial.p.map { Float($0 / density) },
    (0..<3).map { nativeVelocity($0, initial.fields[$0 + 1], d) })
}

@Suite("Independent complete-field wave references") struct WaveReferenceTests {
  @Test("All-active anisotropic 3D masked path converges in every field against rigid-mode oracle")
  func rigidThreeDimensions() throws {
    for c in try RigidModeCase.standard() {
      let d: SIMD3<Int> = [16, 8, c.anisotropicGrid ? 4 : 8]
      let spacing = SIMD3(
        c.lengths[0] / Double(d.x), c.lengths[1] / Double(d.y), c.lengths[2] / Double(d.z))
      var errors: [[Double]] = []
      for steps in [64, 128, 256] {
        let r = RigidModeResolution(axis: "time", nx: d.x, ny: d.y, nz: d.z, steps: steps)
        let dt = c.duration / Double(steps)
        let initial = RigidModeOracle.initial(
          c, r, spacing: [spacing.x, spacing.y, spacing.z], dt: dt)
        let expected = RigidModeOracle.history(c, r, dt: dt)
        let stepper = try CPUWaveStepper(
          grid: waveGrid(d, dt: dt, spacing: spacing, speed: c.speed, density: c.density),
          initialFields: referenceFields(initial, d, c.density))
        var numerator = [Double](repeating: 0, count: 4)
        var denominator = numerator
        var previous = 0
        for frame in expected.frames {
          try stepper.advance(steps: frame.step - previous)
          previous = frame.step
          let h = try stepper.snapshot()
          let actual = arrays(h).map { $0.map(Double.init) }
          let reference =
            [frame.p.map { $0 / c.density }]
            + (0..<3).map { nativeVelocity($0, frame.fields[$0 + 1], d).map(Double.init) }
          for f in 0..<4 {
            for i in actual[f].indices {
              numerator[f] += pow(actual[f][i] - reference[f][i], 2)
              denominator[f] += pow(reference[f][i], 2)
            }
          }
          #expect(h.pressureStepIndex == frame.step)
        }
        errors.append((0..<4).map { sqrt(numerator[$0] / denominator[$0]) })
      }
      for f in 0..<4 {
        let orders = (0..<2).map { log2(errors[$0][f] / errors[$0 + 1][f]) }
        #expect(orders.allSatisfy { (1.7...2.3).contains($0) })
        #expect(errors[2][f] < 0.001)
      }
    }
  }
  @Test(
    "Masked off-origin and split chambers preserve padding and converge against independent modes")
  func maskedModes() throws {
    for c in try MaskedModeCase.standard() {
      let r = MaskedModeResolution(axis: "time", nx: 16, ny: 8, nz: 8, steps: 256)
      let g = try MaskedGrid(c, r)
      let d = SIMD3(r.nx, r.ny, r.nz)
      let dt = c.duration / Double(r.steps)
      let spacing = SIMD3(g.spacing[0], g.spacing[1], g.spacing[2])
      let initial = try MaskedModeOracle.initial(c, r, spacing: g.spacing, dt: dt)
      let stepper = try CPUWaveStepper(
        grid: waveGrid(
          d, mask: g.inside, dt: dt, spacing: spacing, speed: c.speed, density: c.density,
          faces: g.faces),
        initialFields: referenceFields(initial, d, c.density))
      let expected = try MaskedModeOracle.history(c, r)
      var num = [Double](repeating: 0, count: 4)
      var den = num
      var last = 0
      for frame in expected.frames {
        try stepper.advance(steps: frame.step - last)
        last = frame.step
        let h = arrays(try stepper.snapshot())
        let reference =
          [frame.p.map { Float($0 / c.density) }]
          + (0..<3).map { nativeVelocity($0, frame.fields[$0 + 1], d) }
        for i in 0..<g.labels.count {
          if g.labels[i] < 0 {
            #expect(h[0][i] == Float(c.inactivePressure / c.density))
          } else {
            for f in 0..<4 {
              num[f] += pow(Double(h[f][i]) - Double(reference[f][i]), 2)
              den[f] += pow(Double(reference[f][i]), 2)
            }
          }
        }
      }
      #expect((0..<4).allSatisfy { sqrt(num[$0] / den[$0]) < 0.001 })
    }
  }
  @Test("Heterogeneous dissipative graph has second-order complete-field time convergence")
  func dissipativeGraph() throws {
    let d: SIMD3<Int> = [4, 3, 2]
    let spacing: SIMD3<Double> = [1, 0.8, 1.3]
    let c = 1.7
    let mask: [UInt8] = (0..<24).map { [3, 7, 16].contains($0) ? 0 : 1 }
    let closed = waveFaces(d, mask)
    let rates: [Double] = (0..<24).map { at in
      mask[at] == 0
        ? 0 : (0..<6).reduce(0.0) { $0 + (closed[$1 * 24 + at] < 0 ? 0 : 0.1 * Double($1 + 1)) }
    }
    let lattice = try MaskedLattice(
      dimensions: [d.x, d.y, d.z], spacing: [spacing.x, spacing.y, spacing.z], inside: mask,
      speed: c, wallRates: rates)
    var initial = [Double](repeating: 0, count: lattice.stateCount)
    for i in lattice.cells.indices { initial[i] = cos(Double(i) * 0.43) }
    var errors: [[Double]] = []
    for steps in [32, 64, 128] {
      let dt = 0.5 / Double(steps)
      var faces = closed
      for at in 0..<24 where mask[at] == 1 {
        for side in 0..<6 where faces[side * 24 + at] >= 0 {
          faces[side * 24 + at] = Float(0.1 * Double(side + 1) * dt / 2)
        }
      }
      let minus = try lattice.evolve(initial, time: -dt / 2)
      var p = [Float](repeating: 100, count: 24)
      var v = Array(repeating: [Float](repeating: 0, count: 24), count: 3)
      for i in lattice.cells.indices { p[lattice.cells[i]] = Float(initial[i]) }
      for (i, e) in lattice.edges.enumerated() {
        v[e.axis][e.cell] = Float(minus[lattice.cells.count + i] / c)
      }
      let s = try CPUWaveStepper(
        grid: waveGrid(d, mask: mask, dt: dt, spacing: spacing, speed: c, faces: faces),
        initialFields: waveFields(p, v))
      var num = [Double](repeating: 0, count: 4)
      var den = num
      var previous = 0
      for capture in 1...8 {
        let step = capture * steps / 8
        try s.advance(steps: step - previous)
        previous = step
        let h = arrays(try s.snapshot())
        let time = Double(step) * dt
        let pressure = try lattice.evolve(initial, time: time)
        let velocity = try lattice.evolve(initial, time: time - dt / 2)
        for i in lattice.cells.indices {
          num[0] += pow(Double(h[0][lattice.cells[i]]) - pressure[i], 2)
          den[0] += pow(pressure[i], 2)
        }
        for (i, e) in lattice.edges.enumerated() {
          let exact = velocity[lattice.cells.count + i] / c
          num[e.axis + 1] += pow(Double(h[e.axis + 1][e.cell]) - exact, 2)
          den[e.axis + 1] += exact * exact
        }
        for at in 0..<24 where mask[at] == 0 { #expect(h[0][at] == 100) }
      }
      errors.append((0..<4).map { sqrt(num[$0] / den[$0]) })
    }
    for f in 0..<4 {
      #expect((0..<2).allSatisfy { (1.7...2.3).contains(log2(errors[$0][f] / errors[$0 + 1][f])) })
      #expect(errors[2][f] < 0.0003)
    }
  }
}

@Suite("Complete grid energy ledger") struct WaveEnergyTests {
  @Test("Heterogeneous walls account for all lost staggered modified energy")
  func budget() throws {
    let d: SIMD3<Int> = [4, 3, 2]
    let spacing: SIMD3<Double> = [1, 0.8, 1.3]
    let speed = 1.7
    let dt = 0.025
    let mask: [UInt8] = (0..<24).map { [3, 7, 16].contains($0) ? 0 : 1 }
    var faces = waveFaces(d, mask)
    for at in 0..<24 where mask[at] == 1 {
      for side in 0..<6 where faces[side * 24 + at] >= 0 {
        faces[side * 24 + at] = Float(0.1 * Double(side + 1) * dt / 2)
      }
    }
    let grid = try waveGrid(d, mask: mask, dt: dt, spacing: spacing, speed: speed, faces: faces)
    let p: [Float] = (0..<24).map { mask[$0] == 0 ? 100 : Float(cos(Double($0) * 0.43)) }
    let stepper = try CPUWaveStepper(grid: grid, initialFields: waveFields(p))
    func energy(_ h: WaveSnapshot) -> Double {
      let f = arrays(h)
      let stride = [1, d.x, d.x * d.y]
      var e = 0.0
      for at in 0..<24 where mask[at] == 1 {
        e += Double(f[0][at]) * Double(f[0][at]) / (2 * speed * speed)
        for axis in 0..<3 where faces[(2 * axis + 1) * 24 + at] == -1 {
          let minus = Double(f[axis + 1][at])
          let plus =
            minus - dt / spacing[axis] * (Double(f[0][at + stride[axis]]) - Double(f[0][at]))
          e += minus * plus / 2
        }
      }
      return e
    }
    var previous = try stepper.snapshot()
    var work = 0.0
    let e0 = energy(previous)
    for _ in 0..<32 {
      try stepper.advance()
      let current = try stepper.snapshot()
      for at in 0..<24 where mask[at] == 1 {
        let wall = (0..<6).reduce(0.0) { $0 + max(0, Double(faces[$1 * 24 + at])) }
        let mean =
          (Double(previous.pressureOverDensity[at]) + Double(current.pressureOverDensity[at])) / 2
        work += 2 * wall * mean * mean / (speed * speed)
      }
      #expect(abs((energy(current) + work) / e0 - 1) < 2e-6)
      previous = current
    }
  }
}
