import Foundation

/// Shared command/report orchestration; adapters supply actual source calculations.
public enum AdiabaticCommand {
  public static func run(
    model: String, refinementMetric: String, expectedOrder: ClosedRange<Double>,
    samples: (AdiabaticCase, Int) throws -> [AdiabaticSample]
  ) throws {
    let args = Array(CommandLine.arguments.dropFirst())
    func argument(_ flag: String) -> String? {
      guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
      return args[index + 1]
    }
    guard let outputPath = argument("--output"), let metadataPath = argument("--metadata") else {
      throw BenchmarkFailure.failedConformance("Supply --output DIRECTORY and --metadata FILE.json")
    }
    let environment = try JSONDecoder().decode(
      BenchmarkEnvironment.self,
      from: Data(
        contentsOf:
          URL(fileURLWithPath: metadataPath)))
    let cases: [AdiabaticCase]
    if let path = argument("--cases") {
      cases = try JSONDecoder().decode(
        [AdiabaticCase].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    } else {
      cases = try AdiabaticCase.standard()
    }
    guard !cases.isEmpty, Set(cases.map(\.id)).count == cases.count else {
      throw BenchmarkFailure.invalidCase
    }
    let output = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(cases).write(
      to: output.appendingPathComponent("cases.json"), options: .atomic)
    var all: [AdiabaticResult] = []
    var failure: Error?
    var conformance: [SeriesConformance] = []
    for (caseIndex, specification) in cases.enumerated() {
      try specification.validate()
      var series: [AdiabaticResult] = []
      for steps in AdiabaticBenchmark.resolutions {
        let clock = ContinuousClock()
        let start = clock.now
        do {
          let history = try samples(specification, steps)
          let elapsed = start.duration(to: clock.now).components
          let result = try AdiabaticResult.evaluate(
            model: model, caseSpecification: specification,
            environment: environment, steps: steps,
            runtimeS: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
            samples: history)
          series.append(result)
          try result.historyCSV.write(
            to: output.appendingPathComponent("case-\(caseIndex)-n\(steps).csv"),
            atomically: true, encoding: .utf8)
        } catch BenchmarkFailure.unsupported(let reason) {
          series.append(
            .unsupported(
              model: model, caseSpecification: specification,
              environment: environment, reason: reason))
          break
        }
      }
      all += series
      do {
        let orders = try AdiabaticBenchmark.checkRefinement(
          series, metric: refinementMetric,
          expectedOrder: expectedOrder)
        conformance.append(
          SeriesConformance(
            caseID: specification.id, model: model, status: "passed",
            refinementMetric: refinementMetric, observedOrders: orders,
            expectedOrderRange: [expectedOrder.lowerBound, expectedOrder.upperBound],
            failureReason: nil))
        print("PASS \(model) \(specification.id): \(refinementMetric) orders \(orders)")
      } catch {
        failure = error
        conformance.append(
          SeriesConformance(
            caseID: specification.id, model: model, status: "failed",
            refinementMetric: refinementMetric, observedOrders: [],
            expectedOrderRange: [expectedOrder.lowerBound, expectedOrder.upperBound],
            failureReason: String(describing: error)))
      }
    }
    try encoder.encode(all).write(
      to: output.appendingPathComponent("results.json"), options: .atomic)
    try encoder.encode(conformance).write(
      to: output.appendingPathComponent("conformance.json"), options: .atomic)
    if let failure { throw failure }
  }
}

private struct SeriesConformance: Encodable {
  let schemaVersion = 1
  let caseID: String
  let model: String
  let status: String
  let refinementMetric: String
  let observedOrders: [Double]
  let expectedOrderRange: [Double]
  let failureReason: String?
  let finestBounds: [String: Double] = [
    "pressureRelative": 0.01, "energyNormalized": 0.01,
    "workNormalized": 0.01, "energyBudgetNormalized": 1e-3, "massRelative": 1e-12,
  ]
}
