import Foundation

public struct ObliqueModeParameters: Codable, Sendable {
  public let kx, rate, reflection: ObliqueComplex
  public let ky, normalization, duration, initialEnergy: Double
}
public struct ObliqueModeErrors: Codable, Sendable {
  public let fieldL2: [Double]
  public let maxPressure, maxVelocity, energyBudget, initialEnergyError, boundaryVelocity,
    dissipationError: Double
  public let fittedReflection: ObliqueComplex
  public let reflectionError, fitResidual: Double
}
public struct ObliqueModeResult: Codable, Sendable {
  public let schemaVersion: Int
  public let model, status, reference: String
  public let reason: String?
  public let specification: ObliqueModeCase
  public let parameters: ObliqueModeParameters
  public let resolution: ObliqueModeResolution?
  public let environment: BenchmarkEnvironment
  public let runtime: Double
  public let history: BoundaryHistory?
  public let errors: ObliqueModeErrors?
  public static func evaluate(
    model: String, c: ObliqueModeCase, r: ObliqueModeResolution,
    environment: BenchmarkEnvironment, runtime: Double, h: BoundaryHistory,
    status: String = "supported"
  ) throws -> Self {
    let ref = try ObliqueModeReference(c)
    guard r.nx >= 2, r.nx <= 512, r.ny >= 2, r.ny <= 256, r.steps > 0,
      ["space", "time"].contains(r.axis),
      runtime.isFinite, runtime >= 0, [h.dx, h.dy, h.dt].allSatisfy({ $0.isFinite && $0 > 0 }),
      abs(h.dx * Double(r.nx) / c.lengthX - 1) < 1e-6,
      abs(h.dy * Double(r.ny) / c.lengthY - 1) < 1e-6,
      abs(h.dt * Double(r.steps) / ref.duration - 1) < 1e-6, h.frames.map(\.step) == r.captures
    else { throw BenchmarkFailure.invalidSamples }
    let oracle = try ObliqueModeOracle.history(c, r, dx: h.dx, dy: h.dy, dt: h.dt)
    var squared = [Double](repeating: 0, count: 3)
    var referenceSquared = squared
    var maxP = 0.0
    var maxU = 0.0
    var budget = 0.0
    var boundary = 0.0
    var lossError = 0.0
    var lastLoss = 0.0
    var initial: Double?
    for (capture, f) in h.frames.enumerated() {
      let fields = [f.p, f.u, f.v]
      let references = [
        oracle.frames[capture].p, oracle.frames[capture].u, oracle.frames[capture].v,
      ]
      guard f.p.count == r.nx * r.ny, f.u.count == (r.nx + 1) * r.ny,
        f.v.count == r.nx * (r.ny + 1),
        fields.allSatisfy({ $0.allSatisfy(\.isFinite) }), f.dissipation.isFinite,
        f.dissipation >= lastLoss
      else { throw BenchmarkFailure.invalidSamples }
      lastLoss = f.dissipation
      for field in 0...2 {
        for i in fields[field].indices {
          let difference = fields[field][i] - references[field][i]
          squared[field] += difference * difference
          referenceSquared[field] += references[field][i] * references[field][i]
          if field == 0 {
            maxP = max(maxP, abs(difference) / c.amplitude)
          } else {
            maxU = max(maxU, abs(difference) * c.density * c.speed / c.amplitude)
          }
        }
      }
      for j in 0..<r.ny {
        boundary = max(boundary, abs(f.u[j * (r.nx + 1)]) * c.density * c.speed / c.amplitude)
      }
      for i in 0..<r.nx {
        boundary = max(
          boundary, max(abs(f.v[i]), abs(f.v[r.nx * r.ny + i])) * c.density * c.speed / c.amplitude)
      }
      var energy =
        f.p.reduce(0) { $0 + $1 * $1 } * h.dx * h.dy / (2 * c.density * c.speed * c.speed)
      for j in 0..<r.ny {
        for i in 1..<r.nx {
          let u = f.u[j * (r.nx + 1) + i]
          let plus = u - h.dt * (f.p[j * r.nx + i] - f.p[j * r.nx + i - 1]) / (c.density * h.dx)
          energy += c.density * h.dx * h.dy * u * plus / 2
        }
      }
      for j in 1..<r.ny {
        for i in 0..<r.nx {
          let v = f.v[j * r.nx + i]
          let plus = v - h.dt * (f.p[j * r.nx + i] - f.p[(j - 1) * r.nx + i]) / (c.density * h.dy)
          energy += c.density * h.dx * h.dy * v * plus / 2
        }
      }
      guard energy.isFinite, energy > 0 else { throw BenchmarkFailure.invalidSamples }
      if initial == nil { initial = energy }
      budget = max(budget, abs((energy + f.dissipation) / initial! - 1))
      lossError = max(
        lossError, abs(f.dissipation - oracle.frames[capture].dissipation) / ref.energy(time: 0))
    }
    guard referenceSquared.allSatisfy({ $0.isFinite && $0 > 0 }), squared.allSatisfy(\.isFinite),
      let e0 = initial
    else { throw BenchmarkFailure.invalidSamples }
    let fit = try fitReflection(ref, r, h)
    return Self(
      schemaVersion: 1, model: model, status: status,
      reference: r.axis == "time"
        ? "fixed-spatial-oblique-matrix-exponential" : "continuum-damped-oblique-mode", reason: nil,
      specification: c, parameters: parameters(ref), resolution: r, environment: environment,
      runtime: runtime, history: h,
      errors: ObliqueModeErrors(
        fieldL2: zip(squared, referenceSquared).map { sqrt($0 / $1) },
        maxPressure: maxP, maxVelocity: maxU, energyBudget: budget,
        initialEnergyError: abs(e0 / ref.energy(time: 0) - 1),
        boundaryVelocity: boundary, dissipationError: lossError, fittedReflection: fit.value,
        reflectionError: (fit.value - ref.reflection).magnitude, fitResidual: fit.residual))
  }
  static func parameters(_ ref: ObliqueModeReference) -> ObliqueModeParameters {
    ObliqueModeParameters(
      kx: ref.kx, rate: ref.rate, reflection: ref.reflection, ky: ref.ky,
      normalization: ref.normalization, duration: ref.duration, initialEnergy: ref.energy(time: 0))
  }
  /// Fit independent incident/reflected complex amplitudes from the complete pressure history.
  /// This does not infer reflection from the already imposed boundary p/u ratio.
  static func fitReflection(
    _ ref: ObliqueModeReference, _ r: ObliqueModeResolution, _ h: BoundaryHistory
  ) throws -> (value: ObliqueComplex, residual: Double) {
    var matrix = Array(repeating: Array(repeating: 0.0, count: 5), count: 4)
    let weights = (0..<r.ny).map { cos(ref.ky * (Double($0) + 0.5) * h.dy) }
    let denominator = weights.reduce(0) { $0 + $1 * $1 }
    var rows: [[Double]] = []
    var targets: [Double] = []
    for frame in h.frames {
      for i in 0..<r.nx {
        var target = 0.0
        for j in 0..<r.ny { target += frame.p[j * r.nx + i] * weights[j] / denominator }
        let x = (Double(i) + 0.5) * h.dx - ref.specification.lengthX
        let t = Double(frame.step) * h.dt
        let a = (ObliqueComplex.i * ref.kx * ObliqueComplex(x) + ref.rate * ObliqueComplex(t)).exp
        let b = (-ObliqueComplex.i * ref.kx * ObliqueComplex(x) + ref.rate * ObliqueComplex(t)).exp
        let basis = [a.real, -a.imag, b.real, -b.imag]
        for j in 0..<4 {
          for k in 0..<4 { matrix[j][k] += basis[j] * basis[k] }
          matrix[j][4] += basis[j] * target
        }
        rows.append(basis)
        targets.append(target)
      }
    }
    let scale = matrix.flatMap { $0 }.map(abs).max()!
    for col in 0..<4 {
      let pivot = (col..<4).max(by: { abs(matrix[$0][col]) < abs(matrix[$1][col]) })!
      guard abs(matrix[pivot][col]) > 1e-13 * scale else { throw BenchmarkFailure.invalidSamples }
      matrix.swapAt(col, pivot)
      let value = matrix[col][col]
      for k in col...4 { matrix[col][k] /= value }
      for j in 0..<4 where j != col {
        let factor = matrix[j][col]
        for k in col...4 { matrix[j][k] -= factor * matrix[col][k] }
      }
    }
    let coefficients = matrix.map { $0[4] }
    let incoming = ObliqueComplex(coefficients[0], coefficients[1])
    let outgoing = ObliqueComplex(coefficients[2], coefficients[3])
    guard incoming.magnitude > 1e-8 else { throw BenchmarkFailure.invalidSamples }
    var residual = 0.0
    var total = 0.0
    for (row, target) in zip(rows, targets) {
      let prediction = zip(row, coefficients).reduce(0) { $0 + $1.0 * $1.1 }
      residual += (prediction - target) * (prediction - target)
      total += target * target
    }
    let value = outgoing / incoming
    guard total > 0, value.real.isFinite, value.imag.isFinite, residual.isFinite else {
      throw BenchmarkFailure.invalidSamples
    }
    return (value, sqrt(residual / total))
  }
}
public enum ObliqueModeCommand {
  public static func bounds(_ result: ObliqueModeResult) throws {
    guard let e = result.errors, e.fieldL2.count == 3,
      e.fieldL2.allSatisfy({ $0.isFinite && $0 >= 0 && $0 < 0.02 }),
      [
        e.maxPressure, e.maxVelocity, e.energyBudget, e.initialEnergyError, e.boundaryVelocity,
        e.dissipationError, e.reflectionError, e.fitResidual,
      ].allSatisfy({ $0.isFinite && $0 >= 0 }),
      e.maxPressure < 0.03, e.maxVelocity < 0.03, e.energyBudget < 1e-4,
      e.initialEnergyError < 0.01, e.boundaryVelocity < 1e-6,
      e.dissipationError < (result.resolution?.axis == "time" ? 1e-3 : 0.02),
      result.resolution?.axis == "time" || (e.reflectionError < 0.02 && e.fitResidual < 0.02)
    else {
      throw BenchmarkFailure.failedConformance(
        "Oblique field, reflection, work or energy bound failed")
    }
  }
  public static func check(_ series: [ObliqueModeResult]) throws -> [[Double]] {
    guard series.count == 3, let first = series.first, let axis = first.resolution?.axis else {
      throw BenchmarkFailure.invalidSamples
    }
    try first.specification.validate()
    guard
      series.allSatisfy({
        $0.status == "supported" && $0.errors?.fieldL2.count == 3
          && $0.specification == first.specification && $0.model == first.model
          && ($0.errors?.fieldL2.allSatisfy { $0.isFinite && $0 >= 0 } ?? false)
          && ($0.history?.dt.isFinite ?? false) && ($0.history?.dt ?? 0) > 0
      }),
      series.compactMap(\.resolution)
        == (try ObliqueModeResolution.standard(first.specification)).filter({ $0.axis == axis })
    else { throw BenchmarkFailure.failedConformance("Incomplete or unsupported oblique series") }
    var orders: [[Double]] = []
    let range = axis == "space" ? 0.8...2.3 : 1.7...2.3
    for metric in 0...3 {
      var pair: [Double] = []
      for (a, b) in zip(series, series.dropFirst()) {
        let ea = metric == 3 ? a.errors!.dissipationError : a.errors!.fieldL2[metric]
        let eb = metric == 3 ? b.errors!.dissipationError : b.errors!.fieldL2[metric]
        let ratio =
          axis == "space"
          ? Double(b.resolution!.nx) / Double(a.resolution!.nx) : a.history!.dt / b.history!.dt
        let order = log(ea / eb) / log(ratio)
        guard order.isFinite, range.contains(order) else {
          throw BenchmarkFailure.failedConformance(
            "Oblique metric \(metric) refinement \(order), expected \(range)")
        }
        pair.append(order)
      }
      orders.append(pair)
    }
    try bounds(series.last!)
    return orders
  }
  public static func runReference() throws {
    try execute(
      model: "ContinuumKit.oblique-reference", supported: true, reference: true,
      history: { c, r in try ObliqueModeOracle.history(c, r) })
  }
  public static func run(
    model: String, supported: Bool,
    history: (ObliqueModeCase, ObliqueModeResolution) throws -> BoundaryHistory
  ) throws {
    try execute(model: model, supported: supported, reference: false, history: history)
  }
  private static func execute(
    model: String, supported: Bool, reference: Bool,
    history: (ObliqueModeCase, ObliqueModeResolution) throws -> BoundaryHistory
  ) throws {
    func argument(_ key: String) -> String? {
      guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count
      else { return nil }
      return CommandLine.arguments[i + 1]
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
    let cases = try ObliqueModeCase.standard()
    var all: [ObliqueModeResult] = []
    var checks: [[String: String]] = []
    var failed = false
    for c in cases {
      let ref = try ObliqueModeReference(c)
      if !supported {
        all.append(
          ObliqueModeResult(
            schemaVersion: 1, model: model, status: "unsupported",
            reference: "continuum-damped-oblique-mode",
            reason: "Production wave solver has rigid walls only", specification: c,
            parameters: ObliqueModeResult.parameters(ref), resolution: nil, environment: env,
            runtime: 0, history: nil, errors: nil))
        checks.append([
          "case": c.id, "axis": "all", "status": "unsupported",
          "reason": "No production impedance law",
        ])
        continue
      }
      var series: [ObliqueModeResult] = []
      for r in try ObliqueModeResolution.standard(c) {
        do {
          let clock = ContinuousClock()
          let start = clock.now
          let h = try history(c, r)
          let elapsed = start.duration(to: clock.now).components
          series.append(
            try ObliqueModeResult.evaluate(
              model: model, c: c, r: r, environment: env,
              runtime: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, h: h,
              status: reference ? "reference" : "supported"))
        } catch {
          failed = true
          series.append(
            ObliqueModeResult(
              schemaVersion: 1, model: model, status: "failed", reference: "not-evaluated",
              reason: String(describing: error), specification: c,
              parameters: ObliqueModeResult.parameters(ref), resolution: r, environment: env,
              runtime: 0, history: nil, errors: nil))
        }
      }
      all += series
      for axis in ["space", "time"] {
        do {
          let orders = reference ? [] : try check(series.filter { $0.resolution?.axis == axis })
          checks.append([
            "case": c.id, "axis": axis, "status": reference ? "reference" : "passed",
            "orders": String(describing: orders),
          ])
          print("\(reference ? "REFERENCE":"PASS") \(model) \(c.id) \(axis): \(orders)")
        } catch {
          failed = true
          checks.append([
            "case": c.id, "axis": axis, "status": "failed", "reason": String(describing: error),
          ])
          print("FAIL \(c.id) \(axis): \(error)")
        }
      }
    }
    try encoder.encode(cases).write(to: root.appendingPathComponent("cases.json"))
    try encoder.encode(all).write(to: root.appendingPathComponent("results.json"))
    try encoder.encode(checks).write(to: root.appendingPathComponent("conformance.json"))
    var csv =
      "model,case,status,axis,nx,ny,steps,pressure_relative_l2,ux_relative_l2,uy_relative_l2,max_pressure_normalized,max_velocity_normalized,energy_budget_normalized,initial_energy_error,boundary_velocity_normalized,dissipation_error_normalized,reflection_real,reflection_imag,reflection_error,fit_residual,reference,runtime_s\n"
    for result in all {
      let r = result.resolution
      let e = result.errors
      var values = [result.model, result.specification.id, result.status, r?.axis ?? "unsupported"]
      for value in [r?.nx, r?.ny, r?.steps] { values.append(value.map { String($0) } ?? "") }
      for i in 0...2 { values.append(e.map { String($0.fieldL2[i]) } ?? "") }
      for value in [
        e?.maxPressure, e?.maxVelocity, e?.energyBudget, e?.initialEnergyError, e?.boundaryVelocity,
        e?.dissipationError, e?.fittedReflection.real, e?.fittedReflection.imag, e?.reflectionError,
        e?.fitResidual,
      ] { values.append(value.map { String($0) } ?? "") }
      values += [result.reference, String(result.runtime)]
      csv += values.joined(separator: ",") + "\n"
    }
    try csv.write(to: root.appendingPathComponent("summary.csv"), atomically: true, encoding: .utf8)
    if failed {
      throw BenchmarkFailure.failedConformance("Oblique suite failed; full reports retained")
    }
  }
}
