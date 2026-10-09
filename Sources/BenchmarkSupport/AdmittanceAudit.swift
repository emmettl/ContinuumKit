import Foundation

/// Prescribed pressure-load calibration; this is not a continuum transient cylinder solution.
public struct AdmittanceCase: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case alignedBox, cylinder }
  public let version: Int, id: String, kind: Kind
  public let lengths, centre: [Double]
  public let radius, density, speed, amplitude, inactivePressure, impedance: Double
  public init(kind: Kind) {
    version = 1
    self.kind = kind
    id = kind == .cylinder ? "absorbing-cylinder" : "aligned-box-control"
    lengths = [0.25, 0.25, 0.125]
    centre = [0.125, 0.125]
    radius = 0.09375
    density = 1.25
    speed = 320
    amplitude = 1
    inactivePressure = 100
    impedance = 3
  }
  public func validate() throws {
    guard self == Self(kind: kind) else { throw BenchmarkFailure.invalidCase }
  }
  public var sideArea: Double {
    (kind == .cylinder ? 2 * Double.pi * radius : 8 * radius) * lengths[2]
  }
  public var volume: Double {
    (kind == .cylinder ? Double.pi * radius * radius : 4 * radius * radius) * lengths[2]
  }
  public var prescribedPower: Double {
    amplitude * amplitude * sideArea / (density * speed * impedance)
  }
  public static func standard() -> [Self] { [Self(kind: .alignedBox), Self(kind: .cylinder)] }
}
public struct AdmittanceResolution: Codable, Equatable, Sendable {
  public let axis: String, nx, ny, nz: Int, courant: Double
  public init(axis: String, nx: Int, courant: Double) {
    self.axis = axis
    self.nx = nx
    ny = nx
    nz = nx / 2
    self.courant = courant
  }
  public var dimensions: [Int] { [nx, ny, nz] }
  public var steps: Int { 1 }
  public var captures: [Int] { [0, 1] }
  public func dt(_ c: AdmittanceCase) -> Double {
    courant * c.lengths[0] / Double(nx) / (c.speed * sqrt(3))
  }
  public static func standard() -> [Self] {
    [16, 32, 64].map { Self(axis: "space", nx: $0, courant: 0.2) }
      + [0.8, 0.4, 0.2].map { Self(axis: "time", nx: 32, courant: $0) }
  }
}
/// Independent integer occupancy and face connectivity; not produced by an application's mesh code.
public struct AdmittanceGrid: Codable, Sendable {
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
  public init(_ c: AdmittanceCase, _ r: AdmittanceResolution) throws {
    try c.validate()
    guard r.dimensions.allSatisfy({ $0 >= 2 && $0 <= 128 }), r.courant.isFinite, r.courant > 0,
      ["space", "time"].contains(r.axis)
    else { throw BenchmarkFailure.invalidCase }
    dimensions = r.dimensions
    spacing = zip(c.lengths, r.dimensions).map { $0 / Double($1) }
    let cellSpacing = spacing
    labels = (0..<r.dimensions.reduce(1, *)).map { index in
      let x = (Double(index % r.nx) + 0.5) * cellSpacing[0] - c.centre[0]
      let y = (Double(index / r.nx % r.ny) + 0.5) * cellSpacing[1] - c.centre[1]
      return
        (c.kind == .cylinder
        ? x * x + y * y < c.radius * c.radius : abs(x) < c.radius && abs(y) < c.radius) ? 0 : -1
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

public struct AdmittanceHistory: Codable, Sendable {
  public let fields: RigidModeHistory, inside: [UInt8], faces: [Float], layoutFaces: [Float],
    layoutDt: Double, materialImpedance: Double
  public init(
    fields: RigidModeHistory, inside: [UInt8], faces: [Float], layoutFaces: [Float],
    layoutDt: Double, materialImpedance: Double
  ) {
    self.fields = fields
    self.inside = inside
    self.faces = faces
    self.layoutFaces = layoutFaces
    self.layoutDt = layoutDt
    self.materialImpedance = materialImpedance
  }
}
public enum AdmittanceOracle {
  public static func nominalFaces(_ c: AdmittanceCase, _ r: AdmittanceResolution, dt: Double) throws
    -> [Float]
  {
    let grid = try AdmittanceGrid(c, r)
    var faces = grid.faces
    for cell in grid.labels.indices where grid.labels[cell] >= 0 {
      for side in 0..<4 where faces[side * grid.labels.count + cell] == 0 {
        faces[side * grid.labels.count + cell] = Float(
          c.speed * dt / (2 * c.impedance * grid.spacing[side / 2]))
      }
    }
    return faces
  }
  public static func initial(_ c: AdmittanceCase, _ r: AdmittanceResolution) throws
    -> RigidModeFrame
  {
    let grid = try AdmittanceGrid(c, r)
    return RigidModeFrame(
      step: 0, p: grid.labels.map { $0 >= 0 ? c.amplitude : c.inactivePressure },
      u: [Double](repeating: 0, count: grid.fieldDimensions(1).reduce(1, *)),
      v: [Double](repeating: 0, count: grid.fieldDimensions(2).reduce(1, *)),
      w: [Double](repeating: 0, count: grid.fieldDimensions(3).reduce(1, *)))
  }
  /// Exponential pressure decay for the isolated post-velocity wall substep, dp/dt = -lambda p.
  public static func rates(_ grid: AdmittanceGrid, faces: [Float], dt: Double) throws -> [Double] {
    guard faces.count == 6 * grid.labels.count, dt.isFinite, dt > 0 else {
      throw BenchmarkFailure.invalidSamples
    }
    return grid.labels.indices.map { cell in
      guard grid.labels[cell] >= 0 else { return 0 }
      return 2 * (0..<6).reduce(0.0) { $0 + max(0, Double(faces[$1 * grid.labels.count + cell])) }
        / dt
    }
  }
  public static func reference(_ c: AdmittanceCase, _ r: AdmittanceResolution) throws
    -> AdmittanceHistory
  {
    let grid = try AdmittanceGrid(c, r)
    let dt = r.dt(c)
    let faces = try nominalFaces(c, r, dt: dt)
    let initial = try initial(c, r)
    let rates = try rates(grid, faces: faces, dt: dt)
    let final = RigidModeFrame(
      step: 1,
      p: initial.p.indices.map {
        grid.labels[$0] >= 0 ? initial.p[$0] * exp(-rates[$0] * dt) : initial.p[$0]
      }, u: initial.u, v: initial.v, w: initial.w)
    return AdmittanceHistory(
      fields: RigidModeHistory(spacing: grid.spacing, dt: dt, frames: [initial, final]),
      inside: grid.inside, faces: faces, layoutFaces: faces, layoutDt: dt,
      materialImpedance: c.impedance)
  }
}
public struct AdmittanceErrors: Codable, Sendable {
  public let rateL2, maxRateRelative, pressureStepL2, energyBudget, workRelative, zeroVelocity,
    inactivePreservation, initialPressureError: Double
  public let effectiveArea, physicalArea, areaRelativeError, effectivePrescribedPower,
    physicalPrescribedPower, energyLossJ, midpointWallWorkJ: Double
}
public struct AdmittanceResult: Codable, Sendable {
  public let schemaVersion: Int, model: String, status: String, numericalStatus: String,
    physicalStatus: String, reason: String?
  public let specification: AdmittanceCase, resolution: AdmittanceResolution?,
    environment: BenchmarkEnvironment, history: AdmittanceHistory?, errors: AdmittanceErrors?,
    runtime: Double
  public static func evaluate(
    model: String, c: AdmittanceCase, r: AdmittanceResolution, environment: BenchmarkEnvironment,
    h: AdmittanceHistory, runtime: Double, reference: Bool = false
  ) throws -> Self {
    let grid = try AdmittanceGrid(c, r)
    let count = grid.labels.count
    let nominal = grid.faces
    let dt = h.fields.dt
    guard runtime.isFinite, runtime >= 0, h.inside == grid.inside, h.faces.count == 6 * count,
      h.layoutFaces.count == 6 * count, h.layoutDt.isFinite, h.layoutDt > 0,
      h.materialImpedance.isFinite, abs(h.materialImpedance / c.impedance - 1) < 1e-6, dt.isFinite,
      dt > 0, abs(dt / r.dt(c) - 1) < 1e-6, h.fields.spacing.count == 3,
      (0..<3).allSatisfy({ abs(h.fields.spacing[$0] / grid.spacing[$0] - 1) < 1e-6 }),
      h.fields.frames.map(\.step) == [0, 1], h.faces.allSatisfy(\.isFinite),
      h.layoutFaces.allSatisfy(\.isFinite)
    else { throw BenchmarkFailure.invalidSamples }
    var effectiveArea = 0.0
    for cell in grid.labels.indices where grid.labels[cell] >= 0 {
      for side in 0..<6 {
        let index = side * count + cell
        let raw = Double(h.layoutFaces[index])
        let scaled = Double(h.faces[index])
        if nominal[index] < 0 {
          guard raw == -1, scaled == -1 else { throw BenchmarkFailure.invalidSamples }
        } else if side >= 4 {
          guard raw == 0, scaled == 0 else { throw BenchmarkFailure.invalidSamples }
        } else {
          let beta = c.speed * h.layoutDt / (2 * c.impedance * grid.spacing[side / 2])
          guard raw >= 0, raw <= beta * (1 + 1e-6),
            abs(scaled - raw * dt / h.layoutDt) < max(1e-12, abs(scaled) * 2e-6)
          else { throw BenchmarkFailure.invalidSamples }
          effectiveArea +=
            2 * raw * grid.spacing.reduce(1, *) * c.impedance / (c.speed * h.layoutDt)
        }
      }
    }
    let first = h.fields.frames[0]
    let last = h.fields.frames[1]
    var inactive = 0.0
    var zeroVelocity = 0.0
    var initialError = 0.0
    for frame in h.fields.frames {
      for field in 0...3 {
        guard frame.fields[field].count == grid.fieldDimensions(field).reduce(1, *),
          frame.fields[field].allSatisfy(\.isFinite)
        else { throw BenchmarkFailure.invalidSamples }
        for index in frame.fields[field].indices {
          if field > 0 {
            zeroVelocity = max(
              zeroVelocity, abs(frame.fields[field][index]) * c.density * c.speed / c.amplitude)
          } else if grid.labels[index] < 0 {
            inactive = max(inactive, abs(frame.p[index] - c.inactivePressure) / c.amplitude)
          }
        }
      }
    }
    let rates = try AdmittanceOracle.rates(grid, faces: h.faces, dt: dt)
    let energyScale = grid.spacing.reduce(1, *) / (2 * c.density * c.speed * c.speed)
    var rateError = 0.0
    var rateReference = 0.0
    var maxRate = 0.0
    var pError = 0.0
    var pReference = 0.0
    var e0 = 0.0
    var e1 = 0.0
    var work = 0.0
    for cell in grid.labels.indices where grid.labels[cell] >= 0 {
      let p0 = first.p[cell]
      let p1 = last.p[cell]
      let rate = rates[cell]
      guard p0 > 0, p1 > 0 else { throw BenchmarkFailure.invalidSamples }
      initialError = max(initialError, abs(p0 / c.amplitude - 1))
      let exact = p0 * exp(-rate * dt)
      pError += pow(p1 - exact, 2)
      pReference += exact * exact
      if rate > 0 {
        let observed = -log(p1 / p0) / dt
        rateError += pow(observed - rate, 2)
        rateReference += rate * rate
        maxRate = max(maxRate, abs(observed / rate - 1))
      }
      e0 += p0 * p0 * energyScale
      e1 += p1 * p1 * energyScale
      work += rate * dt * pow((p0 + p1) / 2, 2) * 2 * energyScale
    }
    guard rateReference > 0, pReference > 0, e0 > 0, work > 0 else {
      throw BenchmarkFailure.invalidSamples
    }
    let errors = AdmittanceErrors(
      rateL2: sqrt(rateError / rateReference), maxRateRelative: maxRate,
      pressureStepL2: sqrt(pError / pReference), energyBudget: abs(e1 + work - e0) / e0,
      workRelative: abs(e0 - e1 - work) / work, zeroVelocity: zeroVelocity,
      inactivePreservation: inactive, initialPressureError: initialError,
      effectiveArea: effectiveArea, physicalArea: c.sideArea,
      areaRelativeError: abs(effectiveArea / c.sideArea - 1),
      effectivePrescribedPower: c.amplitude * c.amplitude * effectiveArea
        / (c.density * c.speed * c.impedance), physicalPrescribedPower: c.prescribedPower,
      energyLossJ: e0 - e1, midpointWallWorkJ: work)
    let physical = errors.areaRelativeError < 0.005 ? "passed" : "gap"
    var numerical = "passed"
    if !reference {
      if !(errors.energyBudget < 1e-5 && errors.workRelative < 5e-5 && zeroVelocity < 1e-6
        && inactive < 1e-6 && initialError < 1e-6)
      {
        numerical = "failed"
      }
    }
    return Self(
      schemaVersion: 1, model: model,
      status: reference
        ? "reference" : numerical == "failed" ? "failed" : physical == "gap" ? "gap" : "supported",
      numericalStatus: reference ? "reference" : numerical, physicalStatus: physical,
      reason: physical == "gap"
        ? "Effective wall admittance fails physical side-area tolerance; geometry conformance is not established"
        : nil, specification: c, resolution: r, environment: environment, history: h,
      errors: errors, runtime: runtime)
  }
}
