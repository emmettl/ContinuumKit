import Foundation

/// Numerical wall-flow verification and physical area calibration have separate statuses.
public enum AdmittanceCommand {
  public static func timeCheck(_ series: [AdmittanceResult]) throws -> [Double] {
    if let first = series.first { try first.specification.validate() }
    guard series.count == 3, let first = series.first,
      series.allSatisfy({
        $0.numericalStatus == "passed" && $0.specification == first.specification
          && $0.model == first.model && ($0.errors?.rateL2.isFinite ?? false)
          && ($0.errors?.rateL2 ?? 0) > 0
          && ($0.history?.fields.dt.isFinite ?? false) && ($0.history?.fields.dt ?? 0) > 0
          && ($0.errors?.maxRateRelative.isFinite ?? false)
          && ($0.errors?.maxRateRelative ?? -1) >= 0
      }),
      series.compactMap(\.resolution)
        == AdmittanceResolution.standard().filter({ $0.axis == "time" })
    else { throw BenchmarkFailure.failedConformance("Incomplete wall-rate series") }
    var orders: [Double] = []
    for (a, b) in zip(series, series.dropFirst()) {
      let order =
        log(a.errors!.rateL2 / b.errors!.rateL2) / log(a.history!.fields.dt / b.history!.fields.dt)
      guard order.isFinite, (1.7...2.3).contains(order) else {
        throw BenchmarkFailure.failedConformance("Wall-rate order \(order)")
      }
      orders.append(order)
    }
    guard let last = series.last?.errors, last.rateL2.isFinite, last.rateL2 < 0.002,
      last.maxRateRelative < 0.002
    else { throw BenchmarkFailure.failedConformance("Finest isolated wall-flow rate bound failed") }
    return orders
  }
  public static func runReference() throws {
    try execute(
      model: "ContinuumKit.wall-admittance-reference", supported: true, reference: true,
      history: { c, r in try AdmittanceOracle.reference(c, r) })
  }
  public static func run(
    model: String, supported: Bool,
    history: (AdmittanceCase, AdmittanceResolution) throws -> AdmittanceHistory
  ) throws { try execute(model: model, supported: supported, reference: false, history: history) }
  private static func execute(
    model: String, supported: Bool, reference: Bool,
    history: (AdmittanceCase, AdmittanceResolution) throws -> AdmittanceHistory
  ) throws {
    func argument(_ key: String) -> String? {
      guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count
      else { return nil }
      return CommandLine.arguments[i + 1]
    }
    guard let output = argument("--output"), let metadata = argument("--metadata") else {
      throw BenchmarkFailure.invalidCase
    }
    let root = URL(fileURLWithPath: output)
    let env = try JSONDecoder().decode(
      BenchmarkEnvironment.self, from: Data(contentsOf: URL(fileURLWithPath: metadata)))
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let cases = AdmittanceCase.standard()
    var results: [AdmittanceResult] = []
    var reports: [[String: String]] = []
    var failed = false
    for c in cases {
      if !supported {
        results.append(
          AdmittanceResult(
            schemaVersion: 1, model: model, status: "unsupported", numericalStatus: "unsupported",
            physicalStatus: "unsupported",
            reason: "Production wave solver has no masked-domain update", specification: c,
            resolution: nil, environment: env, history: nil, errors: nil, runtime: 0))
        reports.append([
          "case": c.id, "axis": "all", "contract": "capability", "status": "unsupported",
        ])
        continue
      }
      var series: [AdmittanceResult] = []
      for r in AdmittanceResolution.standard() {
        do {
          let clock = ContinuousClock()
          let start = clock.now
          let h = try history(c, r)
          let elapsed = start.duration(to: clock.now).components
          let result = try AdmittanceResult.evaluate(
            model: model, c: c, r: r, environment: env, h: h,
            runtime: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
            reference: reference)
          series.append(result)
          if result.numericalStatus == "failed" { failed = true }
        } catch {
          failed = true
          series.append(
            AdmittanceResult(
              schemaVersion: 1, model: model, status: "failed", numericalStatus: "failed",
              physicalStatus: "not-evaluated", reason: String(describing: error), specification: c,
              resolution: r, environment: env, history: nil, errors: nil, runtime: 0))
        }
      }
      results += series
      do {
        let order = reference ? [] : try timeCheck(series.filter { $0.resolution?.axis == "time" })
        reports.append([
          "case": c.id, "axis": "time", "contract": "isolated-wall-flow",
          "status": reference ? "reference" : "passed", "orders": String(describing: order),
        ])
        let spatial = series.filter { $0.resolution?.axis == "space" }
        guard spatial.count == 3, spatial.allSatisfy({ $0.errors != nil }) else {
          throw BenchmarkFailure.invalidSamples
        }
        let physical = spatial.allSatisfy { $0.physicalStatus == "passed" } ? "passed" : "gap"
        reports.append([
          "case": c.id, "axis": "space", "contract": "physical-side-area", "status": physical,
          "relativeErrors": String(describing: spatial.map { $0.errors!.areaRelativeError }),
          "reason": physical == "gap"
            ? "A reported geometry gap is not a physical conformance pass"
            : "Prescribed-pressure wall power agrees with physical area",
        ])
        print(
          "\(reference ? "REFERENCE" : "NUMERICAL PASS") \(c.id) isolated wall rate: \(order); PHYSICAL AREA \(physical): \(spatial.map{$0.errors!.areaRelativeError})"
        )
      } catch {
        failed = true
        reports.append([
          "case": c.id, "axis": "all", "contract": "report", "status": "failed",
          "reason": String(describing: error),
        ])
      }
    }
    try encoder.encode(cases).write(to: root.appendingPathComponent("cases.json"))
    try encoder.encode(results).write(to: root.appendingPathComponent("results.json"))
    try encoder.encode(reports).write(to: root.appendingPathComponent("conformance.json"))
    var csv =
      "model,case,status,numerical_status,physical_status,axis,nx,ny,nz,courant,rate_relative_l2,max_rate_relative,pressure_step_relative_l2,energy_budget,work_relative,zero_velocity,inactive_preservation,initial_pressure_error,effective_area_m2,physical_area_m2,area_relative_error,effective_prescribed_power_w,physical_prescribed_power_w,energy_loss_j,midpoint_wall_work_j,runtime_s\n"
    for result in results {
      let r = result.resolution
      let e = result.errors
      var row = [
        result.model, result.specification.id, result.status, result.numericalStatus,
        result.physicalStatus, r?.axis ?? "unsupported",
      ]
      row += [r?.nx, r?.ny, r?.nz].map { $0.map { String($0) } ?? "" }
      row.append(r.map { String($0.courant) } ?? "")
      row += [
        e?.rateL2, e?.maxRateRelative, e?.pressureStepL2, e?.energyBudget, e?.workRelative,
        e?.zeroVelocity, e?.inactivePreservation, e?.initialPressureError, e?.effectiveArea,
        e?.physicalArea, e?.areaRelativeError, e?.effectivePrescribedPower,
        e?.physicalPrescribedPower, e?.energyLossJ, e?.midpointWallWorkJ,
      ].map { $0.map { String($0) } ?? "" }
      row.append(String(result.runtime))
      csv += row.joined(separator: ",") + "\n"
    }
    try csv.write(to: root.appendingPathComponent("summary.csv"), atomically: true, encoding: .utf8)
    if failed {
      throw BenchmarkFailure.failedConformance(
        "Admittance numerical/report checks failed; complete reports retained")
    }
  }
}
