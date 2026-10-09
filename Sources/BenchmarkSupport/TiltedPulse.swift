import Foundation

/// One plane pulse, before finite-plan corner returns can reach the declared observation region.
public struct TiltedPulseCase: Codable, Equatable, Sendable {
  public let version: Int, id: String
  public let lengths, normal, reflectedDirection: [Double]
  public let intercept, density, speed, amplitude, inactivePressure, impedance: Double
  public let centre, halfWidth, travel, roiYMinimum, roiYMaximum, wallClearance,
    patchHalfWidth: Double
  public init() {
    version = 1
    id = "tilted-plan-pulse-xi3"
    lengths = [0.5, 0.5, 0.00390625]
    normal = [2 / sqrt(5), 1 / sqrt(5), 0]
    reflectedDirection = [-0.6, -0.8, 0]
    intercept = 0.45
    density = 1.25
    speed = 320
    amplitude = 1
    inactivePressure = 100
    impedance = 3
    centre = 0.075
    halfWidth = 0.04
    travel = 0.31
    roiYMinimum = 0.235
    roiYMaximum = 0.265
    wallClearance = 0.015
    patchHalfWidth = 0.018
  }
  public func validate() throws { guard self == Self() else { throw BenchmarkFailure.invalidCase } }
  public var duration: Double { travel / speed }
  public var reflection: Double { (impedance * normal[0] - 1) / (impedance * normal[0] + 1) }
  public var sideArea: Double { lengths[1] / normal[0] * lengths[2] }
  public var volume: Double {
    (intercept + (intercept - lengths[1] / 2)) / 2 * lengths[1] * lengths[2]
  }
  public var pulseIntegral: Double { 35 * halfWidth / 64 }
  public var energy: Double { pulseIntegral * lengths[1] * lengths[2] / (density * speed * speed) }
  public var patchEnergy: Double {
    pulseIntegral * lengths[2] * (3 * patchHalfWidth / 4) / (density * speed * speed)
  }
  public var cornerArrivalTravel: Double {
    intercept - lengths[1] / 2 - centre - halfWidth + lengths[1] - roiYMaximum
  }
  public func pulse(_ phase: Double) -> Double {
    guard abs(phase) < halfWidth else { return 0 }
    return pow(cos(Double.pi * phase / (2 * halfWidth)), 4) * amplitude
  }
  public func pulseSquaredPrimitive(_ phase: Double) -> Double {
    let z = min(1, max(-1, phase / halfWidth))
    return halfWidth / 128
      * (35 * (z + 1) + 56 * sin(Double.pi * z) / Double.pi + 14 * sin(2 * Double.pi * z)
        / Double.pi + 8 * sin(3 * Double.pi * z) / (3 * Double.pi) + sin(4 * Double.pi * z)
        / (4 * Double.pi)) * amplitude * amplitude
  }
  public func patchWeight(_ y: Double) -> Double {
    let t = (y - 0.25) / patchHalfWidth
    return abs(t) < 1 ? pow(cos(Double.pi * t / 2), 4) : 0
  }
  public func reflectedShape(_ xyz: [Double], time: Double, shift: Double = 0) -> Double {
    pulse(
      reflectedDirection[0] * xyz[0] + reflectedDirection[1] * xyz[1] + 2 * normal[0] * normal[0]
        * intercept - centre - speed * time - shift)
  }
  public func state(_ xyz: [Double], time: Double) -> [Double] {
    let incident = pulse(xyz[0] - centre - speed * time)
    let reflected = reflection * reflectedShape(xyz, time: time)
    return [
      incident + reflected, (incident + reflectedDirection[0] * reflected) / (density * speed),
      reflectedDirection[1] * reflected / (density * speed), 0,
    ]
  }
  public func observation(_ xyz: [Double]) -> Bool {
    xyz[0] >= 0.05 && xyz[0] <= 0.35 && xyz[1] >= roiYMinimum && xyz[1] <= roiYMaximum
      && (intercept - xyz[0] - xyz[1] / 2) * normal[0] >= wallClearance
  }
  /// Independent physical plane work over the smooth central patch. Simpson y quadrature has 512 intervals.
  public func patchWork(time: Double) -> Double {
    let n = 512
    let dy = 2 * patchHalfWidth / Double(n)
    var integral = 0.0
    for i in 0...n {
      let y = 0.25 - patchHalfWidth + Double(i) * dy
      let s = intercept - y / 2 - centre
      let weight = i == 0 || i == n ? 1.0 : i.isMultiple(of: 2) ? 2 : 4
      integral +=
        weight * dy / 3 * patchWeight(y)
        * (pulseSquaredPrimitive(s) - pulseSquaredPrimitive(s - speed * time)) / speed
    }
    return integral * pow(1 + reflection, 2) * lengths[2]
      / (density * speed * impedance * normal[0])
  }
}
public struct TiltedPulseResolution: Codable, Equatable, Sendable {
  public let axis: String, nx: Int, ny: Int, nz: Int, steps: Int
  public init(axis: String, nx: Int, steps: Int) {
    self.axis = axis
    self.nx = nx
    ny = nx
    nz = 2
    self.steps = steps
  }
  public var dimensions: [Int] { [nx, ny, nz] }
  public var captures: [Int] { (0...8).map { $0 * steps / 8 } }
  public static func standard(_ c: TiltedPulseCase) -> [Self] {
    func steps(_ n: Int, _ courant: Double) -> Int {
      let inverse = sqrt(2 * pow(Double(n) / c.lengths[0], 2) + pow(2 / c.lengths[2], 2))
      return 8 * Int(ceil(c.travel * inverse / courant / 8))
    }
    return [64, 128, 256].map { Self(axis: "space", nx: $0, steps: steps(256, 0.2)) }
      + [0.8, 0.4, 0.2].map { Self(axis: "time", nx: 64, steps: steps(64, $0)) }
  }
}
/// Analytic half-plane occupancy, native staggered connectivity and independent segment projection.
public struct TiltedPulseGrid: Sendable {
  public let dimensions: [Int], spacing: [Double], inside: [UInt8], openFields: [[Bool]],
    faceKinds: [Int]
  public let specification: TiltedPulseCase
  public init(_ c: TiltedPulseCase, _ r: TiltedPulseResolution) throws {
    try c.validate()
    guard r.nx >= 4, r.nx <= 256, r.ny == r.nx, r.nz == 2, r.steps > 0, r.steps % 8 == 0,
      ["space", "time"].contains(r.axis)
    else { throw BenchmarkFailure.invalidCase }
    specification = c
    dimensions = r.dimensions
    spacing = zip(c.lengths, r.dimensions).map { $0 / Double($1) }
    let d = spacing
    let nx = r.nx
    let ny = r.ny
    let nz = r.nz
    let count = nx * ny * nz
    let flags = (0..<count).map { i -> UInt8 in
      (Double(i % nx) + 0.5) * d[0] + 0.5 * (Double(i / nx % ny) + 0.5) * d[1] < c.intercept ? 1 : 0
    }
    inside = flags
    func active(_ xyz: [Int]) -> Bool {
      (0..<3).allSatisfy { xyz[$0] >= 0 && xyz[$0] < r.dimensions[$0] }
        && flags[xyz[0] + nx * (xyz[1] + ny * xyz[2])] == 1
    }
    openFields =
      [flags.map { $0 == 1 }]
      + (0..<3).map { axis in
        var shape = r.dimensions
        shape[axis] += 1
        return (0..<shape.reduce(1, *)).map { index in
          let xyz = [index % shape[0], index / shape[0] % shape[1], index / (shape[0] * shape[1])]
          var left = xyz
          left[axis] -= 1
          return active(xyz) && active(left)
        }
      }
    let offsets = [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]]
    let corners = [
      [0.0, 0.0], [c.intercept, 0], [c.intercept - c.lengths[1] / 2, c.lengths[1]],
      [0, c.lengths[1]],
    ]
    func nearest(_ p: [Double]) -> Int {
      var best = Double.infinity
      var result = 0
      for side in 0..<4 {
        let a = corners[side]
        let b = corners[(side + 1) % 4]
        let dx = b[0] - a[0]
        let dy = b[1] - a[1]
        let t = max(0, min(1, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy)))
        let distance = hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)
        if distance < best {
          best = distance
          result = side
        }
      }
      return result
    }
    var kinds = [Int](repeating: -1, count: 6 * count)
    for cell in 0..<count where flags[cell] == 1 {
      let xyz = [cell % nx, cell / nx % ny, cell / (nx * ny)]
      for side in 0..<6 where !active(zip(xyz, offsets[side]).map(+)) {
        var p = (0..<3).map { (Double(xyz[$0]) + 0.5) * d[$0] }
        p[side / 2] += (side % 2 == 0 ? -0.5 : 0.5) * d[side / 2]
        kinds[side * count + cell] = side < 4 && nearest(p) == 1 ? 1 : 0
      }
    }
    faceKinds = kinds
  }
  public func shape(_ field: Int) -> [Int] {
    var s = dimensions
    if field > 0 { s[field - 1] += 1 }
    return s
  }
  public func position(_ field: Int, _ index: Int) -> [Double] {
    let s = shape(field)
    let xyz = [index % s[0], index / s[0] % s[1], index / (s[0] * s[1])]
    return (0..<3).map { (Double(xyz[$0]) + ($0 + 1 == field ? 0 : 0.5)) * spacing[$0] }
  }
  public var wallCells: [Int] {
    (0..<inside.count).filter { cell in
      inside[cell] == 1 && (0..<4).contains { faceKinds[$0 * inside.count + cell] == 1 }
    }
  }
  public func faces(dt: Double) -> [Float] {
    faceKinds.enumerated().map { i, kind in
      kind < 0
        ? -1
        : kind == 0
          ? 0
          : Float(
            specification.speed * dt
              / (2 * specification.impedance * spacing[(i / inside.count) / 2]
                * (specification.normal[0] + specification.normal[1])))
    }
  }
  public func rates(faces: [Float], dt: Double) throws -> (total: [Double], patch: [Double]) {
    guard faces.count == faceKinds.count, dt.isFinite, dt > 0 else {
      throw BenchmarkFailure.invalidSamples
    }
    var total = [Double](repeating: 0, count: inside.count)
    var patch = total
    let c = specification
    let n = c.normal
    let h = c.intercept * n[0]
    for cell in wallCells {
      for side in 0..<4 where faceKinds[side * inside.count + cell] == 1 {
        let beta = Double(faces[side * inside.count + cell])
        var p = position(0, cell)
        p[side / 2] += (side % 2 == 0 ? -0.5 : 0.5) * spacing[side / 2]
        let distance = n[0] * p[0] + n[1] * p[1] - h
        let y = p[1] - n[1] * distance
        total[cell] += 2 * beta / dt
        patch[cell] += 2 * beta / dt * c.patchWeight(y)
      }
    }
    return (total, patch)
  }
}
/// Independent continuous-time graph exponential and polynomial pressure-squared work integration.
/// State is pressure and rho*c*edge velocity; this is verification code, not an application stepper.
struct PulseGraphReference {
  let graph: MaskedLattice, patchRates: [Double], normBound: Double
  init(graph: MaskedLattice, patchRates: [Double]) throws {
    guard patchRates.count == graph.cells.count,
      patchRates.enumerated().allSatisfy({
        $0.element.isFinite && $0.element >= 0
          && $0.element <= graph.wallRates[$0.offset] * (1 + 1e-12)
      })
    else { throw BenchmarkFailure.invalidCase }
    self.graph = graph
    self.patchRates = patchRates
    var rows = graph.wallRates
    for e in graph.edges {
      rows[e.left] += e.rate
      rows[e.right] += e.rate
    }
    normBound = max(rows.max() ?? 0, graph.edges.map { 2 * $0.rate }.max() ?? 0)
  }
  func action(_ y: [Double]) -> [Double] {
    var z = [Double](repeating: 0, count: graph.stateCount)
    for i in graph.cells.indices { z[i] = -graph.wallRates[i] * y[i] }
    for (i, e) in graph.edges.enumerated() {
      let v = y[graph.cells.count + i] * e.rate
      z[e.left] -= v
      z[e.right] += v
      z[graph.cells.count + i] = e.rate * (y[e.left] - y[e.right])
    }
    return z
  }
  func evolve(_ initial: [Double], time: Double) throws -> (state: [Double], patchIntegral: Double)
  {
    guard initial.count == graph.stateCount, initial.allSatisfy(\.isFinite), time.isFinite,
      abs(time) * normBound < 500000
    else { throw BenchmarkFailure.invalidSamples }
    let subdivisions = max(1, Int(ceil(2 * abs(time) * normBound)))
    let h = time / Double(subdivisions)
    var y = initial
    var work = 0.0
    let wall = patchRates.indices.filter { patchRates[$0] > 0 }
    for _ in 0..<subdivisions {
      var term = y
      var sum = y
      var coefficients = [wall.map { y[$0] }]
      for degree in 1...20 {
        let derivative = action(term)
        for i in term.indices {
          term[i] = derivative[i] * h / Double(degree)
          sum[i] += term[i]
        }
        coefficients.append(wall.map { term[$0] })
      }
      for (j, cell) in wall.enumerated() {
        var integral = 0.0
        for a in 0...20 {
          for b in 0...20 {
            integral += coefficients[a][j] * coefficients[b][j] / Double(a + b + 1)
          }
        }
        work += h * patchRates[cell] * integral
      }
      guard sum.allSatisfy(\.isFinite), work.isFinite else { throw BenchmarkFailure.invalidSamples }
      y = sum
    }
    return (y, work)
  }
}
public enum TiltedPulseOracle {
  public static func initial(_ c: TiltedPulseCase, _ r: TiltedPulseResolution, dt: Double) throws
    -> RigidModeFrame
  {
    let grid = try TiltedPulseGrid(c, r)
    let count = grid.inside.count
    let p = (0..<count).map {
      grid.inside[$0] == 1 ? c.state(grid.position(0, $0), time: 0)[0] : c.inactivePressure
    }
    let velocities = (0..<3).map { axis in
      let shape = grid.shape(axis + 1)
      let stride = [1, r.nx, r.nx * r.ny][axis]
      return (0..<shape.reduce(1, *)).map { index -> Double in
        guard grid.openFields[axis + 1][index] else { return 0 }
        let xyz = [index % shape[0], index / shape[0] % shape[1], index / (shape[0] * shape[1])]
        let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
        return c.state(grid.position(axis + 1, index), time: 0)[axis + 1] + dt
          * (p[plus] - p[plus - stride]) / (2 * c.density * grid.spacing[axis])
      }
    }
    return RigidModeFrame(step: 0, p: p, u: velocities[0], v: velocities[1], w: velocities[2])
  }
  public static func history(
    _ c: TiltedPulseCase, _ r: TiltedPulseResolution, faces: [Float], dt: Double
  ) throws -> (fields: RigidModeHistory, work: [Double], patchWork: [Double]) {
    let grid = try TiltedPulseGrid(c, r)
    if r.axis == "space" {
      let frames = r.captures.map { step in
        let fields = (0...3).map { field in
          (0..<grid.shape(field).reduce(1, *)).map { index -> Double in
            guard grid.openFields[field][index] else { return field == 0 ? c.inactivePressure : 0 }
            return c.state(
              grid.position(field, index), time: Double(step) * dt - (field > 0 ? dt / 2 : 0))[
                field]
          }
        }
        return RigidModeFrame(step: step, p: fields[0], u: fields[1], v: fields[2], w: fields[3])
      }
      return (
        RigidModeHistory(spacing: grid.spacing, dt: dt, frames: frames), [],
        r.captures.map { c.patchWork(time: Double($0) * dt) }
      )
    }
    // The source and seed are z invariant with rigid caps. Reduce exactly to one xy layer.
    let plane = r.nx * r.ny
    let rates = try grid.rates(faces: faces, dt: dt)
    let graph = try MaskedLattice(
      dimensions: [r.nx, r.ny, 1], spacing: grid.spacing, inside: Array(grid.inside.prefix(plane)),
      speed: c.speed, wallRates: Array(rates.total.prefix(plane)))
    let reference = try PulseGraphReference(
      graph: graph, patchRates: graph.cells.map { rates.patch[$0] })
    var state =
      graph.cells.map { c.state(grid.position(0, $0), time: 0)[0] }
      + graph.edges.map { e -> Double in
        let i = e.cell % r.nx + (e.axis == 0 ? 1 : 0)
        let j = e.cell / r.nx + (e.axis == 1 ? 1 : 0)
        return c.state(
          [Double(i) + (e.axis == 0 ? 0 : 0.5), Double(j) + (e.axis == 1 ? 0 : 0.5), 0].enumerated()
            .map { $0.element * grid.spacing[$0.offset] }, time: 0)[e.axis + 1] * c.density
          * c.speed
      }
    let scale = grid.spacing[0] * grid.spacing[1] * c.lengths[2] / (c.density * c.speed * c.speed)
    let e0 = state.reduce(0) { $0 + $1 * $1 } * scale / 2
    var frames: [RigidModeFrame] = []
    var work: [Double] = []
    var patch: [Double] = []
    var clock = 0.0
    var patchIntegral = 0.0
    for step in r.captures {
      let t = Double(step) * dt
      let evolved = try reference.evolve(state, time: t - clock)
      state = evolved.state
      patchIntegral += evolved.patchIntegral
      clock = t
      let half = try reference.evolve(state, time: -dt / 2).state
      var p = [Double](repeating: c.inactivePressure, count: grid.inside.count)
      var velocities = (1...3).map { [Double](repeating: 0, count: grid.shape($0).reduce(1, *)) }
      for (i, cell) in graph.cells.enumerated() {
        for k in 0..<r.nz { p[cell + k * plane] = state[i] }
      }
      for (i, e) in graph.edges.enumerated() {
        let x = e.cell % r.nx + (e.axis == 0 ? 1 : 0)
        let y = e.cell / r.nx + (e.axis == 1 ? 1 : 0)
        let shape = grid.shape(e.axis + 1)
        for k in 0..<r.nz {
          velocities[e.axis][x + shape[0] * (y + shape[1] * k)] =
            half[graph.cells.count + i] / (c.density * c.speed)
        }
      }
      frames.append(
        RigidModeFrame(step: step, p: p, u: velocities[0], v: velocities[1], w: velocities[2]))
      work.append(max(0, e0 - state.reduce(0) { $0 + $1 * $1 } * scale / 2))
      patch.append(max(0, patchIntegral * scale))
    }
    return (RigidModeHistory(spacing: grid.spacing, dt: dt, frames: frames), work, patch)
  }
  /// Least-squares echo amplitude with a bounded independent pulse-template shift fit.
  public static func reflectionFit(
    _ c: TiltedPulseCase, _ r: TiltedPulseResolution, grid: TiltedPulseGrid, p: [Double]
  ) -> (coefficient: Double, shift: Double) {
    let cells = grid.inside.indices.filter {
      grid.inside[$0] == 1 && c.observation(grid.position(0, $0))
    }
    let phases = cells.map { i in
      let x = grid.position(0, i)
      return c.reflectedDirection[0] * x[0] + c.reflectedDirection[1] * x[1] + 2 * c.normal[0]
        * c.normal[0] * c.intercept - c.centre - c.travel
    }
    func fit(_ shift: Double) -> (score: Double, coefficient: Double) {
      var numerator = 0.0
      var denominator = 0.0
      for (j, cell) in cells.enumerated() {
        let shape = c.pulse(phases[j] - shift)
        numerator += p[cell] * shape
        denominator += shape * shape
      }
      return denominator > 0
        ? (numerator * numerator / denominator, numerator / denominator) : (0, 0)
    }
    let limit = c.halfWidth / 2
    let candidates = (0...80).map { -limit + 2 * limit * Double($0) / 80 }
    let best =
      candidates.indices.max { fit(candidates[$0]).score < fit(candidates[$1]).score } ?? 40
    var low = candidates[max(0, best - 1)]
    var high = candidates[min(80, best + 1)]
    for _ in 0..<40 {
      let a = (2 * low + high) / 3
      let b = (low + 2 * high) / 3
      if fit(a).score < fit(b).score { low = a } else { high = b }
    }
    let shift = (low + high) / 2
    return (fit(shift).coefficient, shift)
  }
}
