import Darwin
import Foundation

/// A Neumann radial mode with nonzero axial variation; pressures in Pa and velocities in m/s.
public struct CylinderCase: Codable, Equatable, Sendable {
  public let version: Int
  public let id: String
  public let lengths: [Double]
  public let centre: [Double]
  public let radius: Double
  public let radialRoot: Double
  public let density, speed, amplitude, inactivePressure: Double
  public init() {
    version = 1
    id = "rigid-cylinder"
    lengths = [0.25, 0.25, 0.125]
    centre = [0.125, 0.125]
    radius = 0.09375
    radialRoot = 3.8317059702075123156
    density = 1.25
    speed = 320
    amplitude = 1
    inactivePressure = 100
  }
  public func validate() throws {
    guard self == Self() else { throw BenchmarkFailure.invalidCase }
  }
  public var radialWave: Double { radialRoot / radius }
  public var axialWave: Double { Double.pi / lengths[2] }
  public var norm: Double { hypot(radialWave, axialWave) }
  public var duration: Double { 2 * Double.pi / (speed * norm) }
  public var volume: Double { Double.pi * radius * radius * lengths[2] }
  public var energy: Double {
    amplitude * amplitude * volume * pow(j0(radialRoot), 2) / (4 * density * speed * speed)
  }
  public static func standard() throws -> [Self] { [Self()] }
  public func state(_ xyz: [Double], time: Double) -> [Double] {
    let x = xyz[0] - centre[0]
    let y = xyz[1] - centre[1]
    let radius = hypot(x, y)
    let radial = j0(radialWave * radius)
    let axial = cos(axialWave * xyz[2])
    let phase = speed * norm * time
    let common = amplitude / (density * speed * norm) * sin(phase)
    let derivative = radius > 0 ? radialWave * j1(radialWave * radius) / radius : 0
    return [
      amplitude * radial * axial * cos(phase), common * derivative * x * axial,
      common * derivative * y * axial, common * axialWave * radial * sin(axialWave * xyz[2]),
    ]
  }
}
public struct CylinderResolution: Codable, Equatable, Sendable {
  public let axis: String
  public let nx, ny, nz, steps: Int
  public init(axis: String, nx: Int, ny: Int, nz: Int, steps: Int) {
    self.axis = axis
    self.nx = nx
    self.ny = ny
    self.nz = nz
    self.steps = steps
  }
  public var dimensions: [Int] { [nx, ny, nz] }
  public var captures: [Int] { (0...8).map { $0 * steps / 8 } }
  public static func standard(_ c: CylinderCase) -> [Self] {
    func count(_ n: Int, _ courant: Double) -> Int {
      8 * Int(ceil(c.duration * c.speed * sqrt(3) * Double(n) / c.lengths[0] / courant / 8))
    }
    return [16, 32, 64].map {
      Self(axis: "space", nx: $0, ny: $0, nz: $0 / 2, steps: count(64, 0.25))
    }
      + [0.8, 0.4, 0.2].map { Self(axis: "time", nx: 32, ny: 32, nz: 16, steps: count(32, $0)) }
  }
}
/// Independent integer occupancy and face connectivity; not produced by an application's mesh code.
public struct CylinderGrid: Codable, Sendable {
  public let dimensions: [Int], spacing: [Double], labels: [Int]
  public let openFields: [[Bool]]
  public var inside: [UInt8] { labels.map { $0 < 0 ? 0 : 1 } }
  /// Matches the declared rigid-face contract; inactive coefficients are unused -1 sentinels.
  public var faces: [Float] {
    let count = labels.count
    var result = [Float](repeating: -1, count: 6 * count)
    let offsets = [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]]
    for index in labels.indices where labels[index] >= 0 {
      let xyz = coordinates(index, shape: dimensions)
      for side in 0..<6 {
        let other = zip(xyz, offsets[side]).map(+)
        result[side * count + index] = label(other) >= 0 ? -1 : 0
      }
    }
    return result
  }
  public init(_ c: CylinderCase, _ r: CylinderResolution) throws {
    try c.validate()
    guard r.dimensions.allSatisfy({ $0 >= 2 && $0 <= 128 }), r.steps > 0,
      ["space", "time"].contains(r.axis)
    else { throw BenchmarkFailure.invalidCase }
    dimensions = r.dimensions
    spacing = zip(c.lengths, r.dimensions).map { $0 / Double($1) }
    let cellSpacing = spacing
    labels = (0..<r.dimensions.reduce(1, *)).map { index in
      let x = (Double(index % r.nx) + 0.5) * cellSpacing[0] - c.centre[0]
      let y = (Double(index / r.nx % r.ny) + 0.5) * cellSpacing[1] - c.centre[1]
      return x * x + y * y < c.radius * c.radius ? 0 : -1
    }
    let storedLabels = labels
    let dims = dimensions
    func labelAt(_ xyz: [Int]) -> Int {
      guard (0..<3).allSatisfy({ xyz[$0] >= 0 && xyz[$0] < dims[$0] }) else { return -1 }
      return storedLabels[xyz[0] + dims[0] * (xyz[1] + dims[1] * xyz[2])]
    }
    openFields =
      [labels.map { $0 >= 0 }]
      + (0..<3).map { axis in
        var shape = dims
        shape[axis] += 1
        return (0..<shape.reduce(1, *)).map { index in
          let xyz = [index % shape[0], index / shape[0] % shape[1], index / (shape[0] * shape[1])]
          var left = xyz
          left[axis] -= 1
          let a = labelAt(left)
          let b = labelAt(xyz)
          return a >= 0 && a == b
        }
      }
  }
  public func fieldDimensions(_ field: Int) -> [Int] {
    var d = dimensions
    if field > 0 { d[field - 1] += 1 }
    return d
  }
  public func coordinates(_ index: Int, shape: [Int]) -> [Int] {
    [index % shape[0], index / shape[0] % shape[1], index / (shape[0] * shape[1])]
  }
  public func label(_ xyz: [Int]) -> Int {
    guard xyz.count == 3, (0..<3).allSatisfy({ xyz[$0] >= 0 && xyz[$0] < dimensions[$0] }) else {
      return -1
    }
    return labels[xyz[0] + dimensions[0] * (xyz[1] + dimensions[1] * xyz[2])]
  }
  public func component(field: Int, index: Int) -> Int {
    label(coordinates(index, shape: fieldDimensions(field)))
  }
}

/// Independent continuous-time graph operator, state [active p, rho*c*open-face velocity].
/// Every edge contributes equal/opposite pressure fluxes and one pressure-gradient rate.
public struct MaskedLattice: Sendable {
  public struct Edge: Sendable {
    public let left, right, axis, cell: Int
    public let rate: Double
  }
  public let dimensions: [Int], inside: [UInt8], cells: [Int], edges: [Edge]
  public let normBound: Double
  public var stateCount: Int { cells.count + edges.count }
  public init(dimensions: [Int], spacing: [Double], inside: [UInt8], speed: Double) throws {
    guard dimensions.count == 3, dimensions.allSatisfy({ $0 > 0 && $0 <= 128 }),
      dimensions.reduce(1, *) <= 65536,
      spacing.count == 3, spacing.allSatisfy({ $0.isFinite && $0 > 0 }),
      inside.count == dimensions.reduce(1, *), inside.allSatisfy({ $0 <= 1 }), speed.isFinite,
      speed > 0
    else { throw BenchmarkFailure.invalidCase }
    self.dimensions = dimensions
    self.inside = inside
    cells = inside.indices.filter { inside[$0] == 1 }
    guard !cells.isEmpty else { throw BenchmarkFailure.invalidCase }
    var indices = [Int](repeating: -1, count: inside.count)
    for (i, cell) in cells.enumerated() { indices[cell] = i }
    var all: [Edge] = []
    let strides = [1, dimensions[0], dimensions[0] * dimensions[1]]
    for cell in cells {
      let xyz = [
        cell % dimensions[0], cell / dimensions[0] % dimensions[1],
        cell / (dimensions[0] * dimensions[1]),
      ]
      for axis in 0..<3 where xyz[axis] + 1 < dimensions[axis] && inside[cell + strides[axis]] == 1
      {
        all.append(
          Edge(
            left: indices[cell], right: indices[cell + strides[axis]], axis: axis, cell: cell,
            rate: speed / spacing[axis]))
      }
    }
    edges = all
    normBound = 2 * spacing.reduce(0) { $0 + speed / $1 }
    guard normBound.isFinite else { throw BenchmarkFailure.invalidCase }
  }
  private func action(_ y: [Double]) -> [Double] {
    var z = [Double](repeating: 0, count: stateCount)
    for (i, e) in edges.enumerated() {
      let velocity = y[cells.count + i] * e.rate
      z[e.left] -= velocity
      z[e.right] += velocity
      z[cells.count + i] = e.rate * (y[e.left] - y[e.right])
    }
    return z
  }
  /// Degree-20 Taylor action with ||h A||∞ <= 1/2; practical accuracy is limited by Float64 roundoff.
  public func evolve(_ initial: [Double], time: Double) throws -> [Double] {
    guard initial.count == stateCount, initial.allSatisfy(\.isFinite), time.isFinite else {
      throw BenchmarkFailure.invalidSamples
    }
    let extent = abs(time) * normBound
    guard extent.isFinite, extent <= 500000 else { throw BenchmarkFailure.invalidSamples }
    let subdivisions = max(1, Int(ceil(2 * extent)))
    let h = time / Double(subdivisions)
    var y = initial
    for _ in 0..<subdivisions {
      var term = y
      var sum = y
      for degree in 1...20 {
        let derivative = action(term)
        for i in y.indices {
          term[i] = derivative[i] * h / Double(degree)
          sum[i] += term[i]
        }
      }
      guard sum.allSatisfy(\.isFinite) else { throw BenchmarkFailure.invalidSamples }
      y = sum
    }
    return y
  }
}
public enum CylinderOracle {
  public static func history(
    _ c: CylinderCase, _ r: CylinderResolution, spacing: [Double]? = nil, dt: Double? = nil,
    captures: [Int]? = nil
  ) throws -> RigidModeHistory {
    let grid = try CylinderGrid(c, r)
    let spacing = spacing ?? grid.spacing
    let dt = dt ?? c.duration / Double(r.steps)
    guard spacing.count == 3, spacing.allSatisfy({ $0.isFinite && $0 > 0 }), dt.isFinite, dt > 0
    else { throw BenchmarkFailure.invalidSamples }
    let captures = captures ?? r.captures
    if r.axis == "time" {
      return try temporal(c, r, grid: grid, spacing: spacing, dt: dt, captures: captures)
    }
    let amplitudes = (0...3).map { field in
      let shape = grid.fieldDimensions(field)
      return (0..<shape.reduce(1, *)).map { index -> Double in
        guard grid.openFields[field][index] else { return field == 0 ? c.inactivePressure : 0 }
        let xyz = grid.coordinates(index, shape: shape)
        let position = (0..<3).map { (Double(xyz[$0]) + (field == $0 + 1 ? 0 : 0.5)) * spacing[$0] }
        return c.state(position, time: field == 0 ? 0 : c.duration / 4)[field]
      }
    }
    let frames = captures.map { step in
      let fields = (0...3).map { field in
        let phase = c.speed * c.norm * (Double(step) * dt - (field > 0 ? dt / 2 : 0))
        return amplitudes[field].indices.map { index in
          guard grid.openFields[field][index] else { return field == 0 ? c.inactivePressure : 0 }
          return amplitudes[field][index] * (field == 0 ? cos(phase) : sin(phase))
        }
      }
      return RigidModeFrame(step: step, p: fields[0], u: fields[1], v: fields[2], w: fields[3])
    }
    return RigidModeHistory(spacing: spacing, dt: dt, frames: frames)
  }
  private static func temporal(
    _ c: CylinderCase, _ r: CylinderResolution, grid: CylinderGrid, spacing: [Double], dt: Double,
    captures: [Int]
  ) throws -> RigidModeHistory {
    let lattice = try MaskedLattice(
      dimensions: r.dimensions, spacing: spacing, inside: grid.inside, speed: c.speed)
    var state =
      lattice.cells.map { index in
        let xyz = grid.coordinates(index, shape: r.dimensions)
        return c.state((0..<3).map { (Double(xyz[$0]) + 0.5) * spacing[$0] }, time: 0)[0]
      } + [Double](repeating: 0, count: lattice.edges.count)
    var frames: [RigidModeFrame] = []
    var clock = 0.0
    for step in captures {
      let time = Double(step) * dt
      state = try lattice.evolve(state, time: time - clock)
      clock = time
      let half = try lattice.evolve(state, time: -dt / 2)
      var p = [Double](repeating: c.inactivePressure, count: grid.labels.count)
      var velocities = (1...3).map {
        [Double](repeating: 0, count: grid.fieldDimensions($0).reduce(1, *))
      }
      for (i, cell) in lattice.cells.enumerated() { p[cell] = state[i] }
      for (i, edge) in lattice.edges.enumerated() {
        var xyz = grid.coordinates(edge.cell, shape: r.dimensions)
        xyz[edge.axis] += 1
        let shape = grid.fieldDimensions(edge.axis + 1)
        let index = xyz[0] + shape[0] * (xyz[1] + shape[1] * xyz[2])
        velocities[edge.axis][index] = half[lattice.cells.count + i] / (c.density * c.speed)
      }
      frames.append(
        RigidModeFrame(step: step, p: p, u: velocities[0], v: velocities[1], w: velocities[2]))
    }
    return RigidModeHistory(spacing: spacing, dt: dt, frames: frames)
  }
  public static func initial(
    _ c: CylinderCase, _ r: CylinderResolution, spacing: [Double], dt: Double
  ) throws -> RigidModeFrame {
    let grid = try CylinderGrid(c, r)
    guard spacing.count == 3, spacing.allSatisfy({ $0.isFinite && $0 > 0 }), dt.isFinite, dt > 0
    else { throw BenchmarkFailure.invalidSamples }
    let p = grid.labels.indices.map { index -> Double in
      guard grid.labels[index] >= 0 else { return c.inactivePressure }
      let xyz = grid.coordinates(index, shape: r.dimensions)
      return c.state((0..<3).map { (Double(xyz[$0]) + 0.5) * spacing[$0] }, time: 0)[0]
    }
    let velocities = (0..<3).map { axis in
      let shape = grid.fieldDimensions(axis + 1)
      let stride = axis == 0 ? 1 : axis == 1 ? r.nx : r.nx * r.ny
      return (0..<shape.reduce(1, *)).map { index -> Double in
        guard grid.openFields[axis + 1][index] else { return 0 }
        let xyz = grid.coordinates(index, shape: shape)
        let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
        return dt * (p[plus] - p[plus - stride]) / (2 * c.density * spacing[axis])
      }
    }
    return RigidModeFrame(step: 0, p: p, u: velocities[0], v: velocities[1], w: velocities[2])
  }
}
