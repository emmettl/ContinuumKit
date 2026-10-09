import Foundation

public struct AbsorbingCylinderHistory: Codable, Sendable {
  public let fields: RigidModeHistory, inside: [UInt8], faces: [Float], layoutFaces: [Float]
  public let layoutDt, materialImpedance: Double
  /// All source wall-cell pressures in Pa at every complete pressure step; references omit this trace.
  public let wallCells: [Int], wallPressures: [[Double]]?
  public let dissipation: [Double]
  public init(
    fields: RigidModeHistory, inside: [UInt8], faces: [Float], layoutFaces: [Float],
    layoutDt: Double, materialImpedance: Double, wallCells: [Int], wallPressures: [[Double]]?,
    dissipation: [Double]
  ) {
    self.fields = fields
    self.inside = inside
    self.faces = faces
    self.layoutFaces = layoutFaces
    self.layoutDt = layoutDt
    self.materialImpedance = materialImpedance
    self.wallCells = wallCells
    self.wallPressures = wallPressures
    self.dissipation = dissipation
  }
}
public struct AbsorbingCylinderErrors: Codable, Sendable {
  public let fieldL2: [Double]
  public let maxPressure, maxVelocity, energyBudget, workError, initialEnergyError,
    initialStateError: Double
  public let boundaryVelocity, inactivePreservation, geometryVolumeError, areaRelativeError,
    localWeightError: Double
  public let finalDissipationJ, referenceDissipationJ: Double
}
public struct AbsorbingCylinderResult: Codable, Sendable {
  public let schemaVersion: Int, model: String, status: String, reference: String, reason: String?
  public let specification: AbsorbingCylinderCase, resolution: CylinderResolution?,
    environment: BenchmarkEnvironment
  public let runtime: Double, history: AbsorbingCylinderHistory?, errors: AbsorbingCylinderErrors?
  public static func evaluate(
    model: String, c: AbsorbingCylinderCase, r: CylinderResolution,
    environment: BenchmarkEnvironment, h: AbsorbingCylinderHistory, runtime: Double,
    reference: Bool = false
  ) throws -> Self {
    try c.validate()
    let g = c.geometry
    let grid = try CylinderGrid(g, r)
    let ref = try AbsorbingCylinderReference(c)
    let count = grid.labels.count
    let dt = h.fields.dt
    guard runtime.isFinite, runtime >= 0, h.inside == grid.inside, h.faces.count == 6 * count,
      h.layoutFaces.count == 6 * count,
      h.faces.allSatisfy(\.isFinite), h.layoutFaces.allSatisfy(\.isFinite), h.layoutDt.isFinite,
      h.layoutDt > 0,
      h.materialImpedance.isFinite, abs(h.materialImpedance / c.impedance - 1) < 1e-6,
      dt.isFinite, dt > 0, abs(dt * Double(r.steps) / ref.duration - 1) < 1e-6,
      h.fields.spacing.count == 3,
      (0..<3).allSatisfy({ abs(h.fields.spacing[$0] / grid.spacing[$0] - 1) < 1e-6 }),
      h.fields.frames.map(\.step) == r.captures,
      h.wallCells == AbsorbingCylinderOracle.wallCells(grid),
      h.dissipation.count == r.captures.count,
      h.dissipation.allSatisfy({ $0.isFinite && $0 >= 0 }), h.dissipation.first == 0,
      zip(h.dissipation.dropFirst(), h.dissipation).allSatisfy({ $0 + 1e-18 >= $1 })
    else { throw BenchmarkFailure.invalidSamples }
    let rigid = grid.faces
    let ideal = try AbsorbingCylinderOracle.faces(c, r, dt: h.layoutDt)
    let volume = grid.spacing.reduce(1, *)
    var area = 0.0
    var weightError = 0.0
    for cell in grid.labels.indices where grid.labels[cell] >= 0 {
      for side in 0..<6 {
        let index = side * count + cell
        let raw = Double(h.layoutFaces[index])
        let scaled = Double(h.faces[index])
        if rigid[index] < 0 {
          guard raw == -1 && scaled == -1 else { throw BenchmarkFailure.invalidSamples }
        } else if side >= 4 {
          guard raw == 0 && scaled == 0 else { throw BenchmarkFailure.invalidSamples }
        } else {
          let full = g.speed * h.layoutDt / (2 * c.impedance * grid.spacing[side / 2])
          guard raw > 0, raw <= full * (1 + 1e-6),
            abs(scaled - raw * dt / h.layoutDt) < max(1e-12, abs(scaled) * 2e-6)
          else { throw BenchmarkFailure.invalidSamples }
          weightError = max(weightError, abs(raw / Double(ideal[index]) - 1))
          area += 2 * raw * volume * c.impedance / (g.speed * h.layoutDt)
        }
      }
    }
    guard
      h.fields.frames.allSatisfy({ frame in
        (0...3).allSatisfy { field in
          frame.fields[field].count == grid.fieldDimensions(field).reduce(1, *)
            && frame.fields[field].allSatisfy(\.isFinite)
        }
      })
    else { throw BenchmarkFailure.invalidSamples }
    let expected = try AbsorbingCylinderOracle.history(c, r, faces: h.faces, dt: dt)
    let initial = try AbsorbingCylinderOracle.initial(c, r, dt: dt)
    let rates = try AbsorbingCylinderOracle.rates(grid, faces: h.faces, dt: dt)
    if !reference {
      guard let trace = h.wallPressures, trace.count == r.steps + 1,
        trace.allSatisfy({ $0.count == h.wallCells.count && $0.allSatisfy(\.isFinite) })
      else { throw BenchmarkFailure.invalidSamples }
      var work = 0.0
      var capture = 0
      for step in 0...r.steps {
        if step > 0 {
          for (i, cell) in h.wallCells.enumerated() {
            work +=
              dt * volume * rates[cell] * pow((trace[step - 1][i] + trace[step][i]) / 2, 2)
              / (g.density * g.speed * g.speed)
          }
        }
        if r.captures[capture] == step {
          guard abs(h.dissipation[capture] - work) / ref.energy(time: 0) < 1e-9 else {
            throw BenchmarkFailure.invalidSamples
          }
          for (i, cell) in h.wallCells.enumerated() {
            guard abs(trace[step][i] - h.fields.frames[capture].p[cell]) / g.amplitude < 1e-6 else {
              throw BenchmarkFailure.invalidSamples
            }
          }
          if capture + 1 < r.captures.count { capture += 1 }
        }
      }
    } else {
      guard h.wallPressures == nil else { throw BenchmarkFailure.invalidSamples }
    }
    var squares = [Double](repeating: 0, count: 4)
    var norms = squares
    var maxP = 0.0
    var maxV = 0.0
    var boundary = 0.0
    var inactive = 0.0
    var budget = 0.0
    var workError = 0.0
    var initialError = 0.0
    var initialEnergy: Double?
    for (capture, frame) in h.fields.frames.enumerated() {
      for field in 0...3 {
        guard frame.fields[field].count == grid.fieldDimensions(field).reduce(1, *),
          frame.fields[field].allSatisfy(\.isFinite)
        else { throw BenchmarkFailure.invalidSamples }
        let scale = field == 0 ? 1 / g.amplitude : g.density * g.speed / g.amplitude
        for index in frame.fields[field].indices {
          let value = frame.fields[field][index]
          if !grid.openFields[field][index] {
            if field == 0 {
              inactive = max(inactive, abs(value - g.inactivePressure) / g.amplitude)
            } else {
              boundary = max(boundary, abs(value) * scale)
            }
            continue
          }
          let truth = expected.fields.frames[capture].fields[field][index]
          let delta = value - truth
          squares[field] += delta * delta
          norms[field] += truth * truth
          if field == 0 {
            maxP = max(maxP, abs(delta) * scale)
          } else {
            maxV = max(maxV, abs(delta) * scale)
          }
          if capture == 0 {
            initialError = max(initialError, abs(value - initial.fields[field][index]) * scale)
          }
        }
      }
      // The modified staggered energy has the exact midpoint wall-work identity.
      var energy =
        grid.labels.indices.filter { grid.labels[$0] >= 0 }.reduce(0.0) {
          $0 + frame.p[$1] * frame.p[$1]
        } * volume / (2 * g.density * g.speed * g.speed)
      for axis in 0..<3 {
        let shape = grid.fieldDimensions(axis + 1)
        let stride = [1, r.nx, r.nx * r.ny][axis]
        for index in frame.fields[axis + 1].indices where grid.openFields[axis + 1][index] {
          let xyz = grid.coordinates(index, shape: shape)
          let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
          let minus = frame.fields[axis + 1][index]
          let next =
            minus - dt * (frame.p[plus] - frame.p[plus - stride]) / (g.density * grid.spacing[axis])
          energy += g.density * volume * minus * next / 2
        }
      }
      guard energy.isFinite, energy > 0 else { throw BenchmarkFailure.invalidSamples }
      if initialEnergy == nil { initialEnergy = energy }
      budget = max(budget, abs(energy + h.dissipation[capture] - initialEnergy!) / initialEnergy!)
      workError = max(
        workError, abs(h.dissipation[capture] - expected.work[capture]) / ref.energy(time: 0))
    }
    guard let e0 = initialEnergy, norms.allSatisfy({ $0.isFinite && $0 > 0 }),
      squares.allSatisfy(\.isFinite)
    else { throw BenchmarkFailure.invalidSamples }
    return Self(
      schemaVersion: 1, model: model, status: reference ? "reference" : "supported",
      reference: r.axis == "time"
        ? "continuous-damped-masked-graph" : "continuum-robin-bessel-mode", reason: nil,
      specification: c, resolution: r, environment: environment, runtime: runtime, history: h,
      errors: AbsorbingCylinderErrors(
        fieldL2: zip(squares, norms).map { sqrt($0 / $1) }, maxPressure: maxP, maxVelocity: maxV,
        energyBudget: budget, workError: workError,
        initialEnergyError: abs(e0 / ref.energy(time: 0) - 1), initialStateError: initialError,
        boundaryVelocity: boundary, inactivePreservation: inactive,
        geometryVolumeError: abs(
          Double(grid.labels.filter { $0 >= 0 }.count) * volume / g.volume - 1),
        areaRelativeError: abs(area / (2 * Double.pi * g.radius * g.lengths[2]) - 1),
        localWeightError: weightError,
        finalDissipationJ: h.dissipation.last!, referenceDissipationJ: expected.work.last!))
  }
}
public enum AbsorbingCylinderCommand {
  public static func bounds(_ r: AbsorbingCylinderResult) throws {
    guard let e = r.errors, e.fieldL2.count == 4, let axis = r.resolution?.axis,
      e.fieldL2.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < (axis == "space" ? 0.05 : 0.01) }),
      [
        e.maxPressure, e.maxVelocity, e.energyBudget, e.workError, e.initialEnergyError,
        e.initialStateError, e.boundaryVelocity, e.inactivePreservation, e.geometryVolumeError,
        e.areaRelativeError, e.localWeightError, e.finalDissipationJ, e.referenceDissipationJ,
      ].allSatisfy({ $0.isFinite && $0 >= 0 }),
      e.maxPressure < (axis == "space" ? 0.10 : 0.03),
      e.maxVelocity < (axis == "space" ? 0.10 : 0.03), e.energyBudget < 1e-4,
      e.workError < (axis == "space" ? 0.03 : 0.002),
      e.initialEnergyError < (axis == "space" ? 0.03 : 0.06), e.initialStateError < 1e-6,
      e.boundaryVelocity < 1e-6, e.inactivePreservation < 1e-6,
      e.geometryVolumeError < (axis == "space" ? 0.005 : 0.02),
      e.areaRelativeError < 0.005, e.localWeightError < 0.01, e.finalDissipationJ > 0
    else {
      throw BenchmarkFailure.failedConformance(
        "absorbing cylinder finest-grid accuracy, geometry or work gate failed")
    }
  }
  public static func check(_ series: [AbsorbingCylinderResult]) throws -> [[Double]] {
    guard series.count == 3, let last = series.last, let axis = last.resolution?.axis,
      series.allSatisfy({
        $0.status == "supported" && $0.resolution?.axis == axis
          && $0.specification == last.specification
      }),
      series.allSatisfy({ $0.errors?.fieldL2.count == 4 }),
      series.allSatisfy({
        ($0.errors?.energyBudget ?? .infinity) < 1e-4
          && ($0.errors?.inactivePreservation ?? .infinity) < 1e-6
          && ($0.errors?.boundaryVelocity ?? .infinity) < 1e-6
          && ($0.errors?.initialStateError ?? .infinity) < 1e-6
      })
    else { throw BenchmarkFailure.invalidSamples }
    try bounds(last)
    var orders: [[Double]] = []
    for field in 0...3 {
      let errors = series.map { $0.errors!.fieldL2[field] }
      guard errors.allSatisfy({ $0.isFinite && $0 > 0 }) else {
        throw BenchmarkFailure.invalidSamples
      }
      if axis == "space" {
        let order =
          log(errors[0] / errors[2])
          / log(Double(series[2].resolution!.nx) / Double(series[0].resolution!.nx))
        guard (0.5...2.5).contains(order) else {
          throw BenchmarkFailure.failedConformance(
            "absorbing cylinder spatial field does not refine")
        }
      }
      let row = (0..<2).map { i in
        log(errors[i] / errors[i + 1])
          / log(
            axis == "space"
              ? Double(series[i + 1].resolution!.nx) / Double(series[i].resolution!.nx)
              : series[i].history!.fields.dt / series[i + 1].history!.fields.dt)
      }
      if axis == "time" {
        guard row.allSatisfy({ (1.7...2.3).contains($0) }) else {
          throw BenchmarkFailure.failedConformance(
            "absorbing cylinder temporal field is not second order")
        }
      }
      orders.append(row)
    }
    return orders
  }
  public static func runReference() throws {
    try run(model: "ContinuumKit.absorbing-cylinder-reference", supported: true, reference: true) {
      c, r in
      let ref = try AbsorbingCylinderReference(c)
      let dt = ref.duration / Double(r.steps)
      let grid = try CylinderGrid(c.geometry, r)
      let faces = try AbsorbingCylinderOracle.faces(c, r, dt: dt)
      let h = try AbsorbingCylinderOracle.history(c, r, faces: faces, dt: dt)
      return AbsorbingCylinderHistory(
        fields: h.fields, inside: grid.inside, faces: faces, layoutFaces: faces, layoutDt: dt,
        materialImpedance: c.impedance, wallCells: AbsorbingCylinderOracle.wallCells(grid),
        wallPressures: nil, dissipation: h.work)
    }
  }
  public static func run(
    model: String, supported: Bool, reference: Bool = false,
    history: (AbsorbingCylinderCase, CylinderResolution) throws -> AbsorbingCylinderHistory
  ) throws {
    let args = CommandLine.arguments
    guard let at = args.firstIndex(of: "--output"), at + 1 < args.count else {
      throw BenchmarkFailure.invalidCase
    }
    let root = URL(fileURLWithPath: args[at + 1])
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    guard let meta = args.firstIndex(of: "--metadata"), meta + 1 < args.count else {
      throw BenchmarkFailure.invalidCase
    }
    let env = try JSONDecoder().decode(
      BenchmarkEnvironment.self, from: Data(contentsOf: URL(fileURLWithPath: args[meta + 1])))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let cases = AbsorbingCylinderCase.standard()
    var results: [AbsorbingCylinderResult] = []
    var reports: [[String: String]] = []
    var failed = false
    for c in cases {
      if !supported {
        results.append(
          AbsorbingCylinderResult(
            schemaVersion: 1, model: model, status: "unsupported",
            reference: "continuum-robin-bessel-mode",
            reason: "Production solver has no absorbing masked cylinder update", specification: c,
            resolution: nil, environment: env, runtime: 0, history: nil, errors: nil))
        reports.append([
          "case": c.id, "axis": "all", "status": "unsupported",
          "reason": "No absorbing masked cylinder update",
        ])
        continue
      }
      var series: [AbsorbingCylinderResult] = []
      for r in try AbsorbingCylinderOracle.resolutions(c) {
        do {
          let clock = ContinuousClock()
          let start = clock.now
          let h = try history(c, r)
          let elapsed = start.duration(to: clock.now).components
          series.append(
            try AbsorbingCylinderResult.evaluate(
              model: model, c: c, r: r, environment: env, h: h,
              runtime: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
              reference: reference))
        } catch {
          failed = true
          series.append(
            AbsorbingCylinderResult(
              schemaVersion: 1, model: model, status: "failed", reference: "not-evaluated",
              reason: String(describing: error), specification: c, resolution: r, environment: env,
              runtime: 0, history: nil, errors: nil))
        }
      }
      results += series
      for axis in ["space", "time"] {
        do {
          let orders = reference ? [] : try check(series.filter { $0.resolution?.axis == axis })
          reports.append([
            "case": c.id, "axis": axis, "status": reference ? "reference" : "passed",
            "orders": String(describing: orders),
          ])
          print("\(reference ? "REFERENCE":"PASS") \(c.id) \(axis): \(orders)")
        } catch {
          failed = true
          reports.append([
            "case": c.id, "axis": axis, "status": "failed", "reason": String(describing: error),
          ])
          print("FAIL \(c.id) \(axis): \(error)")
        }
      }
    }
    try encoder.encode(cases).write(to: root.appendingPathComponent("cases.json"))
    try encoder.encode(results).write(to: root.appendingPathComponent("results.json"))
    try encoder.encode(reports).write(to: root.appendingPathComponent("conformance.json"))
    var csv =
      "model,case,status,axis,nx,steps,pressure_relative_l2,ux_relative_l2,uy_relative_l2,uz_relative_l2,energy_budget,work_error,area_error,reference,runtime_s\n"
    for r in results {
      var values = [
        r.model, r.specification.id, r.status, r.resolution?.axis ?? "unsupported",
        r.resolution.map { String($0.nx) } ?? "", r.resolution.map { String($0.steps) } ?? "",
      ]
      values += (0...3).map { i in r.errors.map { String($0.fieldL2[i]) } ?? "" }
      values += [
        r.errors.map { String($0.energyBudget) } ?? "", r.errors.map { String($0.workError) } ?? "",
        r.errors.map { String($0.areaRelativeError) } ?? "", r.reference, String(r.runtime),
      ]
      csv += values.joined(separator: ",") + "\n"
    }
    try csv.write(to: root.appendingPathComponent("summary.csv"), atomically: true, encoding: .utf8)
    if failed {
      throw BenchmarkFailure.failedConformance(
        "absorbing cylinder suite failed; complete reports retained")
    }
  }
}
