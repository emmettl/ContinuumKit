import Foundation
import Testing

@testable import BenchmarkSupport

@Suite("Independent coupled Robin cylinder and dissipative graph")
struct AbsorbingCylinderTests {
  let env = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test",
    operatingSystem: "test")
  @Test("60-digit independent complex root, rate, complete field and energy goldens")
  func goldens() throws {
    let ref = try AbsorbingCylinderReference(AbsorbingCylinderCase())
    #expect(abs(ref.root.real - 3.821751618059804487) < 1e-13)
    #expect(abs(ref.root.imag + 0.4131219254346297565) < 1e-13)
    #expect(abs(ref.rate.real + 1201.72637321809038) < 1e-9)
    #expect(abs(ref.rate.imag + 15307.0857217838908) < 1e-9)
    let state = ref.state([0.1484375, 0.1484375, 0.03125], time: ref.duration * 0.137)
    #expect(abs(state[0] - 0.2955119052067613029) < 1e-13)
    #expect(abs(state[1] - 0.0004348309899006301474) < 1e-15 && state[1] == state[2])
    #expect(abs(state[3] - 0.0003152887793136530258) < 1e-15)
    #expect(abs(ref.energy(time: 0) / 1.2294217641745638498e-9 - 1) < 1e-13)
    #expect(abs(ref.energy(time: ref.duration / 2) / 7.5071032970680972263e-10 - 1) < 1e-13)
    #expect(abs(ref.dissipated(time: ref.duration / 2) / 4.7871143446775412713e-10 - 1) < 1e-13)
  }
  @Test("Compatible physical side velocity and rigid caps")
  func boundary() throws {
    let c = AbsorbingCylinderCase()
    let ref = try AbsorbingCylinderReference(c)
    let g = c.geometry
    for t in [0.0, ref.duration * 0.23, ref.duration] {
      for angle in [0.0, 0.37, 1.7] {
        let p = ref.state(
          [g.centre[0] + g.radius * cos(angle), g.centre[1] + g.radius * sin(angle), 0.03], time: t)
        #expect(
          abs((p[1] * cos(angle) + p[2] * sin(angle)) * g.density * g.speed * c.impedance - p[0])
            < 1e-13)
      }
      #expect(abs(ref.state([0.13, 0.14, 0], time: t)[3]) < 1e-15)
      #expect(abs(ref.state([0.13, 0.14, g.lengths[2]], time: t)[3]) < 1e-15)
    }
  }
  @Test("Analytic radial energy and physical wall integral close for a whole mode cycle")
  func continuumWork() throws {
    let ref = try AbsorbingCylinderReference(AbsorbingCylinderCase())
    let e0 = ref.energy(time: 0)
    var previous = 0.0
    for i in 0...32 {
      let t = Double(i) / 32 * ref.duration
      let w = ref.dissipated(time: t)
      #expect(w >= previous - 1e-20)
      #expect(abs(ref.energy(time: t) + w - e0) / e0 < 1e-13)
      previous = w
    }
    // Independent Simpson time quadrature of boundary p²/(rho*c*xi).
    let n = 512
    let dt = ref.duration / Double(n)
    let g = ref.specification.geometry
    var work = 0.0
    for i in 0...n {
      let weight = i == 0 || i == n ? 1.0 : i.isMultiple(of: 2) ? 2 : 4
      let p = ref.state([g.centre[0] + g.radius, g.centre[1], 0], time: Double(i) * dt)[0]
      work +=
        weight * dt / 3 * Double.pi * g.radius * g.lengths[2] * p * p / (g.density * g.speed * 3)
    }
    #expect(abs(work / ref.dissipated(time: ref.duration) - 1) < 1e-9)
  }
  @Test("A two-cell uniformly damped graph has an independent oscillator")
  func dampedOscillator() throws {
    let graph = try MaskedLattice(
      dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3, wallRates: [2, 2])
    let t = 0.17
    let w = sqrt(17.0)
    let p = exp(-t) * (cos(w * t) - sin(w * t) / w)
    let u = 6 * exp(-t) * sin(w * t) / w
    let actual = try graph.evolve([1, -1, 0], time: t)
    #expect(abs(actual[0] - p) < 1e-14 && abs(actual[1] + p) < 1e-14 && abs(actual[2] - u) < 1e-14)
    let uniform = try graph.evolve([1, 1, 0], time: t)
    #expect(abs(uniform[0] - exp(-2 * t)) < 1e-14 && uniform[0] == uniform[1] && uniform[2] == 0)
  }
  @Test("Disconnected damped cells cannot transmit and retain distinct analytic rates")
  func disconnected() throws {
    let graph = try MaskedLattice(
      dimensions: [3, 1, 1], spacing: [1, 1, 1], inside: [1, 0, 1], speed: 3, wallRates: [2, 0, 4])
    let p = try graph.evolve([1, 2], time: 0.3)
    #expect(abs(p[0] - exp(-0.6)) < 1e-14 && abs(p[1] - 2 * exp(-1.2)) < 1e-14)
  }
  @Test("Variable damped graph composes, is passive and supports the half-step clock")
  func composition() throws {
    let graph = try MaskedLattice(
      dimensions: [3, 2, 2], spacing: [0.2, 0.3, 0.4], inside: [UInt8](repeating: 1, count: 12),
      speed: 2, wallRates: (0..<12).map { Double($0) * 0.3 })
    let initial = (0..<graph.stateCount).map { sin(Double($0) * 0.7) }
    let a = try graph.evolve(initial, time: 0.11)
    let b = try graph.evolve(graph.evolve(initial, time: 0.04), time: 0.07)
    #expect(zip(a, b).allSatisfy { abs($0 - $1) < 1e-13 })
    #expect(a.reduce(0) { $0 + $1 * $1 } < initial.reduce(0) { $0 + $1 * $1 })
    let backward = try graph.evolve(a, time: -0.11)
    #expect(zip(initial, backward).allSatisfy { abs($0 - $1) < 1e-13 })
  }
  @Test("Negative, non-finite and inactive wall rates reject")
  func invalidGraph() throws {
    for rates in [[-1.0, 0], [Double.infinity, 0], [Double.nan, 0], [1]] {
      #expect(throws: BenchmarkFailure.self) {
        try MaskedLattice(
          dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3, wallRates: rates)
      }
    }
    #expect(throws: BenchmarkFailure.self) {
      try MaskedLattice(
        dimensions: [3, 1, 1], spacing: [1, 1, 1], inside: [1, 0, 1], speed: 3,
        wallRates: [0, 1, 0])
    }
  }
  func source() throws -> (AbsorbingCylinderCase, CylinderResolution, AbsorbingCylinderHistory) {
    let c = AbsorbingCylinderCase()
    let r = try AbsorbingCylinderOracle.resolutions(c)[0]
    let ref = try AbsorbingCylinderReference(c)
    let dt = ref.duration / Double(r.steps)
    let grid = try CylinderGrid(c.geometry, r)
    let faces = try AbsorbingCylinderOracle.faces(c, r, dt: dt)
    let h = try AbsorbingCylinderOracle.history(c, r, faces: faces, dt: dt)
    return (
      c, r,
      AbsorbingCylinderHistory(
        fields: h.fields, inside: grid.inside, faces: faces, layoutFaces: faces, layoutDt: dt,
        materialImpedance: c.impedance, wallCells: AbsorbingCylinderOracle.wallCells(grid),
        wallPressures: nil, dissipation: h.work)
    )
  }
  @Test("Native z velocity and inactive padding cannot hide in active norms")
  func fields() throws {
    let (c, r, h) = try source()
    let wrong = RigidModeHistory(
      spacing: h.fields.spacing, dt: h.fields.dt,
      frames: h.fields.frames.map { f in
        var p = f.p
        p[0] -= 1
        return RigidModeFrame(step: f.step, p: p, u: f.u, v: f.v, w: f.w.map { -$0 })
      })
    let broken = AbsorbingCylinderHistory(
      fields: wrong, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
      layoutDt: h.layoutDt, materialImpedance: 3, wallCells: h.wallCells, wallPressures: nil,
      dissipation: h.dissipation)
    let result = try AbsorbingCylinderResult.evaluate(
      model: "wrong-z", c: c, r: r, environment: env, h: broken, runtime: 0, reference: true)
    #expect(
      result.errors!.fieldL2[0] == 0 && result.errors!.fieldL2[3] > 1.99
        && result.errors!.inactivePreservation == 1)
    #expect(throws: BenchmarkFailure.self) { try AbsorbingCylinderCommand.bounds(result) }
  }
  @Test("Wrong native dimensions, material, masks, face clocks and missing source trace reject")
  func malformed() throws {
    let (c, r, h) = try source()
    var mask = h.inside
    mask[0] = 1
    let short = RigidModeHistory(
      spacing: h.fields.spacing, dt: h.fields.dt,
      frames: h.fields.frames.map {
        RigidModeFrame(step: $0.step, p: [], u: $0.u, v: $0.v, w: $0.w)
      })
    for bad in [
      AbsorbingCylinderHistory(
        fields: short, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
        layoutDt: h.layoutDt, materialImpedance: 3, wallCells: h.wallCells, wallPressures: nil,
        dissipation: h.dissipation),
      AbsorbingCylinderHistory(
        fields: h.fields, inside: mask, faces: h.faces, layoutFaces: h.layoutFaces,
        layoutDt: h.layoutDt, materialImpedance: 3, wallCells: h.wallCells, wallPressures: nil,
        dissipation: h.dissipation),
      AbsorbingCylinderHistory(
        fields: h.fields, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
        layoutDt: 2 * h.layoutDt, materialImpedance: 3, wallCells: h.wallCells, wallPressures: nil,
        dissipation: h.dissipation),
      AbsorbingCylinderHistory(
        fields: h.fields, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
        layoutDt: h.layoutDt, materialImpedance: 6, wallCells: h.wallCells, wallPressures: nil,
        dissipation: h.dissipation),
    ] {
      #expect(throws: BenchmarkFailure.self) {
        try AbsorbingCylinderResult.evaluate(
          model: "bad", c: c, r: r, environment: env, h: bad, runtime: 0, reference: true)
      }
    }
    #expect(throws: BenchmarkFailure.self) {
      try AbsorbingCylinderResult.evaluate(
        model: "missing-ledger", c: c, r: r, environment: env, h: h, runtime: 0)
    }
  }
  @Test("Malformed decoded cases and empty series reject")
  func invalidCase() throws {
    var dict =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(AbsorbingCylinderCase()))
      as! [String: Any]
    dict["impedance"] = -3
    let bad = try JSONDecoder().decode(
      AbsorbingCylinderCase.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(throws: BenchmarkFailure.self) { try bad.validate() }
    #expect(throws: BenchmarkFailure.self) { try AbsorbingCylinderCommand.check([]) }
  }
}
