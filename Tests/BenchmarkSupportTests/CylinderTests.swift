import BenchmarkSupport
import Darwin
import Foundation
import Testing

@Suite("Independent cylinder and masked graph reference") struct CylinderTests {
  let env = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test",
    operatingSystem: "test")
  @Test("Independent 60-digit Bessel and field goldens") func goldens() throws {
    let c = CylinderCase()
    let xyz = [0.125 + 0.09375 / 4, 0.125 + 0.09375 / 4, 0.03125]
    #expect(abs(j1(c.radialRoot)) < 1e-15)
    #expect(abs(c.state(xyz, time: 0)[0] - 0.4180472549917344137) < 1e-14)
    let q = c.state(xyz, time: c.duration / 4)
    #expect(abs(q[0]) < 1e-14)
    #expect(abs(q[1] - 0.0005679663702543087985) < 1e-15)
    #expect(q[1] == q[2])
    #expect(abs(q[3] - 0.0005474439904526934672) < 1e-15)
    #expect(abs(c.energy / 1.0935127186193479175e-9 - 1) < 1e-14)
    #expect(abs(c.state([0.125 + c.radius, 0.125, 0.03125], time: c.duration / 4)[1]) < 1e-15)
  }
  @Test("Independent Simpson integral verifies cylindrical energy") func energy() throws {
    let c = CylinderCase()
    let n = 512
    let dr = c.radius / Double(n)
    var integral = 0.0
    for i in 0...n {
      let r = Double(i) * dr
      let weight = i == 0 || i == n ? 1.0 : i.isMultiple(of: 2) ? 2 : 4
      integral += weight * r * pow(j0(c.radialWave * r), 2) * dr / 3
    }
    let energy = 2 * Double.pi * integral * c.lengths[2] / 2 / (2 * c.density * c.speed * c.speed)
    #expect(abs(energy / c.energy - 1) < 1e-9)
  }
  @Test("Closed two-cell graph has a golden oscillator") func twoCell() throws {
    let lattice = try MaskedLattice(
      dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3)
    let q = try lattice.evolve([1, -1, 0], time: Double.pi / (2 * 3 * sqrt(2)))
    #expect(abs(q[0]) < 1e-14 && abs(q[1]) < 1e-14)
    #expect(abs(q[2] - sqrt(2)) < 1e-14)
  }
  @Test("Disconnected graph cannot transmit across an inactive cell") func disconnected() throws {
    let lattice = try MaskedLattice(
      dimensions: [3, 1, 1], spacing: [1, 1, 1], inside: [1, 0, 1], speed: 3)
    #expect(lattice.edges.isEmpty)
    #expect(try lattice.evolve([1, 0], time: 1) == [1, 0])
  }
  @Test("Graph conserves continuous energy and composes independently of sample time")
  func composition() throws {
    let lattice = try MaskedLattice(
      dimensions: [3, 2, 2], spacing: [0.2, 0.3, 0.4], inside: [UInt8](repeating: 1, count: 12),
      speed: 2)
    let initial = (0..<lattice.stateCount).map { sin(Double($0) * 0.7) }
    let a = try lattice.evolve(initial, time: 0.11)
    let b = try lattice.evolve(lattice.evolve(initial, time: 0.04), time: 0.07)
    #expect(zip(a, b).allSatisfy { abs($0 - $1) < 1e-13 })
    #expect(abs(a.reduce(0) { $0 + $1 * $1 } / initial.reduce(0) { $0 + $1 * $1 } - 1) < 1e-13)
    let backward = try lattice.evolve(a, time: -0.11)
    #expect(zip(backward, initial).allSatisfy { abs($0 - $1) < 1e-13 })
  }
  @Test("Graph matches an independently known rectangular masked eigenmode") func boxEigenmode()
    throws
  {
    let c = try MaskedModeCase.standard()[0]
    let r = MaskedModeResolution(axis: "time", nx: 16, ny: 8, nz: 8, steps: 64)
    let grid = try MaskedGrid(c, r)
    let lattice = try MaskedLattice(
      dimensions: r.dimensions, spacing: grid.spacing, inside: grid.inside, speed: c.speed)
    let p = try MaskedModeOracle.initial(c, r, spacing: grid.spacing, dt: c.duration / 64).p
    let initial = lattice.cells.map { p[$0] } + [Double](repeating: 0, count: lattice.edges.count)
    let t = c.duration / 4
    let full = try lattice.evolve(initial, time: t)
    let half = try lattice.evolve(full, time: -t / 2)
    let oracle = try MaskedModeOracle.history(c, r, dt: t, captures: [1]).frames[0]
    for (i, cell) in lattice.cells.enumerated() { #expect(abs(full[i] - oracle.p[cell]) < 1e-13) }
    for (i, edge) in lattice.edges.enumerated() {
      var xyz = grid.coordinates(edge.cell, shape: r.dimensions)
      xyz[edge.axis] += 1
      let shape = grid.fieldDimensions(edge.axis + 1)
      let index = xyz[0] + shape[0] * (xyz[1] + shape[1] * xyz[2])
      #expect(
        abs(
          half[lattice.cells.count + i] / (c.density * c.speed)
            - oracle.fields[edge.axis + 1][index]) < 1e-14)
    }
  }
  @Test("Circle occupancy, native masks and reversed z velocity are audited")
  func geometryAndFields() throws {
    let c = CylinderCase()
    let r = CylinderResolution(axis: "space", nx: 16, ny: 16, nz: 8, steps: 256)
    let grid = try CylinderGrid(c, r)
    #expect(grid.labels.filter { $0 >= 0 }.count == 112 * 8)
    #expect(grid.label([0, 0, 0]) == -1 && grid.label([8, 8, 4]) == 0)
    let h = try CylinderOracle.history(c, r)
    let broken = RigidModeHistory(
      spacing: h.spacing, dt: h.dt,
      frames: h.frames.map {
        RigidModeFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v, w: $0.w.map { -$0 })
      })
    let result = try CylinderResult.evaluate(
      model: "wrong-z", c: c, r: r, environment: env, runtime: 0,
      h: CylinderHistory(fields: broken, inside: grid.inside, faces: grid.faces))
    #expect(result.errors!.fieldL2[0] == 0 && result.errors!.fieldL2[3] > 1.99)
    #expect(throws: BenchmarkFailure.self) { try CylinderCommand.bounds(result) }
    var inside = grid.inside
    inside[0] = 1
    #expect(throws: BenchmarkFailure.self) {
      try CylinderResult.evaluate(
        model: "wrong-mask", c: c, r: r, environment: env, runtime: 0,
        h: CylinderHistory(fields: h, inside: inside, faces: grid.faces))
    }
  }
  @Test("Invalid graph states, decoded cylinders and incomplete reports fail") func invalid() throws
  {
    #expect(throws: BenchmarkFailure.self) {
      try MaskedLattice(dimensions: [2, 1, 1], spacing: [0, 1, 1], inside: [1, 1], speed: 3)
    }
    let graph = try MaskedLattice(
      dimensions: [2, 1, 1], spacing: [1, 1, 1], inside: [1, 1], speed: 3)
    #expect(throws: BenchmarkFailure.self) { try graph.evolve([1, 0], time: 1) }
    #expect(throws: BenchmarkFailure.self) { try graph.evolve([1, 0, 0], time: .infinity) }
    var dict =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(CylinderCase())) as! [String: Any]
    dict["radius"] = -1
    let bad = try JSONDecoder().decode(
      CylinderCase.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(throws: BenchmarkFailure.self) { try bad.validate() }
    #expect(throws: BenchmarkFailure.self) { try CylinderCommand.check([]) }
  }
  @Test("Padding corruption cannot dilute active field errors or energy") func padding() throws {
    let c = CylinderCase()
    let r = CylinderResolution(axis: "space", nx: 16, ny: 16, nz: 8, steps: 256)
    let grid = try CylinderGrid(c, r)
    let h = try CylinderOracle.history(c, r)
    let corrupted = RigidModeHistory(
      spacing: h.spacing, dt: h.dt,
      frames: h.frames.map {
        var p = $0.p
        p[0] -= 1
        return RigidModeFrame(step: $0.step, p: p, u: $0.u, v: $0.v, w: $0.w)
      })
    let result = try CylinderResult.evaluate(
      model: "padding", c: c, r: r, environment: env, runtime: 0,
      h: CylinderHistory(fields: corrupted, inside: grid.inside, faces: grid.faces))
    #expect(result.errors!.fieldL2 == [0, 0, 0, 0])
    #expect(result.errors!.inactivePreservationError == 1)
    #expect(throws: BenchmarkFailure.self) { try CylinderCommand.bounds(result) }
  }
  @Test("Missing native fields, wrong clock and decoded malformed metrics reject") func malformed()
    throws
  {
    let c = CylinderCase()
    let r = CylinderResolution(axis: "space", nx: 16, ny: 16, nz: 8, steps: 256)
    let grid = try CylinderGrid(c, r)
    let h = try CylinderOracle.history(c, r)
    for fields in [
      RigidModeHistory(spacing: h.spacing, dt: 2 * h.dt, frames: h.frames),
      RigidModeHistory(
        spacing: h.spacing, dt: h.dt,
        frames: h.frames.map { RigidModeFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v, w: []) }),
    ] {
      #expect(throws: BenchmarkFailure.self) {
        try CylinderResult.evaluate(
          model: "invalid", c: c, r: r, environment: env, runtime: 0,
          h: CylinderHistory(fields: fields, inside: grid.inside, faces: grid.faces))
      }
    }
    let result = try CylinderResult.evaluate(
      model: "decoded", c: c, r: r, environment: env, runtime: 0,
      h: CylinderHistory(fields: h, inside: grid.inside, faces: grid.faces))
    var dict =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
    var errors = dict["errors"] as! [String: Any]
    errors["fieldL2"] = []
    dict["errors"] = errors
    let broken = try JSONDecoder().decode(
      CylinderResult.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(throws: BenchmarkFailure.self) { try CylinderCommand.check([broken, broken, broken]) }
    #expect(throws: BenchmarkFailure.self) { try CylinderCommand.bounds(broken) }
  }

}
