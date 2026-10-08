import BenchmarkSupport
import Foundation
import Testing

@Suite("Independent three-dimensional rigid modes") struct RigidModes3DTests {
  let env = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test",
    operatingSystem: "test")
  @Test("Body-diagonal quarter-cycle has three equal nonzero velocities") func golden() throws {
    let c = try RigidModeCase.standard()[0]
    let x = [0.03125, 0.03125, 0.03125]
    let initial = c.state(x, time: 0)
    #expect(abs(initial[0] - 1 / (2 * sqrt(2.0))) < 1e-14)
    let quarter = c.state(x, time: c.duration / 4)
    #expect(abs(quarter[0]) < 1e-14)
    for v in quarter.dropFirst() { #expect(abs(v - 1 / (sqrt(24.0) * 400)) < 1e-14) }
  }
  @Test("Discrete three-axis frequency has an independent golden oscillator") func lattice() throws
  {
    let c = try RigidModeCase.standard()[0]
    let omega = 320 * 16 * sqrt(6.0)
    let state = c.state(
      [0.03125, 0.03125, 0.03125], time: .pi / (2 * omega), spacing: [0.0625, 0.0625, 0.0625])
    #expect(abs(state[0]) < 1e-14)
    for v in state.dropFirst() { #expect(abs(v - 1 / (sqrt(24.0) * 400)) < 1e-14) }
  }
  @Test("Independent Simpson volume integral agrees with total continuum energy") func energy()
    throws
  {
    let c = try RigidModeCase.standard()[0]
    var integral = 1.0
    for axis in 0..<3 {
      let count = 32
      let dx = c.lengths[axis] / Double(count)
      var sum = 0.0
      for i in 0...count {
        let weight = i == 0 || i == count ? 1.0 : (i.isMultiple(of: 2) ? 2 : 4)
        sum +=
          weight * pow(cos(Double(c.modes[axis]) * .pi * Double(i) / Double(count)), 2) * dx / 3
      }
      integral *= sum
    }
    #expect(abs(integral / (2 * c.density * c.speed * c.speed) / c.energy - 1) < 1e-14)
  }
  @Test("Native z-face coordinates and Taylor half kick retain all three axes") func staggering()
    throws
  {
    let c = try RigidModeCase.standard()[0]
    let r = RigidModeResolution(axis: "time", nx: 8, ny: 4, nz: 4, steps: 64)
    let spacing = [0.03125, 0.03125, 0.03125]
    let dt = c.duration / 64
    let f = RigidModeOracle.initial(c, r, spacing: spacing, dt: dt)
    let index = 1 + 8 * (1 + 4 * 2)
    let plus = 1 + 8 * (1 + 4 * 2)
    #expect(f.w.count == 8 * 4 * 5)
    #expect(
      abs(f.w[index] - dt * (f.p[plus] - f.p[plus - 32]) / (2 * c.density * spacing[2])) < 1e-15)
    let xyz = RigidModeOracle.position(index, dimensions: [8, 4, 5], field: 3, spacing: spacing)
    #expect(xyz == [0.046875, 0.046875, 0.0625])
    #expect(RigidModeResolution.standard(try RigidModeCase.standard()[1])[0].nz == 4)
  }
  @Test("Pressure agreement cannot conceal a reversed z velocity") func reversedZ() throws {
    let c = try RigidModeCase.standard()[0]
    let r = RigidModeResolution(axis: "time", nx: 8, ny: 4, nz: 4, steps: 64)
    let h = RigidModeOracle.history(c, r)
    let broken = RigidModeHistory(
      spacing: h.spacing, dt: h.dt,
      frames: h.frames.map {
        RigidModeFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v, w: $0.w.map { -$0 })
      })
    let result = try RigidModeResult.evaluate(
      model: "wrong-z", c: c, r: r, environment: env, runtime: 0, h: broken)
    #expect(result.errors!.fieldL2[0] == 0 && result.errors!.fieldL2[3] > 1.99)
    #expect(throws: BenchmarkFailure.self) { try RigidModeCommand.bounds(result) }
  }
  @Test("Missing z fields, wrong clocks and invalid decoded cases fail") func invalid() throws {
    let c = try RigidModeCase.standard()[0]
    let r = RigidModeResolution(axis: "space", nx: 8, ny: 4, nz: 4, steps: 64)
    let h = RigidModeOracle.history(c, r)
    let broken = RigidModeHistory(
      spacing: h.spacing, dt: h.dt,
      frames: h.frames.map {
        RigidModeFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v, w: [])
      })
    #expect(throws: BenchmarkFailure.self) {
      try RigidModeResult.evaluate(
        model: "missing", c: c, r: r, environment: env, runtime: 0, h: broken)
    }
    #expect(throws: BenchmarkFailure.self) {
      try RigidModeResult.evaluate(
        model: "clock", c: c, r: r, environment: env, runtime: 0,
        h: RigidModeHistory(spacing: h.spacing, dt: 2 * h.dt, frames: h.frames))
    }
    var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
    dict["modes"] = [1, 1]
    let invalid = try JSONDecoder().decode(
      RigidModeCase.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(throws: BenchmarkFailure.self) { try invalid.validate() }
  }
  @Test("Unsupported and incomplete histories cannot become refinement passes") func unsupported()
    throws
  {
    let c = try RigidModeCase.standard()[0]
    let r = RigidModeResolution(axis: "time", nx: 8, ny: 4, nz: 4, steps: 64)
    let result = try RigidModeResult.evaluate(
      model: "2D", c: c, r: r, environment: env, runtime: 0,
      h: RigidModeOracle.history(c, r), status: "unsupported")
    #expect(throws: BenchmarkFailure.self) { try RigidModeCommand.check([result, result, result]) }
    #expect(throws: BenchmarkFailure.self) { try RigidModeCommand.check([]) }
  }
  @Test("Malformed decoded refinement reports fail explicitly without indexing")
  func malformedReports() throws {
    let c = try RigidModeCase.standard()[0]
    let r = RigidModeResolution(axis: "time", nx: 8, ny: 4, nz: 4, steps: 64)
    let result = try RigidModeResult.evaluate(
      model: "decoded", c: c, r: r, environment: env,
      runtime: 0, h: RigidModeOracle.history(c, r))
    let original =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
    var truncated = original
    var errors = truncated["errors"] as! [String: Any]
    errors["fieldL2"] = []
    truncated["errors"] = errors
    let missing = try JSONDecoder().decode(
      RigidModeResult.self, from: JSONSerialization.data(withJSONObject: truncated))
    #expect(throws: BenchmarkFailure.self) {
      try RigidModeCommand.check([missing, missing, missing])
    }
    var invalid = original
    var specification = invalid["specification"] as! [String: Any]
    specification["modes"] = []
    invalid["specification"] = specification
    let badCase = try JSONDecoder().decode(
      RigidModeResult.self, from: JSONSerialization.data(withJSONObject: invalid))
    #expect(throws: BenchmarkFailure.self) {
      try RigidModeCommand.check([badCase, badCase, badCase])
    }
    errors = original["errors"] as! [String: Any]
    errors["energyBudget"] = -1
    invalid = original
    invalid["errors"] = errors
    let negativeBudget = try JSONDecoder().decode(
      RigidModeResult.self, from: JSONSerialization.data(withJSONObject: invalid))
    #expect(throws: BenchmarkFailure.self) { try RigidModeCommand.bounds(negativeBudget) }
  }

}
