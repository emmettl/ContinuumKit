import Foundation

public struct BoundaryErrors: Codable, Sendable {
  public let pressureL2, maxPressure, maxVelocity, energyBudget, initialEnergyError,
    boundaryVelocity: Double
  public let reflectedCoefficient: Double?
  public let returnedEnergyFraction: Double
}
public struct BoundaryResult: Codable, Sendable {
  public let schemaVersion: Int
  public let model, status, reference: String
  public let reason: String?
  public let specification: BoundaryAcousticCase
  public let resolution: BoundaryResolution?
  public let environment: BenchmarkEnvironment
  public let runtime: Double
  public let history: BoundaryHistory?
  public let errors: BoundaryErrors?
  public static func evaluate(
    model: String, c: BoundaryAcousticCase, r: BoundaryResolution,
    environment: BenchmarkEnvironment, runtime: Double, h: BoundaryHistory,
    status: String = "supported"
  ) throws -> Self {
    try c.validate()
    guard runtime.isFinite, runtime >= 0, r.nx >= 2, r.ny >= 2, r.steps > 0,
      [h.dx, h.dy, h.dt].allSatisfy({ $0.isFinite && $0 > 0 }),
      abs(h.dx * Double(r.nx) / c.lengthX - 1) < 1e-6,
      abs(h.dy * Double(r.ny) / c.lengthY - 1) < 1e-6,
      abs(h.dt * Double(r.steps) / c.duration - 1) < 1e-6, h.frames.map(\.step) == r.captures(c)
    else { throw BenchmarkFailure.invalidSamples }
    var squared = 0.0
    var referenceSquared = 0.0
    var maxP = 0.0
    var maxU = 0.0
    var budget = 0.0
    var boundary = 0.0
    var initial: Double?
    var lastEnergy = 0.0
    var lastLoss = 0.0
    var coefficient: Double?
    for f in h.frames {
      guard f.p.count == r.nx * r.ny, f.u.count == (r.nx + 1) * r.ny,
        f.v.count == r.nx * (r.ny + 1),
        (f.p + f.u + f.v).allSatisfy(\.isFinite), f.dissipation.isFinite, f.dissipation >= lastLoss
      else { throw BenchmarkFailure.invalidSamples }
      let t = Double(f.step) * h.dt
      let half = t - h.dt / 2
      func ref(_ x: Double, _ y: Double, _ time: Double) -> (p: Double, u: Double, v: Double) {
        c.state(
          x: x, y: y, t: time, dx: r.axis == "time" ? h.dx : nil, dy: r.axis == "time" ? h.dy : nil)
      }
      for j in 0..<r.ny {
        for i in 0..<r.nx {
          let value = ref((Double(i) + 0.5) * h.dx, (Double(j) + 0.5) * h.dy, t).p
          let d = f.p[j * r.nx + i] - value
          squared += d * d
          referenceSquared += value * value
          maxP = max(maxP, abs(d) / c.amplitude)
        }
      }
      for j in 0..<r.ny {
        for i in 0...r.nx {
          maxU = max(
            maxU,
            abs(f.u[j * (r.nx + 1) + i] - ref(Double(i) * h.dx, (Double(j) + 0.5) * h.dy, half).u)
              * c.density * c.speed / c.amplitude)
          if c.kind == .obliqueMode || i == 0 {
            if i == 0 || i == r.nx {
              boundary = max(
                boundary, abs(f.u[j * (r.nx + 1) + i]) * c.density * c.speed / c.amplitude)
            }
          }
        }
      }
      for j in 0...r.ny {
        for i in 0..<r.nx {
          maxU = max(
            maxU,
            abs(f.v[j * r.nx + i] - ref((Double(i) + 0.5) * h.dx, Double(j) * h.dy, half).v)
              * c.density * c.speed / c.amplitude)
          if j == 0 || j == r.ny {
            boundary = max(boundary, abs(f.v[j * r.nx + i]) * c.density * c.speed / c.amplitude)
          }
        }
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
      guard energy.isFinite else { throw BenchmarkFailure.invalidSamples }
      if initial == nil { initial = energy }
      guard let e0 = initial, e0 > 0 else { throw BenchmarkFailure.invalidSamples }
      budget = max(budget, abs((energy + f.dissipation) / e0 - 1))
      lastEnergy = energy
      lastLoss = f.dissipation
      if c.kind == .impedancePulse, f.step == r.steps {
        var numerator = 0.0
        var denominator = 0.0
        for j in 0..<r.ny {
          for i in 0..<r.nx {
            let shape = c.pulse(2 * c.lengthX - (Double(i) + 0.5) * h.dx - c.speed * t)
            numerator += f.p[j * r.nx + i] * shape
            denominator += shape * shape
          }
        }
        guard denominator > 0 else { throw BenchmarkFailure.invalidSamples }
        coefficient = numerator / denominator
      }
    }
    guard squared.isFinite, referenceSquared.isFinite, referenceSquared > 0, let e0 = initial else {
      throw BenchmarkFailure.invalidSamples
    }
    return Self(
      schemaVersion: 1, model: model, status: status,
      reference: r.axis == "time" ? "exact-2D-spatial-eigenmode" : "continuum", reason: nil,
      specification: c, resolution: r, environment: environment, runtime: runtime, history: h,
      errors: BoundaryErrors(
        pressureL2: sqrt(squared / referenceSquared), maxPressure: maxP, maxVelocity: maxU,
        energyBudget: budget,
        initialEnergyError: abs(e0 / c.energy - 1), boundaryVelocity: boundary,
        reflectedCoefficient: coefficient, returnedEnergyFraction: lastEnergy / e0))
  }
}
public enum BoundaryCommand {
  public static func check(_ series: [BoundaryResult]) throws -> [Double] {
    guard series.count == 3,
      series.allSatisfy({ $0.status == "supported" && $0.errors != nil && $0.history != nil }),
      let c = series.first?.specification,
      series.allSatisfy({
        $0.specification == c && $0.resolution?.axis == series[0].resolution?.axis
          && $0.model == series[0].model
      }),
      series.compactMap(\.resolution)
        == BoundaryResolution.standard(c).filter({ $0.axis == series[0].resolution?.axis })
    else { throw BenchmarkFailure.failedConformance("Incomplete boundary series") }
    var orders: [Double] = []
    let range = c.kind == .impedancePulse ? 0.8...2.3 : 1.7...2.3
    for (a, b) in zip(series, series.dropFirst()) {
      let ratio =
        a.resolution!.axis == "space"
        ? Double(b.resolution!.nx) / Double(a.resolution!.nx) : a.history!.dt / b.history!.dt
      let order = log(a.errors!.pressureL2 / b.errors!.pressureL2) / log(ratio)
      guard order.isFinite, range.contains(order) else {
        throw BenchmarkFailure.failedConformance(
          "Boundary refinement order \(order), expected \(range)")
      }
      orders.append(order)
    }
    try bounds(series.last!)
    return orders
  }
  public static func bounds(_ r: BoundaryResult) throws {
    guard let e = r.errors else { throw BenchmarkFailure.invalidSamples }
    let impedance = r.specification.kind == .impedancePulse
    guard e.pressureL2 < (impedance ? 0.02 : 0.01), e.maxPressure < 0.03, e.maxVelocity < 0.03,
      e.energyBudget < 1e-4,
      e.initialEnergyError < 0.01, e.boundaryVelocity < 1e-6,
      e.reflectedCoefficient.map({ abs($0 - r.specification.reflection) < 0.01 }) ?? true,
      !impedance
        || abs(e.returnedEnergyFraction - r.specification.reflection * r.specification.reflection)
          < 0.01
    else {
      throw BenchmarkFailure.failedConformance(
        "Boundary accuracy, reflection or work-budget bound failed")
    }
  }
  public static func run(
    model: String, supportsImpedance: Bool,
    history: (BoundaryAcousticCase, BoundaryResolution) throws -> BoundaryHistory
  ) throws {
    try execute(
      model: model, supportsImpedance: supportsImpedance, reference: false, history: history)
  }
  public static func runReference() throws {
    try execute(
      model: "ContinuumKit.boundary-reference", supportsImpedance: true, reference: true,
      history: BoundaryOracle.history)
  }
  private static func execute(
    model: String, supportsImpedance: Bool, reference: Bool,
    history: (BoundaryAcousticCase, BoundaryResolution) throws -> BoundaryHistory
  ) throws {
    let args = CommandLine.arguments
    func argument(_ name: String) -> String? {
      guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
      return args[i + 1]
    }
    guard let out = argument("--output"), let meta = argument("--metadata") else {
      throw BenchmarkFailure.invalidCase
    }
    let env = try JSONDecoder().decode(
      BenchmarkEnvironment.self, from: Data(contentsOf: URL(fileURLWithPath: meta)))
    let output = URL(fileURLWithPath: out)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let cases = try BoundaryAcousticCase.standard()
    var all: [BoundaryResult] = []
    var conformance: [[String: String]] = []
    var failed = false
    try encoder.encode(cases).write(to: output.appendingPathComponent("cases.json"))
    for c in cases {
      if c.kind == .impedancePulse && !supportsImpedance {
        all.append(
          BoundaryResult(
            schemaVersion: 1, model: model, status: "unsupported", reference: "continuum",
            reason: "Production solver supports rigid walls only",
            specification: c, resolution: nil, environment: env, runtime: 0, history: nil,
            errors: nil))
        conformance.append([
          "case": c.id, "axis": "space", "status": "unsupported",
          "reason": "No production impedance law",
        ])
        continue
      }
      var series: [BoundaryResult] = []
      for r in BoundaryResolution.standard(c) {
        let clock = ContinuousClock()
        let start = clock.now
        do {
          let h = try history(c, r)
          let elapsed = start.duration(to: clock.now).components
          let result = try BoundaryResult.evaluate(
            model: model, c: c, r: r, environment: env,
            runtime: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18, h: h,
            status: reference ? "reference" : "supported")
          series.append(result)
        } catch {
          failed = true
          series.append(
            BoundaryResult(
              schemaVersion: 1, model: model, status: "failed", reference: "not-evaluated",
              reason: String(describing: error), specification: c, resolution: r, environment: env,
              runtime: 0, history: nil, errors: nil))
        }
      }
      all += series
      for axis in (c.kind == .obliqueMode ? ["space", "time"] : ["space"]) {
        do {
          let orders = reference ? [] : try check(series.filter { $0.resolution?.axis == axis })
          conformance.append([
            "case": c.id, "axis": axis, "status": reference ? "reference" : "passed",
            "orders": String(describing: orders),
          ])
          print("\(reference ? "REFERENCE":"PASS") \(model) \(c.id) \(axis): \(orders)")
        } catch {
          failed = true
          conformance.append([
            "case": c.id, "axis": axis, "status": "failed", "reason": String(describing: error),
          ])
          print("FAIL \(c.id): \(error)")
        }
      }
      if c.kind == .impedancePulse && !reference {
        do {
          guard
            let fine = series.first(where: {
              $0.resolution?.nx == 512 && $0.resolution?.axis == "space"
            }), let half = series.last, let a = fine.errors, let b = half.errors,
            abs(a.pressureL2 - b.pressureL2) < 1e-3,
            abs(a.reflectedCoefficient! - b.reflectedCoefficient!) < 1e-3
          else { throw BenchmarkFailure.failedConformance("Impedance timestep sensitivity failed") }
          try bounds(half)
          conformance.append([
            "case": c.id, "axis": "time-sensitivity", "status": "passed",
            "claim": "bounded sensitivity; no temporal order claim",
          ])
        } catch {
          failed = true
          conformance.append([
            "case": c.id, "axis": "time-sensitivity", "status": "failed",
            "reason": String(describing: error),
          ])
        }
      } else if c.kind == .impedancePulse {
        conformance.append(["case": c.id, "axis": "time-sensitivity", "status": "reference"])
      }
    }
    try encoder.encode(all).write(to: output.appendingPathComponent("results.json"))
    try encoder.encode(conformance).write(to: output.appendingPathComponent("conformance.json"))
    var csv =
      "model,case,status,axis,nx,ny,steps,pressure_relative_l2,max_pressure_over_amplitude,max_velocity_normalized,energy_budget_normalized,reflection_coefficient,returned_energy_fraction,reference,runtime_s\n"
    for result in all {
      let r = result.resolution
      let e = result.errors
      func number(_ value: Double?) -> String { value.map { String($0) } ?? "" }
      var values: [String] = [
        result.model, result.specification.id, result.status, r?.axis ?? "unsupported",
      ]
      values.append(r.map { String($0.nx) } ?? "")
      values.append(r.map { String($0.ny) } ?? "")
      values.append(r.map { String($0.steps) } ?? "")
      values.append(number(e?.pressureL2))
      values.append(number(e?.maxPressure))
      values.append(number(e?.maxVelocity))
      values.append(number(e?.energyBudget))
      values.append(number(e?.reflectedCoefficient))
      values.append(number(e?.returnedEnergyFraction))
      values.append(result.reference)
      values.append(String(result.runtime))
      csv += values.joined(separator: ",") + "\n"
    }
    try csv.write(
      to: output.appendingPathComponent("summary.csv"), atomically: true, encoding: .utf8)
    if failed {
      throw BenchmarkFailure.failedConformance("Boundary suite failed; full reports retained")
    }
  }
}
