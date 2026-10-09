import Foundation

/// Independent J0/J1 power-series reference restricted to this bounded modal benchmark.
enum CylinderBessel {
  static func j(_ order: Int, _ z: ObliqueComplex) -> ObliqueComplex {
    precondition((0...1).contains(order) && z.magnitude <= 12)
    var term = order == 0 ? ObliqueComplex(1) : z / ObliqueComplex(2)
    var sum = term
    let factor = -(z * z) / ObliqueComplex(4)
    for k in 1...80 {
      term = term * factor / ObliqueComplex(Double(k * (k + order)))
      sum = sum + term
      if term.magnitude < 1e-17 * max(1, sum.magnitude) { break }
    }
    return sum
  }
}
public struct AbsorbingCylinderCase: Codable, Equatable, Sendable {
  public let version: Int, id: String, impedance: Double
  public let geometry: CylinderCase
  public init() {
    version = 1
    id = "coupled-absorbing-cylinder-xi3"
    impedance = 3
    geometry = CylinderCase()
  }
  public func validate() throws {
    guard self == Self() else { throw BenchmarkFailure.invalidCase }
  }
  public static func standard() -> [Self] { [Self()] }
}
/// p = Re[J0(q r) cos(kz z) exp(s t)], s = -i c sqrt(q²+kz²).
/// The Robin root satisfies z J1(z) + i sqrt(z²+(kz R)²) J0(z)/xi = 0.
public struct AbsorbingCylinderReference: Sendable {
  public let specification: AbsorbingCylinderCase
  public let root, radialWave, rate: ObliqueComplex
  public let axialWave, duration: Double
  public init(_ c: AbsorbingCylinderCase) throws {
    try c.validate()
    specification = c
    axialWave = c.geometry.axialWave
    let b = axialWave * c.geometry.radius
    var z = ObliqueComplex(3.83, -0.4)
    for _ in 0..<40 {
      let j0 = CylinderBessel.j(0, z)
      let j1 = CylinderBessel.j(1, z)
      let q = (z * z + ObliqueComplex(b * b)).sqrt
      let f = z * j1 + ObliqueComplex.i * q * j0 / ObliqueComplex(c.impedance)
      let df = z * j0 + ObliqueComplex.i * (z * j0 / q - q * j1) / ObliqueComplex(c.impedance)
      let delta = f / df
      z = z - delta
      guard z.real.isFinite, z.imag.isFinite, z.magnitude < 12 else {
        throw BenchmarkFailure.invalidSamples
      }
      if delta.magnitude < 2e-14 { break }
    }
    let q = (z * z + ObliqueComplex(b * b)).sqrt
    let residual =
      z * CylinderBessel.j(1, z) + ObliqueComplex.i * q * CylinderBessel.j(0, z)
      / ObliqueComplex(c.impedance)
    guard residual.magnitude < 1e-11, z.real > 0, z.imag < 0 else {
      throw BenchmarkFailure.invalidSamples
    }
    root = z
    radialWave = z / ObliqueComplex(c.geometry.radius)
    rate = -ObliqueComplex.i * q * ObliqueComplex(c.geometry.speed / c.geometry.radius)
    guard rate.real < 0, rate.imag < 0 else { throw BenchmarkFailure.invalidSamples }
    duration = 2 * Double.pi / abs(rate.imag)
  }
  public func amplitudes(_ xyz: [Double]) -> [ObliqueComplex] {
    let g = specification.geometry
    let x = xyz[0] - g.centre[0]
    let y = xyz[1] - g.centre[1]
    let r = hypot(x, y)
    let radial = CylinderBessel.j(0, radialWave * ObliqueComplex(r))
    let derivative =
      r > 0
      ? radialWave * CylinderBessel.j(1, radialWave * ObliqueComplex(r)) / ObliqueComplex(r)
      : ObliqueComplex(0)
    let axial = cos(axialWave * xyz[2])
    return [
      radial * ObliqueComplex(axial * g.amplitude),
      derivative * ObliqueComplex(x * axial * g.amplitude / g.density) / rate,
      derivative * ObliqueComplex(y * axial * g.amplitude / g.density) / rate,
      radial * ObliqueComplex(axialWave * sin(axialWave * xyz[2]) * g.amplitude / g.density) / rate,
    ]
  }
  public func state(_ xyz: [Double], time: Double) -> [Double] {
    let phase = (rate * ObliqueComplex(time)).exp
    return amplitudes(xyz).map { ($0 * phase).real }
  }
  /// Lommel radial integrals, with the conjugate root for squared magnitudes.
  public func energy(time: Double) -> Double {
    let g = specification.geometry
    let R = g.radius
    let a = radialWave
    let b = ObliqueComplex(a.real, -a.imag)
    let ja = [CylinderBessel.j(0, root), CylinderBessel.j(1, root)]
    let jb = ja.map { ObliqueComplex($0.real, -$0.imag) }
    let j2a = ObliqueComplex(2) * ja[1] / root - ja[0]
    let j2b = ObliqueComplex(j2a.real, -j2a.imag)
    let norms = [
      (ObliqueComplex(R) * (a * ja[1] * jb[0] - b * ja[0] * jb[1]) / (a * a - b * b)).real,
      (ObliqueComplex(R) * (a * j2a * jb[1] - b * ja[1] * j2b) / (a * a - b * b)).real,
    ]
    let squares = [
      (ja[0] * ja[0] + ja[1] * ja[1]) * ObliqueComplex(R * R / 2),
      (ja[1] * ja[1] - ja[0] * j2a) * ObliqueComplex(R * R / 2),
    ]
    let phase = (rate * ObliqueComplex(time)).exp * ObliqueComplex(g.amplitude)
    func integral(_ coefficient: ObliqueComplex, _ order: Int) -> Double {
      (pow(coefficient.magnitude, 2) * norms[order]
        + (coefficient * coefficient * squares[order]).real) / 2
    }
    return Double.pi * g.lengths[2] / 2
      * (integral(phase, 0) / (g.density * g.speed * g.speed)
        + g.density * integral(phase * radialWave / (ObliqueComplex(g.density) * rate), 1)
        + g.density * integral(phase * ObliqueComplex(axialWave / g.density) / rate, 0))
  }
  public func dissipated(time: Double) -> Double {
    let g = specification.geometry
    let wall = CylinderBessel.j(0, root) * ObliqueComplex(g.amplitude)
    let first = pow(wall.magnitude, 2) * expm1(2 * rate.real * time) / (2 * rate.real)
    let second =
      (wall * wall * ((rate * ObliqueComplex(2 * time)).exp - ObliqueComplex(1))
      / (ObliqueComplex(2) * rate)).real
    return Double.pi * g.radius * g.lengths[2] * (first + second)
      / (2 * g.density * g.speed * specification.impedance)
  }
}
public enum AbsorbingCylinderOracle {
  public static func resolutions(_ c: AbsorbingCylinderCase) throws -> [CylinderResolution] {
    let ref = try AbsorbingCylinderReference(c)
    let g = c.geometry
    func count(_ n: Int, _ courant: Double) -> Int {
      8 * Int(ceil(ref.duration * g.speed * sqrt(3) * Double(n) / g.lengths[0] / courant / 8))
    }
    return [16, 32, 64].map {
      CylinderResolution(axis: "space", nx: $0, ny: $0, nz: $0 / 2, steps: count(64, 0.2))
    }
      + [0.8, 0.4, 0.2].map {
        CylinderResolution(axis: "time", nx: 32, ny: 32, nz: 16, steps: count(32, $0))
      }
  }
  /// Ideal circle normals, independent of application polygon/nearest-face queries.
  public static func faces(_ c: AbsorbingCylinderCase, _ r: CylinderResolution, dt: Double) throws
    -> [Float]
  {
    let grid = try CylinderGrid(c.geometry, r)
    let count = grid.labels.count
    var faces = grid.faces
    for cell in grid.labels.indices where grid.labels[cell] >= 0 {
      let xyz = grid.coordinates(cell, shape: r.dimensions)
      for side in 0..<4 where faces[side * count + cell] == 0 {
        var point = (0..<3).map { (Double(xyz[$0]) + 0.5) * grid.spacing[$0] }
        point[side / 2] += (side % 2 == 0 ? -0.5 : 0.5) * grid.spacing[side / 2]
        let x = point[0] - c.geometry.centre[0]
        let y = point[1] - c.geometry.centre[1]
        let weight = hypot(x, y) / (abs(x) + abs(y))
        faces[side * count + cell] = Float(
          c.geometry.speed * dt * weight / (2 * c.impedance * grid.spacing[side / 2]))
      }
    }
    return faces
  }
  public static func wallCells(_ grid: CylinderGrid) -> [Int] {
    let faces = grid.faces
    let count = grid.labels.count
    return grid.labels.indices.filter { cell in
      grid.labels[cell] >= 0 && (0..<4).contains { side in faces[side * count + cell] == 0 }
    }
  }
  public static func rates(_ grid: CylinderGrid, faces: [Float], dt: Double) throws -> [Double] {
    guard faces.count == 6 * grid.labels.count, dt.isFinite, dt > 0 else {
      throw BenchmarkFailure.invalidSamples
    }
    return grid.labels.indices.map { cell in
      grid.labels[cell] >= 0
        ? 2 * (0..<6).reduce(0.0) { $0 + max(0, Double(faces[$1 * grid.labels.count + cell])) } / dt
        : 0
    }
  }
  public static func initial(_ c: AbsorbingCylinderCase, _ r: CylinderResolution, dt: Double) throws
    -> RigidModeFrame
  {
    let grid = try CylinderGrid(c.geometry, r)
    let ref = try AbsorbingCylinderReference(c)
    let g = c.geometry
    let seed = try continuum(ref, r, grid: grid, dt: dt, captures: [0]).frames[0]
    // Exact physical velocity at t=0 plus the discrete Taylor backward half kick.
    var velocities = (1...3).map { field in
      [Double](repeating: 0, count: grid.fieldDimensions(field).reduce(1, *))
    }
    for axis in 0..<3 {
      let shape = grid.fieldDimensions(axis + 1)
      let stride = [1, r.nx, r.nx * r.ny][axis]
      for index in velocities[axis].indices where grid.openFields[axis + 1][index] {
        let xyz = grid.coordinates(index, shape: shape)
        let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
        let point = (0..<3).map { (Double(xyz[$0]) + ($0 == axis ? 0 : 0.5)) * grid.spacing[$0] }
        velocities[axis][index] =
          ref.state(point, time: 0)[axis + 1] + dt * (seed.p[plus] - seed.p[plus - stride])
          / (2 * g.density * grid.spacing[axis])
      }
    }
    return RigidModeFrame(step: 0, p: seed.p, u: velocities[0], v: velocities[1], w: velocities[2])
  }
  static func continuum(
    _ ref: AbsorbingCylinderReference, _ r: CylinderResolution, grid: CylinderGrid, dt: Double,
    captures: [Int]
  ) throws -> RigidModeHistory {
    let g = ref.specification.geometry
    let amplitudes = (0...3).map { field in
      let shape = grid.fieldDimensions(field)
      return (0..<shape.reduce(1, *)).map { index -> ObliqueComplex in
        guard grid.openFields[field][index] else { return ObliqueComplex(0) }
        let xyz = grid.coordinates(index, shape: shape)
        return ref.amplitudes(
          (0..<3).map { (Double(xyz[$0]) + ($0 + 1 == field ? 0 : 0.5)) * grid.spacing[$0] })[field]
      }
    }
    return RigidModeHistory(
      spacing: grid.spacing, dt: dt,
      frames: captures.map { step in
        let fields = (0...3).map { field in
          let phase = (ref.rate * ObliqueComplex(Double(step) * dt - (field > 0 ? dt / 2 : 0))).exp
          return amplitudes[field].indices.map { index in
            grid.openFields[field][index]
              ? (amplitudes[field][index] * phase).real : field == 0 ? g.inactivePressure : 0
          }
        }
        return RigidModeFrame(step: step, p: fields[0], u: fields[1], v: fields[2], w: fields[3])
      })
  }
  public static func history(
    _ c: AbsorbingCylinderCase, _ r: CylinderResolution, faces: [Float], dt: Double
  ) throws -> (fields: RigidModeHistory, work: [Double]) {
    let grid = try CylinderGrid(c.geometry, r)
    let ref = try AbsorbingCylinderReference(c)
    let g = c.geometry
    if r.axis == "space" {
      return (
        try continuum(ref, r, grid: grid, dt: dt, captures: r.captures),
        r.captures.map { ref.dissipated(time: Double($0) * dt) }
      )
    }
    let rates = try rates(grid, faces: faces, dt: dt)
    let graph = try MaskedLattice(
      dimensions: r.dimensions, spacing: grid.spacing, inside: grid.inside, speed: g.speed,
      wallRates: rates)
    let seed = try continuum(ref, r, grid: grid, dt: 0, captures: [0]).frames[0]
    var state =
      graph.cells.map { seed.p[$0] }
      + graph.edges.map { edge in
        var xyz = grid.coordinates(edge.cell, shape: r.dimensions)
        xyz[edge.axis] += 1
        let shape = grid.fieldDimensions(edge.axis + 1)
        let index = xyz[0] + shape[0] * (xyz[1] + shape[1] * xyz[2])
        return seed.fields[edge.axis + 1][index] * g.density * g.speed
      }
    let scale = grid.spacing.reduce(1, *) / (2 * g.density * g.speed * g.speed)
    let e0 = state.reduce(0) { $0 + $1 * $1 } * scale
    var frames: [RigidModeFrame] = []
    var work: [Double] = []
    var clock = 0.0
    for step in r.captures {
      let time = Double(step) * dt
      state = try graph.evolve(state, time: time - clock)
      clock = time
      let half = try graph.evolve(state, time: -dt / 2)
      var p = [Double](repeating: g.inactivePressure, count: grid.labels.count)
      var velocities = (1...3).map {
        [Double](repeating: 0, count: grid.fieldDimensions($0).reduce(1, *))
      }
      for (i, cell) in graph.cells.enumerated() { p[cell] = state[i] }
      for (i, edge) in graph.edges.enumerated() {
        var xyz = grid.coordinates(edge.cell, shape: r.dimensions)
        xyz[edge.axis] += 1
        let shape = grid.fieldDimensions(edge.axis + 1)
        let index = xyz[0] + shape[0] * (xyz[1] + shape[1] * xyz[2])
        velocities[edge.axis][index] = half[graph.cells.count + i] / (g.density * g.speed)
      }
      frames.append(
        RigidModeFrame(step: step, p: p, u: velocities[0], v: velocities[1], w: velocities[2]))
      work.append(max(0, e0 - state.reduce(0) { $0 + $1 * $1 } * scale))
    }
    return (RigidModeHistory(spacing: grid.spacing, dt: dt, frames: frames), work)
  }
}
