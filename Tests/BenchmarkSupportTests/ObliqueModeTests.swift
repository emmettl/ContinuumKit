import Foundation
import Testing

@testable import BenchmarkSupport

@Suite("Independent oblique impedance modes") struct ObliqueModeTests {
  let env = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test",
    operatingSystem: "test")
  @Test("Eigenvalues and reflection agree with independent 60-digit roots") func goldens() throws {
    let reference = try ObliqueModeReference(ObliqueModeCase(id: "positive", impedance: 3))
    #expect(abs(reference.kx.real * 0.25 - 6.30715255106200467305) < 2e-13)
    #expect(abs(reference.kx.imag * 0.25 + 0.50803332703282437298) < 2e-13)
    #expect(abs(reference.rate.real + 461.0672311031544059) < 2e-8)
    #expect(abs(reference.reflection.real - 0.3616002526182491374) < 2e-13)
    #expect(abs(reference.reflection.imag + 0.0173464106237609859) < 2e-13)
    let inverted = try ObliqueModeReference(ObliqueModeCase(id: "inverted", impedance: 0.5))
    #expect(abs(inverted.kx.real * 0.25 - 7.8445337994341921268) < 2e-13)
    #expect(abs(inverted.kx.imag * 0.25 + 0.4125154360256583012) < 2e-13)
    #expect(abs(inverted.reflection.real + 0.4381432331100583163) < 2e-13)
    #expect(abs(inverted.reflection.imag + 0.00827999501342354594) < 2e-13)
    for ref in [reference, inverted] {
      let image = (-ObliqueComplex.i * ref.kx * ObliqueComplex(0.5)).exp
      #expect((image - ref.reflection).magnitude < 2e-13)
    }
  }
  @Test("Real fields satisfy the east impedance and rigid side conditions") func boundary() throws {
    for c in try ObliqueModeCase.standard() {
      let ref = try ObliqueModeReference(c)
      for fraction in [0.0, 0.125, 0.37, 0.8, 1] {
        let t = ref.duration * fraction
        let wall = ref.state(x: 0.25, y: 0.03125, time: t)
        #expect(abs(wall.p - c.density * c.speed * c.impedance * wall.u) < 2e-13)
        #expect(abs(ref.state(x: 0, y: 0.04, time: t).u) < 1e-15)
        #expect(abs(ref.state(x: 0.09, y: 0, time: t).v) < 1e-15)
        #expect(abs(ref.state(x: 0.09, y: 0.125, time: t).v) < 1e-15)
      }
    }
  }
  @Test("Independent Simpson energy and wall-work integrals match the analytic budgets")
  func integrals() throws {
    for c in try ObliqueModeCase.standard() {
      let ref = try ObliqueModeReference(c)
      for fraction in [0.0, 0.23, 1] {
        let time = ref.duration * fraction
        let count = 1024
        let dx = c.lengthX / Double(count)
        var energy = 0.0
        var work = 0.0
        for i in 0...count {
          let weight = i == 0 || i == count ? 1.0 : (i.isMultiple(of: 2) ? 2 : 4)
          let x = Double(i) * dx
          let p = ref.state(x: x, y: 0, time: time)
          let v = ref.state(x: x, y: c.lengthY / 2, time: time).v
          energy +=
            weight * dx / 3 * c.lengthY / 4
            * (p.p * p.p / (c.density * c.speed * c.speed) + c.density * (p.u * p.u + v * v))
          let t = time * Double(i) / Double(count)
          let wall = ref.state(x: c.lengthX, y: 0, time: t).p
          work +=
            weight * time / Double(count) / 3 * c.lengthY / 2 * wall * wall
            / (c.density * c.speed * c.impedance)
        }
        #expect(abs(energy / ref.energy(time: time) - 1) < 1e-8)
        #expect(
          abs((ref.energy(time: time) + ref.dissipated(time: time)) / ref.energy(time: 0) - 1)
            < 2e-12)
        #expect(abs((work - ref.dissipated(time: time)) / ref.energy(time: 0)) < 1e-8)
      }
    }
  }
  @Test("Transverse operator has an independent uniform-x oscillator and wall-work derivative")
  func lattice() throws {
    let closed = ObliqueLattice(n: 2, c: 1, dx: 1, xi: 1e30, qy: 2)
    let y = try closed.evolve([1, 1, 0, 0, 0], time: .pi / 4)
    #expect(abs(y[0]) < 1e-13 && abs(y[1]) < 1e-13 && abs(y[2]) < 1e-13)
    #expect(abs(y[3] - 1) < 1e-13 && abs(y[4] - 1) < 1e-13)
    let wall = ObliqueLattice(n: 2, c: 1, dx: 1, xi: 0.5, qy: 2)
    let initial = [1.0, 0.5, 0.25, 0.125, -0.25]
    let derivative = wall.action(initial)
    #expect(
      abs(zip(initial, derivative).reduce(0) { $0 + 2 * $1.0 * $1.1 } + 4 * initial[1] * initial[1])
        < 1e-14)
    let direct = try wall.evolve(initial, time: 0.7)
    let split = try wall.evolve(wall.evolve(initial, time: 0.3), time: 0.4)
    #expect(zip(direct, split).allSatisfy { abs($0 - $1) < 2e-14 })
    #expect(throws: BenchmarkFailure.self) { try wall.evolve([1, 2], time: 1) }
  }
  @Test("Pressure-based complex fitting recovers reflection without using wall p/u") func fitting()
    throws
  {
    let c = try ObliqueModeCase.standard()[0]
    let r = ObliqueModeResolution(axis: "space", nx: 16, ny: 8, steps: 128)
    let ref = try ObliqueModeReference(c)
    let h = try ObliqueModeOracle.history(c, r)
    let fit = try ObliqueModeResult.fitReflection(ref, r, h)
    #expect((fit.value - ref.reflection).magnitude < 1e-12 && fit.residual < 1e-12)
    let incoming = ObliqueComplex(1, 0.2)
    let chosen = ObliqueComplex(0.2, 0.1)
    let outgoing = incoming * chosen
    let different = BoundaryHistory(
      dx: h.dx, dy: h.dy, dt: h.dt,
      frames: h.frames.map { frame in
        let pressure = frame.p.indices.map { index in
          let x = (Double(index % r.nx) + 0.5) * h.dx - c.lengthX
          let y = (Double(index / r.nx) + 0.5) * h.dy
          let time = Double(frame.step) * h.dt
          let incident =
            (ObliqueComplex.i * ref.kx * ObliqueComplex(x) + ref.rate * ObliqueComplex(time)).exp
          let reflected =
            (-ObliqueComplex.i * ref.kx * ObliqueComplex(x) + ref.rate * ObliqueComplex(time)).exp
          return (incoming * incident + outgoing * reflected).real * cos(ref.ky * y)
        }
        return BoundaryFrame(
          step: frame.step, p: pressure, u: frame.u, v: frame.v,
          dissipation: frame.dissipation)
      })
    let independent = try ObliqueModeResult.fitReflection(ref, r, different)
    #expect((independent.value - chosen).magnitude < 1e-12)
    #expect((independent.value - ref.reflection).magnitude > 0.1)

  }
  @Test("Correct pressure cannot conceal reversed transverse velocity or missing work")
  func negative() throws {
    let c = try ObliqueModeCase.standard()[0]
    let r = ObliqueModeResolution(axis: "time", nx: 8, ny: 4, steps: 128)
    let h = try ObliqueModeOracle.history(c, r)
    let wrong = BoundaryHistory(
      dx: h.dx, dy: h.dy, dt: h.dt,
      frames: h.frames.map {
        BoundaryFrame(
          step: $0.step, p: $0.p, u: $0.u, v: $0.v.map { -$0 }, dissipation: $0.dissipation)
      })
    let result = try ObliqueModeResult.evaluate(
      model: "wrong-y", c: c, r: r, environment: env, runtime: 0, h: wrong)
    #expect(result.errors!.fieldL2[0] == 0 && result.errors!.fieldL2[2] > 1.99)
    #expect(throws: BenchmarkFailure.self) { try ObliqueModeCommand.bounds(result) }
    let absent = BoundaryHistory(
      dx: h.dx, dy: h.dy, dt: h.dt,
      frames: h.frames.map { BoundaryFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v) })
    let missing = try ObliqueModeResult.evaluate(
      model: "missing-work", c: c, r: r, environment: env, runtime: 0, h: absent)
    #expect(missing.errors!.dissipationError > 0.3)
    #expect(throws: BenchmarkFailure.self) { try ObliqueModeCommand.bounds(missing) }
  }
  @Test(
    "Malformed decoded metrics, invalid cases, missing fields and wrong clocks reject explicitly")
  func invalid() throws {
    #expect(throws: BenchmarkFailure.self) { try ObliqueModeCase(id: "bad", impedance: 0) }
    let c = try ObliqueModeCase.standard()[0]
    let r = ObliqueModeResolution(axis: "time", nx: 8, ny: 4, steps: 128)
    let h = try ObliqueModeOracle.history(c, r)
    #expect(throws: BenchmarkFailure.self) {
      try ObliqueModeResult.evaluate(
        model: "clock", c: c, r: r, environment: env, runtime: 0,
        h: BoundaryHistory(dx: h.dx, dy: h.dy, dt: 2 * h.dt, frames: h.frames))
    }
    #expect(throws: BenchmarkFailure.self) {
      try ObliqueModeResult.evaluate(
        model: "missing", c: c, r: r, environment: env, runtime: 0,
        h: BoundaryHistory(dx: h.dx, dy: h.dy, dt: h.dt, frames: Array(h.frames.dropLast())))
    }
    let result = try ObliqueModeResult.evaluate(
      model: "decode", c: c, r: r, environment: env, runtime: 0, h: h)
    var dictionary =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
    var errors = dictionary["errors"] as! [String: Any]
    errors["fieldL2"] = []
    dictionary["errors"] = errors
    let malformed = try JSONDecoder().decode(
      ObliqueModeResult.self, from: JSONSerialization.data(withJSONObject: dictionary))
    #expect(throws: BenchmarkFailure.self) {
      try ObliqueModeCommand.check([malformed, malformed, malformed])
    }
    var decoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
    decoded["version"] = 2
    let invalid = try JSONDecoder().decode(
      ObliqueModeCase.self, from: JSONSerialization.data(withJSONObject: decoded))
    #expect(throws: BenchmarkFailure.self) { try invalid.validate() }
  }
}
