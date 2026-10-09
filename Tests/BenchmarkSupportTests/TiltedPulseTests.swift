import Foundation
import Testing

@testable import BenchmarkSupport

@Suite("Independent tilted plane pulse and causal finite-plan graph") struct TiltedPulseTests {
  let env = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test",
    operatingSystem: "test")
  @Test("Independent reflection and energy goldens") func goldens() {
    let c = TiltedPulseCase()
    #expect(abs(c.reflection - 0.45700594419362979494) < 1e-15)
    #expect(abs(c.energy / 3.337860107421875e-10 - 1) < 1e-14)
    #expect(abs(c.patchEnergy / 9.0122222900390625e-12 - 1) < 1e-15)
    #expect(abs(c.patchWork(time: c.duration) / 7.1299797133278468933e-12 - 1) < 1e-13)
  }
  @Test("Plane incident and reflected fields satisfy oblique impedance") func boundary() {
    let c = TiltedPulseCase()
    for y in [0.238, 0.25, 0.262] {
      let x = c.intercept - y / 2
      let t = (x - c.centre) / c.speed
      for offset in [-0.4, 0.0, 0.4] {
        let state = c.state([x, y, 0], time: t + offset * c.halfWidth / c.speed)
        #expect(
          abs(
            c.density * c.speed * c.impedance * (state[1] * c.normal[0] + state[2] * c.normal[1])
              - state[0]) < 1e-13)
      }
    }
  }
  @Test("Compact pulse squared primitive matches independent Simpson integral") func integral() {
    let c = TiltedPulseCase()
    let n = 1024
    let d = 2 * c.halfWidth / Double(n)
    var sum = 0.0
    for i in 0...n {
      let w = i == 0 || i == n ? 1.0 : i.isMultiple(of: 2) ? 2 : 4
      sum += w * d / 3 * pow(c.pulse(-c.halfWidth + Double(i) * d), 2)
    }
    #expect(abs(sum / c.pulseIntegral - 1) < 1e-14)
    #expect(abs(c.pulseSquaredPrimitive(c.halfWidth) / sum - 1) < 1e-14)
    #expect(c.pulse(c.halfWidth) == 0 && c.pulse(-c.halfWidth) == 0)
  }
  @Test("Corner return bound and fully separated final echo") func causal() {
    let c = TiltedPulseCase()
    #expect(abs(c.cornerArrivalTravel - 0.32) < 1e-15 && c.travel < c.cornerArrivalTravel)
    let grid = try! TiltedPulseGrid(c, TiltedPulseResolution(axis: "space", nx: 64, steps: 16))
    for cell in grid.inside.indices
    where grid.inside[cell] == 1 && c.observation(grid.position(0, cell)) {
      let p = grid.position(0, cell)
      #expect(c.pulse(p[0] - c.centre - c.travel) == 0)
      #expect(c.state(p, time: 0)[2] == 0 && c.state(p, time: 0)[3] == 0)
    }
  }
  @Test("Central patch loss equals independent incident minus returned energy") func patch() {
    let c = TiltedPulseCase()
    #expect(
      abs(c.patchWork(time: c.duration) / c.patchEnergy - (1 - c.reflection * c.reflection)) < 1e-13
    )
    var previous = 0.0
    for i in 0...24 {
      let work = c.patchWork(time: c.duration * Double(i) / 24)
      #expect(work >= previous - 1e-20)
      previous = work
    }
  }
  @Test("Independent shifted-template echo amplitude and arrival fit") func fit() throws {
    let c = TiltedPulseCase()
    let r = TiltedPulseResolution(axis: "space", nx: 64, steps: 16)
    let grid = try TiltedPulseGrid(c, r)
    let p = grid.inside.indices.map { i in
      grid.inside[i] == 1
        ? 0.41 * c.reflectedShape(grid.position(0, i), time: c.duration, shift: -0.002) : 100
    }
    let fit = TiltedPulseOracle.reflectionFit(c, r, grid: grid, p: p)
    #expect(abs(fit.coefficient - 0.41) < 1e-9 && abs(fit.shift + 0.002) < 1e-9)
  }
  @Test("Exponential pressure-squared patch work has an independent scalar golden")
  func exponentialWork() throws {
    let graph = try MaskedLattice(
      dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3, wallRates: [2, 2])
    let ref = try PulseGraphReference(graph: graph, patchRates: [2, 0])
    let t = 0.3
    let actual = try ref.evolve([1, 1, 0], time: t)
    #expect(
      abs(actual.state[0] - exp(-2 * t)) < 1e-14 && actual.state[0] == actual.state[1]
        && actual.state[2] == 0)
    #expect(abs(actual.patchIntegral - (1 - exp(-4 * t)) / 2) < 1e-14)
    let back = try ref.evolve(actual.state, time: -t)
    #expect(
      abs(back.state[0] - 1) < 1e-14 && abs(actual.patchIntegral + back.patchIntegral) < 1e-14)
  }
  @Test("Coupled graph action and integrated work compose without a source stepper")
  func composition() throws {
    let graph = try MaskedLattice(
      dimensions: [3, 2, 1], spacing: [0.2, 0.3, 0.4], inside: [1, 1, 1, 1, 1, 1], speed: 2,
      wallRates: [2, 0, 3, 0, 0, 4])
    let ref = try PulseGraphReference(graph: graph, patchRates: [1, 0, 2, 0, 0, 4])
    let seed = (0..<graph.stateCount).map { sin(Double($0) * 0.3) }
    let a = try ref.evolve(seed, time: 0.11)
    let b = try ref.evolve(seed, time: 0.04)
    let d = try ref.evolve(b.state, time: 0.07)
    let other = try graph.evolve(seed, time: 0.11)
    #expect(zip(a.state, other).allSatisfy { abs($0 - $1) < 1e-13 })
    #expect(zip(a.state, d.state).allSatisfy { abs($0 - $1) < 1e-13 })
    #expect(abs(a.patchIntegral - b.patchIntegral - d.patchIntegral) < 1e-13 && a.patchIntegral > 0)
  }
  @Test("The two-dimensional reduction reproduces a z-invariant full graph") func reduction() throws
  {
    let rates = [2.0, 0, 1, 3]
    let plane = try MaskedLattice(
      dimensions: [2, 2, 1], spacing: [0.2, 0.3, 0.4], inside: [1, 1, 1, 1], speed: 2,
      wallRates: rates)
    let full = try MaskedLattice(
      dimensions: [2, 2, 2], spacing: [0.2, 0.3, 0.4], inside: [UInt8](repeating: 1, count: 8),
      speed: 2, wallRates: rates + rates)
    let p = [1.0, 0.3, -0.2, 0.6]
    let a = try plane.evolve(p + [Double](repeating: 0, count: plane.edges.count), time: 0.07)
    let b = try full.evolve(p + p + [Double](repeating: 0, count: full.edges.count), time: 0.07)
    for i in 0..<8 { #expect(abs(b[i] - a[i % 4]) < 1e-13) }
    for (i, e) in full.edges.enumerated() {
      if e.axis == 2 {
        #expect(abs(b[8 + i]) < 1e-13)
      } else {
        let reduced = try #require(
          plane.edges.firstIndex { $0.cell == e.cell % 4 && $0.axis == e.axis })
        #expect(abs(b[8 + i] - a[4 + reduced]) < 1e-13)
      }
    }
  }
  func history() throws -> (TiltedPulseCase, TiltedPulseResolution, TiltedPulseHistory) {
    let c = TiltedPulseCase()
    let r = TiltedPulseResolution(axis: "space", nx: 32, steps: 16)
    let grid = try TiltedPulseGrid(c, r)
    let dt = c.duration / 16
    let faces = grid.faces(dt: dt)
    let h = try TiltedPulseOracle.history(c, r, faces: faces, dt: dt)
    return (
      c, r,
      TiltedPulseHistory(
        fields: h.fields, inside: grid.inside, faces: faces, layoutFaces: faces, layoutDt: dt,
        materialImpedance: 3, wallCells: grid.wallCells, wallPressures: nil, dissipation: nil,
        patchDissipation: h.patchWork)
    )
  }
  @Test("Native z motion and inactive pressure are separate global failures") func padding() throws
  {
    let (c, r, h) = try history()
    let fields = RigidModeHistory(
      spacing: h.fields.spacing, dt: h.fields.dt,
      frames: h.fields.frames.map { f in
        var p = f.p
        p[p.count - 1] += 1
        var w = f.w
        w[0] = 0.001
        return RigidModeFrame(step: f.step, p: p, u: f.u, v: f.v, w: w)
      })
    let bad = TiltedPulseHistory(
      fields: fields, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
      layoutDt: h.layoutDt, materialImpedance: 3, wallCells: h.wallCells, wallPressures: nil,
      dissipation: nil, patchDissipation: h.patchDissipation)
    let result = try TiltedPulseResult.evaluate(
      model: "bad", c: c, r: r, environment: env, h: bad, runtime: 0, reference: true)
    #expect(
      result.errors!.fieldL2 == [0, 0, 0] && result.errors!.inactivePreservation == 1
        && result.errors!.zeroZ == 0.4)
    #expect(throws: BenchmarkFailure.self) { try TiltedPulseCommand.numericalBounds(result) }
  }
  @Test("Missing source trace, wrong face clock and missing native fields reject") func malformed()
    throws
  {
    let (c, r, h) = try history()
    #expect(throws: BenchmarkFailure.self) {
      try TiltedPulseResult.evaluate(
        model: "no-trace", c: c, r: r, environment: env, h: h, runtime: 0)
    }
    let bad = TiltedPulseHistory(
      fields: h.fields, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
      layoutDt: 2 * h.layoutDt, materialImpedance: 3, wallCells: h.wallCells, wallPressures: nil,
      dissipation: nil, patchDissipation: h.patchDissipation)
    #expect(throws: BenchmarkFailure.self) {
      try TiltedPulseResult.evaluate(
        model: "clock", c: c, r: r, environment: env, h: bad, runtime: 0, reference: true)
    }
    let short = RigidModeHistory(
      spacing: h.fields.spacing, dt: h.fields.dt,
      frames: h.fields.frames.map {
        RigidModeFrame(step: $0.step, p: [], u: $0.u, v: $0.v, w: $0.w)
      })
    let empty = TiltedPulseHistory(
      fields: short, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
      layoutDt: h.layoutDt, materialImpedance: 3, wallCells: h.wallCells, wallPressures: nil,
      dissipation: nil, patchDissipation: h.patchDissipation)
    #expect(throws: BenchmarkFailure.self) {
      try TiltedPulseResult.evaluate(
        model: "short", c: c, r: r, environment: env, h: empty, runtime: 0, reference: true)
    }
  }
  @Test("Malformed decoded geometry and work rates reject") func invalid() throws {
    var dict =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(TiltedPulseCase()))
      as! [String: Any]
    dict["travel"] = 0.4
    let c = try JSONDecoder().decode(
      TiltedPulseCase.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(throws: BenchmarkFailure.self) { try c.validate() }
    let graph = try MaskedLattice(
      dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3, wallRates: [2, 2])
    #expect(throws: BenchmarkFailure.self) {
      try PulseGraphReference(graph: graph, patchRates: [3, 0])
    }
    #expect(throws: BenchmarkFailure.self) { try TiltedPulseCommand.check([]) }
  }
}
