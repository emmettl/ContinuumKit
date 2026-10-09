import Foundation

public struct CylinderHistory: Codable, Sendable {
  public let fields: RigidModeHistory
  public let inside: [UInt8]
  public let faces: [Float]
  public init(fields: RigidModeHistory, inside: [UInt8], faces: [Float]) {
    self.fields = fields
    self.inside = inside
    self.faces = faces
  }
}

public struct CylinderErrors: Codable, Sendable {
  public let fieldL2: [Double]
  public let maxPressure, maxVelocity, energyBudget, initialEnergyError, boundaryVelocity: Double
  public let inactivePreservationError, geometryVolumeError: Double
}
public struct CylinderResult: Codable, Sendable {
  public let schemaVersion: Int
  public let model, status, reference: String
  public let reason: String?
  public let specification: CylinderCase
  public let resolution: CylinderResolution?
  public let environment: BenchmarkEnvironment
  public let runtime: Double
  public let history: CylinderHistory?
  public let errors: CylinderErrors?
  public static func evaluate(
    model: String, c: CylinderCase, r: CylinderResolution,
    environment: BenchmarkEnvironment, runtime: Double, h: CylinderHistory,
    status: String = "supported"
  ) throws -> Self {
    try c.validate()
    let grid = try CylinderGrid(c, r)
    let expectedFaces = grid.faces
    let raw = h
    let h = raw.fields
    guard raw.inside == grid.inside, raw.faces.count == 6 * grid.labels.count,
      raw.faces.allSatisfy(\.isFinite),
      grid.labels.indices.allSatisfy({ index in
        grid.labels[index] < 0
          || (0..<6).allSatisfy {
            raw.faces[$0 * grid.labels.count + index]
              == expectedFaces[$0 * grid.labels.count + index]
          }
      })
    else { throw BenchmarkFailure.invalidSamples }
    guard r.dimensions.allSatisfy({ $0 >= 2 && $0 <= 128 }), r.steps > 0,
      ["space", "time"].contains(r.axis), runtime.isFinite, runtime >= 0,
      h.spacing.count == 3, h.spacing.allSatisfy({ $0.isFinite && $0 > 0 }),
      h.dt.isFinite, h.dt > 0, abs(h.dt * Double(r.steps) / c.duration - 1) < 1e-6,
      (0..<3).allSatisfy({
        abs(h.spacing[$0] * Double(r.dimensions[$0]) / c.lengths[$0] - 1) < 1e-6
      }),
      h.frames.map(\.step) == r.captures
    else { throw BenchmarkFailure.invalidSamples }
    let oracle = try CylinderOracle.history(c, r, spacing: h.spacing, dt: h.dt)
    var squares = [Double](repeating: 0, count: 4)
    var referenceSquares = squares
    var maxPressure = 0.0
    var maxVelocity = 0.0
    var boundary = 0.0
    var budget = 0.0
    var inactive = 0.0
    var initialEnergy: Double?
    let volume = h.spacing.reduce(1, *)
    for (capture, frame) in h.frames.enumerated() {
      let fields = frame.fields
      let referenceFields = oracle.frames[capture].fields
      for field in 0...3 {
        let dims = grid.fieldDimensions(field)
        guard fields[field].count == dims.reduce(1, *), fields[field].allSatisfy(\.isFinite) else {
          throw BenchmarkFailure.invalidSamples
        }
        for index in fields[field].indices {
          let scale = field == 0 ? 1 / c.amplitude : c.density * c.speed / c.amplitude
          if !grid.openFields[field][index] {
            if field == 0 {
              inactive = max(inactive, abs(fields[field][index] - c.inactivePressure) / c.amplitude)
            } else {
              boundary = max(boundary, abs(fields[field][index]) * scale)
            }
            continue
          }
          let difference = fields[field][index] - referenceFields[field][index]
          squares[field] += difference * difference
          referenceSquares[field] += pow(referenceFields[field][index], 2)
          if field == 0 {
            maxPressure = max(maxPressure, abs(difference) / c.amplitude)
          } else {
            let scale = c.density * c.speed / c.amplitude
            maxVelocity = max(maxVelocity, abs(difference) * scale)
            let xyz = [index % dims[0], index / dims[0] % dims[1], index / (dims[0] * dims[1])]
            if xyz[field - 1] == 0 || xyz[field - 1] == r.dimensions[field - 1] {
              boundary = max(boundary, abs(fields[field][index]) * scale)
            }
          }
        }
      }
      var energy =
        grid.labels.indices.filter { grid.labels[$0] >= 0 }.reduce(0.0) {
          $0 + frame.p[$1] * frame.p[$1]
        } * volume / (2 * c.density * c.speed * c.speed)
      for axis in 0..<3 {
        let dims = grid.fieldDimensions(axis + 1)
        let stride = axis == 0 ? 1 : (axis == 1 ? r.nx : r.nx * r.ny)
        for index in fields[axis + 1].indices where grid.openFields[axis + 1][index] {
          let xyz = [index % dims[0], index / dims[0] % dims[1], index / (dims[0] * dims[1])]
          if xyz[axis] == 0 || xyz[axis] == r.dimensions[axis] { continue }
          let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
          let minusVelocity = fields[axis + 1][index]
          let plusVelocity =
            minusVelocity - h.dt * (frame.p[plus] - frame.p[plus - stride])
            / (c.density * h.spacing[axis])
          energy += c.density * volume * minusVelocity * plusVelocity / 2
        }
      }
      guard energy.isFinite, energy > 0 else { throw BenchmarkFailure.invalidSamples }
      if initialEnergy == nil { initialEnergy = energy }
      budget = max(budget, abs(energy / initialEnergy! - 1))
    }
    guard let e0 = initialEnergy, squares.allSatisfy(\.isFinite),
      referenceSquares.allSatisfy({ $0.isFinite && $0 > 0 })
    else { throw BenchmarkFailure.invalidSamples }
    return Self(
      schemaVersion: 1, model: model, status: status,
      reference: r.axis == "time"
        ? "exact-cylinder-masked-lattice" : "continuum-cylinder-mode",
      reason: nil, specification: c, resolution: r, environment: environment, runtime: runtime,
      history: raw,
      errors: CylinderErrors(
        fieldL2: zip(squares, referenceSquares).map { sqrt($0 / $1) },
        maxPressure: maxPressure, maxVelocity: maxVelocity, energyBudget: budget,
        initialEnergyError: abs(e0 / c.energy - 1), boundaryVelocity: boundary,
        inactivePreservationError: inactive,
        geometryVolumeError: abs(
          Double(grid.labels.filter { $0 >= 0 }.count) * volume / c.volume - 1)))
  }
}
public enum CylinderCommand {
  public static func bounds(_ r: CylinderResult) throws {
    guard let e = r.errors, e.fieldL2.count == 4,
      [
        e.maxPressure, e.maxVelocity, e.energyBudget, e.initialEnergyError, e.boundaryVelocity,
        e.inactivePreservationError, e.geometryVolumeError,
      ]
      .allSatisfy({ $0.isFinite && $0 >= 0 }),
      e.fieldL2.allSatisfy({
        $0.isFinite && $0 >= 0 && $0 < (r.resolution?.axis == "space" ? 0.03 : 0.01)
      }),
      e.maxPressure < (r.resolution?.axis == "space" ? 0.10 : 0.03),
      e.maxVelocity < (r.resolution?.axis == "space" ? 0.10 : 0.03), e.energyBudget < 1e-4,
      e.initialEnergyError < (r.resolution?.axis == "space" ? 0.01 : 0.02),
      e.boundaryVelocity < 1e-6, e.inactivePreservationError < 1e-6,
      e.geometryVolumeError < (r.resolution?.axis == "space" ? 0.005 : 0.02)
    else {
      throw BenchmarkFailure.failedConformance("cylinder field, wall or energy bound failed")
    }
  }
  public static func check(_ series: [CylinderResult]) throws -> [[Double]] {
    if let first = series.first { try first.specification.validate() }
    guard series.count == 3, let first = series.first, let axis = first.resolution?.axis,
      series.allSatisfy({
        $0.status == "supported" && $0.errors?.fieldL2.count == 4
          && ($0.errors?.fieldL2.allSatisfy { $0.isFinite && $0 >= 0 } ?? false)
          && ($0.history?.fields.dt.isFinite ?? false) && ($0.history?.fields.dt ?? 0) > 0
          && $0.specification == first.specification && $0.model == first.model
      }),
      series.compactMap(\.resolution)
        == CylinderResolution.standard(first.specification).filter({ $0.axis == axis })
    else { throw BenchmarkFailure.failedConformance("Incomplete or unsupported cylinder series") }
    var orders: [[Double]] = []
    for field in 0...3 {
      var values: [Double] = []
      for (a, b) in zip(series, series.dropFirst()) {
        let ratio =
          axis == "space"
          ? Double(b.resolution!.nx) / Double(a.resolution!.nx)
          : a.history!.fields.dt / b.history!.fields.dt
        let order = log(a.errors!.fieldL2[field] / b.errors!.fieldL2[field]) / log(ratio)
        guard order.isFinite, axis == "space" || (1.7...2.3).contains(order) else {
          throw BenchmarkFailure.failedConformance(
            "cylinder field \(field) refinement order \(order)")
        }
        values.append(order)
      }
      if axis == "space" {
        let overall =
          log(series[0].errors!.fieldL2[field] / series[2].errors!.fieldL2[field]) / log(4.0)
        guard overall.isFinite, (0.5...2.5).contains(overall) else {
          throw BenchmarkFailure.failedConformance(
            "Cylinder staircase field \(field) overall order \(overall)")
        }
      }
      orders.append(values)
    }
    try bounds(series.last!)
    return orders
  }
  public static func runReference() throws {
    try execute(
      model: "ContinuumKit.cylinder-mode-reference", supported: true, reference: true,
      history: { c, r in
        let grid = try CylinderGrid(c, r)
        return CylinderHistory(
          fields: try CylinderOracle.history(c, r), inside: grid.inside, faces: grid.faces)
      })
  }
  public static func run(
    model: String, supported: Bool,
    history: (CylinderCase, CylinderResolution) throws -> CylinderHistory
  ) throws {
    try execute(model: model, supported: supported, reference: false, history: history)
  }
  private static func execute(
    model: String, supported: Bool, reference: Bool,
    history: (CylinderCase, CylinderResolution) throws -> CylinderHistory
  ) throws {
    func argument(_ key: String) -> String? {
      guard let index = CommandLine.arguments.firstIndex(of: key),
        index + 1 < CommandLine.arguments.count
      else { return nil }
      return CommandLine.arguments[index + 1]
    }
    guard let out = argument("--output"), let metadata = argument("--metadata") else {
      throw BenchmarkFailure.invalidCase
    }
    let env = try JSONDecoder().decode(
      BenchmarkEnvironment.self, from: Data(contentsOf: URL(fileURLWithPath: metadata)))
    let root = URL(fileURLWithPath: out)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let cases = try CylinderCase.standard()
    var results: [CylinderResult] = []
    var conformance: [[String: String]] = []
    var failed = false
    for c in cases {
      if !supported {
        results.append(
          CylinderResult(
            schemaVersion: 1, model: model, status: "unsupported",
            reference: "continuum-cylinder-mode",
            reason: "Production wave solver has no cylinder-domain update",
            specification: c, resolution: nil, environment: env, runtime: 0, history: nil,
            errors: nil))
        conformance.append([
          "case": c.id, "axis": "all", "status": "unsupported",
          "reason": "No production cylinder-domain update",
        ])
        continue
      }
      var series: [CylinderResult] = []
      for r in CylinderResolution.standard(c) {
        do {
          let clock = ContinuousClock()
          let start = clock.now
          let h = try history(c, r)
          let elapsed = start.duration(to: clock.now).components
          series.append(
            try CylinderResult.evaluate(
              model: model, c: c, r: r, environment: env,
              runtime: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, h: h,
              status: reference ? "reference" : "supported"))
        } catch {
          failed = true
          series.append(
            CylinderResult(
              schemaVersion: 1, model: model, status: "failed", reference: "not-evaluated",
              reason: String(describing: error), specification: c, resolution: r, environment: env,
              runtime: 0, history: nil, errors: nil))
        }
      }
      results += series
      for axis in ["space", "time"] {
        do {
          let orders = reference ? [] : try check(series.filter { $0.resolution?.axis == axis })
          conformance.append([
            "case": c.id, "axis": axis, "status": reference ? "reference" : "passed",
            "orders": String(describing: orders),
          ])
          print("\(reference ? "REFERENCE" : "PASS") \(model) \(c.id) \(axis): \(orders)")
        } catch {
          failed = true
          conformance.append([
            "case": c.id, "axis": axis, "status": "failed", "reason": String(describing: error),
          ])
          print("FAIL \(c.id) \(axis): \(error)")
        }
      }
    }
    try encoder.encode(cases).write(to: root.appendingPathComponent("cases.json"))
    try encoder.encode(results).write(to: root.appendingPathComponent("results.json"))
    try encoder.encode(conformance).write(to: root.appendingPathComponent("conformance.json"))
    var csv =
      "model,case,status,axis,nx,ny,nz,steps,pressure_relative_l2,ux_relative_l2,uy_relative_l2,uz_relative_l2,max_pressure_normalized,max_velocity_normalized,energy_budget_normalized,initial_energy_error,boundary_velocity_normalized,inactive_preservation_error,geometry_relative_volume_error,reference,runtime_s\n"
    for result in results {
      let r = result.resolution
      let e = result.errors
      var values = [result.model, result.specification.id, result.status, r?.axis ?? "unsupported"]
      for value in [r?.nx, r?.ny, r?.nz, r?.steps] { values.append(value.map { String($0) } ?? "") }
      for field in 0...3 { values.append(e.map { String($0.fieldL2[field]) } ?? "") }
      for value in [
        e?.maxPressure, e?.maxVelocity, e?.energyBudget, e?.initialEnergyError, e?.boundaryVelocity,
        e?.inactivePreservationError, e?.geometryVolumeError,
      ] {
        values.append(value.map { String($0) } ?? "")
      }
      values += [result.reference, String(result.runtime)]
      csv += values.joined(separator: ",") + "\n"
    }
    try csv.write(to: root.appendingPathComponent("summary.csv"), atomically: true, encoding: .utf8)
    if failed {
      throw BenchmarkFailure.failedConformance("cylinder suite failed; reports retained")
    }
  }
}
