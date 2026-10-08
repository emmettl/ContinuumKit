import BenchmarkSupport
import Foundation
import Testing

@Suite("Independent dissipative time reference") struct DissipativeLatticeTests {
  @Test("Single cell is exact exponential decay, including a negative half clock")
  func decay() throws {
    let lattice = try DissipativeLattice(cells: 1, speed: 2, dx: 0.5, impedance: 3)
    for t in [-0.01, 0, 0.25, 2] {
      let y = try lattice.evolve([1], time: t)
      #expect(abs(y[0] - exp(-4 * t / 3)) < 2e-14)
    }
  }
  @Test("Closed two-cell oscillator preserves its mean and energy") func oscillator() throws {
    let lattice = try DissipativeLattice(cells: 2, speed: 1, dx: 1, impedance: nil)
    let y = try lattice.evolve([1, 0, 0], time: .pi / (2 * sqrt(2.0)))
    #expect(abs(y[0] - 0.5) < 2e-14 && abs(y[1] - 0.5) < 2e-14)
    #expect(abs(y[2] - 1 / sqrt(2.0)) < 2e-14)
    #expect(abs(y.reduce(0) { $0 + $1 * $1 } - 1) < 3e-14)
  }
  @Test("Dissipative energy loss equals independently integrated wall work") func work() throws {
    let lattice = try DissipativeLattice(cells: 3, speed: 1, dx: 1, impedance: 0.5)
    let initial = [1.0, 0.5, 0.25, 0, 0]
    let count = 256
    let dt = 0.5 / Double(count)
    var work = 0.0
    var previousEnergy = initial.reduce(0) { $0 + $1 * $1 }
    for i in 0...count {
      let y = try lattice.evolve(initial, time: Double(i) * dt)
      let e = y.reduce(0) { $0 + $1 * $1 }
      #expect(e <= previousEnergy + 1e-14)
      previousEnergy = e
      let weight = i == 0 || i == count ? 1.0 : (i.isMultiple(of: 2) ? 2 : 4)
      work += weight * 4 * y[2] * y[2] * dt / 3
    }
    #expect(abs(initial.reduce(0) { $0 + $1 * $1 } - previousEnergy - work) < 2e-11)
  }
  @Test("Evolution composes and has the independently specified operator derivative")
  func composition() throws {
    let lattice = try DissipativeLattice(cells: 2, speed: 1, dx: 1, impedance: 2)
    let initial = [1.0, 0.25, -0.125]
    let direct = try lattice.evolve(initial, time: 0.7)
    let split = try lattice.evolve(lattice.evolve(initial, time: 0.3), time: 0.4)
    #expect(zip(direct, split).allSatisfy { abs($0 - $1) < 2e-14 })
    let dt = 1e-5
    let plus = try lattice.evolve(initial, time: dt)
    let minus = try lattice.evolve(initial, time: -dt)
    let derivative = [0.125, -0.25, 0.75]
    for i in initial.indices {
      #expect(abs((plus[i] - minus[i]) / (2 * dt) - derivative[i]) < 1e-10)
    }
  }
  @Test("Invalid dimensions, impedance, nonfinite and excessive clocks fail") func invalid() throws
  {
    #expect(throws: BenchmarkFailure.self) {
      try DissipativeLattice(cells: 0, speed: 1, dx: 1, impedance: 1)
    }
    #expect(throws: BenchmarkFailure.self) {
      try DissipativeLattice(cells: 2, speed: 1, dx: 1, impedance: .infinity)
    }
    let lattice = try DissipativeLattice(cells: 2, speed: 1, dx: 1, impedance: 1)
    for state in [[1.0, 0], [1, 0, .nan]] {
      #expect(throws: BenchmarkFailure.self) { try lattice.evolve(state, time: 1) }
    }
    for t in [Double.infinity, 1e10] {
      #expect(throws: BenchmarkFailure.self) { try lattice.evolve([1, 0, 0], time: t) }
    }
  }
  @Test("Correct pressures cannot conceal missing boundary work") func missingWork() throws {
    let c = try BoundaryAcousticCase.standard()[3]
    let r = BoundaryResolution.standard(c).last!
    let h = try BoundaryOracle.temporalHistory(c, r)
    let broken = BoundaryHistory(
      dx: h.dx, dy: h.dy, dt: h.dt,
      frames: h.frames.map {
        BoundaryFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v)
      })
    let env = BenchmarkEnvironment(
      repository: "test", revision: "test", sourceHashes: [:],
      hardware: "test", toolchain: "test", operatingSystem: "test")
    let result = try BoundaryResult.evaluate(
      model: "missing-work", c: c, r: r,
      environment: env, runtime: 0, h: broken)
    #expect(result.errors!.pressureL2 == 0 && result.errors!.dissipationError! > 0.7)
    #expect(throws: BenchmarkFailure.self) { try BoundaryCommand.bounds(result) }
  }
  @Test("A first-order temporal history cannot pass the independent refinement gate")
  func firstOrder() throws {
    let c = try BoundaryAcousticCase.standard()[2]
    let env = BenchmarkEnvironment(
      repository: "test", revision: "test", sourceHashes: [:],
      hardware: "test", toolchain: "test", operatingSystem: "test")
    let runs = try BoundaryResolution.standard(c).filter { $0.axis == "impedance-time" }.map { r in
      let h = try BoundaryOracle.temporalHistory(c, r)
      let factor = 1 + 0.1 * 360 / Double(r.steps)
      let broken = BoundaryHistory(
        dx: h.dx, dy: h.dy, dt: h.dt,
        frames: h.frames.map {
          BoundaryFrame(
            step: $0.step, p: $0.p.map { $0 * factor }, u: $0.u, v: $0.v,
            dissipation: $0.dissipation)
        })
      return try BoundaryResult.evaluate(
        model: "first-order", c: c, r: r,
        environment: env, runtime: 0, h: broken)
    }
    #expect(throws: BenchmarkFailure.self) { try BoundaryCommand.check(runs) }
  }

}
