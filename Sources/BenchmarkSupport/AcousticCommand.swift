import Foundation

public struct AcousticConformance: Codable, Sendable {
  public let schemaVersion: Int
  public let caseID, model, axis, status: String
  public let observedOrders: [Double]
  public let failureReason: String?
}
public enum AcousticCommand {
  public static func check(_ results: [AcousticResult]) throws -> [Double] {
    guard results.count == 3,
      results.allSatisfy({ $0.status == "supported" && $0.errors != nil && $0.history != nil }),
      let first = results.first,
      results.allSatisfy({
        $0.caseSpecification == first.caseSpecification
          && $0.resolution.axis == first.resolution.axis && $0.model == first.model
      })
    else {
      throw BenchmarkFailure.failedConformance("Incomplete, failed or unsupported acoustic series")
    }
    let expected = AcousticResolution.standard(for: first.caseSpecification).filter {
      $0.axis == first.resolution.axis
    }
    guard results.map(\.resolution) == expected else {
      throw BenchmarkFailure.failedConformance("Wrong refinement resolutions")
    }
    var orders: [Double] = []
    for pair in zip(results, results.dropFirst()) {
      let a = pair.0.errors!.pressureRelativeL2
      let b = pair.1.errors!.pressureRelativeL2
      guard a > b, b > 0 else {
        throw BenchmarkFailure.failedConformance("Pressure error does not strictly refine")
      }
      let factor =
        first.resolution.axis == .space
        ? Double(pair.1.resolution.cells) / Double(pair.0.resolution.cells)
        : pair.0.history!.timeStepS / pair.1.history!.timeStepS
      let order = log(a / b) / log(factor)
      guard order.isFinite, (1.7...2.3).contains(order) else {
        throw BenchmarkFailure.failedConformance(
          "Second-order acoustic refinement failed: \(order)")
      }
      orders.append(order)
    }
    let e = results.last!.errors!
    guard e.pressureRelativeL2 < 0.01, e.maximumPressureNormalized < 0.03,
      e.maximumVelocityNormalized < 0.03, e.maximumAmplitudeRelative < 0.01,
      e.maximumPhaseRad < 0.01, e.maximumSpeedRelative < 0.01,
      e.maximumDiscreteEnergyDrift < 1e-4, e.initialContinuumEnergyRelative < 0.01,
      e.maximumMeanPressureDrift < 1e-5, e.maximumBoundaryVelocityNormalized < 1e-6,
      e.reflectionWallPressureRatio.map({ abs($0 - 2) < 0.02 }) ?? true,
      e.returnedPulseAmplitudeRatio.map({ abs($0 - 1) < 0.01 }) ?? true
    else {
      throw BenchmarkFailure.failedConformance(
        "Finest acoustic accuracy, reflection or invariant bounds failed")
    }
    return orders
  }

  public static func run(
    model: String, history: (AcousticCase, AcousticResolution) throws -> AcousticHistory
  ) throws {
    try run(model: model, referenceOnly: false, history: history)
  }
  public static func runReference() throws {
    try run(model: "ContinuumKit.analytic-acoustic-reference", referenceOnly: true) { c, r in
      let dx = c.lengthM / Double(r.cells)
      let dt = c.durationS / Double(r.steps)
      let lattice =
        r.axis == .time ? try AcousticOracle.SpatialLattice(c, cells: r.cells, spacingM: dx) : nil
      let frames = r.captureSteps(for: c).map { step in
        let time = Double(step) * dt
        let p =
          lattice?.fields(timeS: time).pressurePa
          ?? (0..<r.cells).map {
            AcousticOracle.continuum(c, xM: (Double($0) + 0.5) * dx, timeS: time).pressurePa
          }
        let u =
          lattice?.fields(timeS: time - dt / 2).velocityMps
          ?? (0...r.cells).map {
            AcousticOracle.continuum(c, xM: Double($0) * dx, timeS: time - dt / 2).velocityMps
          }
        return AcousticFrame(step: step, pressurePa: p, normalVelocityMps: u)
      }
      return AcousticHistory(spacingM: dx, timeStepS: dt, frames: frames)
    }
  }
  private static func run(
    model: String, referenceOnly: Bool,
    history: (AcousticCase, AcousticResolution) throws -> AcousticHistory
  ) throws {
    let args = Array(CommandLine.arguments.dropFirst())
    func argument(_ flag: String) -> String? {
      guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
      return args[i + 1]
    }
    guard let outputPath = argument("--output"), let metadataPath = argument("--metadata") else {
      throw BenchmarkFailure.failedConformance("Supply --output DIRECTORY and --metadata FILE.json")
    }
    let decoder = JSONDecoder()
    let environment = try decoder.decode(
      BenchmarkEnvironment.self, from: Data(contentsOf: URL(fileURLWithPath: metadataPath)))
    let cases =
      try argument("--cases").map {
        try decoder.decode([AcousticCase].self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
      }
      ?? AcousticCase.standard()
    guard !cases.isEmpty, Set(cases.map(\.id)).count == cases.count else {
      throw BenchmarkFailure.invalidCase
    }
    let output = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(cases).write(
      to: output.appendingPathComponent("cases.json"), options: .atomic)
    var results: [AcousticResult] = []
    var conformance: [AcousticConformance] = []
    var failed = false
    for (caseIndex, c) in cases.enumerated() {
      try c.validate()
      var series: [AcousticResult] = []
      for (runIndex, r) in AcousticResolution.standard(for: c).enumerated() {
        let clock = ContinuousClock()
        let start = clock.now
        do {
          let h = try history(c, r)
          let elapsed = start.duration(to: clock.now).components
          let result = try AcousticResult.evaluate(
            model: model, caseSpecification: c, resolution: r,
            environment: environment,
            runtimeS: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
            history: h, status: referenceOnly ? "reference" : "supported")
          series.append(result)
          try result.fieldCSV.write(
            to: output.appendingPathComponent("case-\(caseIndex)-run-\(runIndex).csv"),
            atomically: true, encoding: .utf8)
        } catch {
          let status: String
          if case BenchmarkFailure.unsupported = error {
            status = "unsupported"
          } else {
            status = "failed"
          }
          series.append(
            .unavailable(
              model: model, status: status, reason: String(describing: error),
              caseSpecification: c, resolution: r, environment: environment))
          failed = true
        }
      }
      results += series
      for axis in [AcousticResolution.Axis.space, .time] {
        let selected = series.filter { $0.resolution.axis == axis }
        do {
          let orders = referenceOnly ? [] : try check(selected)
          conformance.append(
            AcousticConformance(
              schemaVersion: 1, caseID: c.id, model: model,
              axis: axis.rawValue, status: referenceOnly ? "reference" : "passed",
              observedOrders: orders, failureReason: nil))
          print("\(referenceOnly ? "REFERENCE" : "PASS") \(model) \(c.id) \(axis): \(orders)")
        } catch {
          failed = true
          conformance.append(
            AcousticConformance(
              schemaVersion: 1, caseID: c.id, model: model,
              axis: axis.rawValue, status: "failed", observedOrders: [],
              failureReason: String(describing: error)))
          print("FAIL \(model) \(c.id) \(axis): \(error)")
        }
      }
    }
    try encoder.encode(results).write(
      to: output.appendingPathComponent("results.json"), options: .atomic)
    try encoder.encode(conformance).write(
      to: output.appendingPathComponent("conformance.json"), options: .atomic)
    if failed {
      throw BenchmarkFailure.failedConformance(
        "Acoustic suite failed; inspect retained results/conformance")
    }
  }
}
