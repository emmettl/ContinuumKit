import BenchmarkSupport
import Foundation
import Testing

@Suite("Mixed-axis and impedance references") struct BoundaryAcousticTests {
  let env = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test",
    operatingSystem: "test")
  @Test("Two independent mixed-axis oscillator golden states") func modes() throws {
    let c = try BoundaryAcousticCase.standard()[0]
    let x = 0.015625
    let y = 0.015625
    let continuum = c.state(x: x, y: y, t: c.duration / 4)
    #expect(abs(continuum.p) < 1e-14)
    #expect(
      abs(continuum.u - 1 / (2 * sqrt(2.0) * 400)) < 1e-14 && abs(continuum.v - continuum.u) < 1e-14
    )
    let h = 0.03125
    let latticeOmega = 2 * 320 / h
    let lattice = c.state(x: x, y: y, t: .pi / (2 * latticeOmega), dx: h, dy: h)
    #expect(abs(lattice.p) < 1e-14 && abs(lattice.u - 1 / (2 * sqrt(2.0) * 400)) < 1e-14)
    #expect(abs(c.state(x: x, y: y, t: c.duration).p - 0.5) < 1e-14)
  }
  @Test("Impedance pressure and energy signs have independent golden values") func impedance()
    throws
  {
    for (xi, r) in [(1.0, 0.0), (3.0, 0.5), (0.5, -1.0 / 3)] {
      let c = try BoundaryAcousticCase(id: "golden", kind: .impedancePulse, impedance: xi)
      #expect(abs(c.reflection - r) < 1e-15)
      let hit = (0.25 - 0.075) / 320
      let wall = c.state(x: 0.25, y: 0, t: hit)
      let returned = c.state(x: 0.15, y: 0, t: c.duration)
      #expect(abs(wall.p - (1 + r)) < 1e-14 && abs(wall.p - 400 * xi * wall.u) < 1e-14)
      #expect(abs(returned.p - r) < 1e-14 && abs(returned.u + r / 400) < 1e-14)
      #expect(abs(BoundaryOracle.dissipated(c, t: c.duration) / c.energy - (1 - r * r)) < 1e-13)
    }
  }
  @Test("A correct pressure field cannot conceal a reversed transverse velocity")
  func wrongComponent() throws {
    let c = try BoundaryAcousticCase.standard()[0]
    let r = BoundaryResolution.standard(c).last!
    let h = BoundaryOracle.history(c, r)
    let broken = BoundaryHistory(
      dx: h.dx, dy: h.dy, dt: h.dt,
      frames: h.frames.map { BoundaryFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v.map { -($0) }) }
    )
    let result = try BoundaryResult.evaluate(
      model: "wrong-y", c: c, r: r, environment: env, runtime: 0, h: broken)
    #expect(result.errors!.pressureL2 < 1e-14 && result.errors!.maxVelocity > 1)
    #expect(throws: BenchmarkFailure.self) { try BoundaryCommand.bounds(result) }
  }
  @Test("Version, geometry, missing fields and invalid impedance fail explicitly") func invalid()
    throws
  {
    #expect(throws: BenchmarkFailure.self) {
      try BoundaryAcousticCase(id: "bad", kind: .impedancePulse, impedance: 0)
    }
    let c = try BoundaryAcousticCase.standard()[0]
    let r = BoundaryResolution.standard(c)[0]
    let h = BoundaryOracle.history(c, r)
    #expect(throws: BenchmarkFailure.self) {
      try BoundaryResult.evaluate(
        model: "missing", c: c, r: r, environment: env, runtime: 0,
        h: BoundaryHistory(dx: h.dx, dy: h.dy, dt: h.dt, frames: Array(h.frames.dropLast())))
    }
    var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
    dict["lengthX"] = 1
    let decoded = try JSONDecoder().decode(
      BoundaryAcousticCase.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(throws: BenchmarkFailure.self) { try decoded.validate() }
  }
  @Test("First-order boundary plus second-order interior error has mixed full-field orders")
  func mixedError() {
    let errors = [0.1, 0.05, 0.025].map { $0 + 32 * $0 * $0 }
    let orders = zip(errors, errors.dropFirst()).map { log($0.0 / $0.1) / log(2) }
    #expect(orders.allSatisfy { $0 > 1.2 && $0 < 2 })
  }

}
