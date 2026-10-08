import BenchmarkSupport
import Foundation
import Testing

@Suite("Adiabatic benchmark contract")
struct AdiabaticBenchmarkTests {
  let environment = BenchmarkEnvironment(
    repository: "fixture", revision: "fixture", sourceHashes: [:],
    hardware: "test", toolchain: "test", operatingSystem: "test")

  @Test("Pressure-first oracle agrees with an integer-exponent analytic reference")
  func oracle() throws {
    let c = try AdiabaticCase(
      id: "golden", initialVolumeM3: 2, initialEnergyJ: 5,
      heatCapacityRatio: 2, volumeRatios: [1, 2])
    let reference = c.reference(atVolume: 4)
    #expect(reference.pressure == 0.625 && reference.energy == 2.5 && reference.work == 2.5)
  }

  @Test("All canonical histories refine pressure-work quadrature at second order")
  func histories() throws {
    for c in try AdiabaticCase.standard() {
      let results = try AdiabaticBenchmark.resolutions.map { n in
        try AdiabaticResult.evaluate(
          model: "fixture", caseSpecification: c,
          environment: environment, steps: n, runtimeS: 0,
          samples: AdiabaticBenchmark.reservoirSamples(caseSpecification: c, steps: n))
      }
      let orders = try AdiabaticBenchmark.checkRefinement(
        results, metric: "work", expectedOrder: 1.8...2.2)
      #expect(orders.count == 3)
      #expect(results.allSatisfy { $0.errors!.maximumRelativePressure < 1e-14 })
      #expect(results.allSatisfy { $0.errors!.maximumRelativeMassChange == nil })
      #expect(results.allSatisfy { $0.massAccounting == "implicit-fixed-mass" })
      if c.id == "adiabatic-cycle" {
        #expect(results.last!.samples.last!.volumeM3 == c.initialVolumeM3)
        #expect(results.last!.errors!.maximumWorkNormalized > 1e-6)
      }
    }
  }

  @Test("Result JSON and unit-labelled CSV retain the actual case and budget fields")
  func interchange() throws {
    let c = try AdiabaticCase.standard()[0]
    let result = try AdiabaticResult.evaluate(
      model: "fixture", caseSpecification: c,
      environment: environment, steps: 16, runtimeS: 0.1,
      samples: AdiabaticBenchmark.reservoirSamples(caseSpecification: c, steps: 16))
    let decoded = try JSONDecoder().decode(AdiabaticResult.self, from: JSONEncoder().encode(result))
    #expect(decoded.schemaVersion == 1 && decoded.caseSpecification == c)
    #expect(decoded.environment.precision == "Float64")
    #expect(
      decoded.historyCSV.hasPrefix(
        "time_s,volume_m3,internal_energy_j,pressure_pa,work_by_reservoir_j,mass_kg\n"))
    #expect(decoded.historyCSV.split(separator: "\n").count == 18)
  }

  @Test("Unsupported capabilities cannot become a passing refinement series")
  func unsupported() throws {
    let c = try AdiabaticCase.standard()[0]
    let result = AdiabaticResult.unsupported(
      model: "fixture", caseSpecification: c,
      environment: environment, reason: "heat-capacity ratio unavailable")
    #expect(result.status == "unsupported" && result.errors == nil && result.samples.isEmpty)
    #expect(throws: BenchmarkFailure.self) {
      try AdiabaticBenchmark.checkRefinement([result], metric: "work", expectedOrder: 1.8...2.2)
    }
  }

  @Test("Missing samples, wrong prescribed volume and a changing tracked mass are detected")
  func invalidHistory() throws {
    let c = try AdiabaticCase.standard()[0]
    let good = try AdiabaticBenchmark.reservoirSamples(caseSpecification: c, steps: 16)
    #expect(throws: BenchmarkFailure.self) {
      try AdiabaticResult.evaluate(
        model: "fixture", caseSpecification: c, environment: environment,
        steps: 16, runtimeS: 0, samples: Array(good.dropLast()))
    }
    var wrong = good
    wrong[4] = AdiabaticSample(
      timeS: good[4].timeS, volumeM3: 2, energyJ: good[4].energyJ,
      pressurePa: good[4].pressurePa, workByReservoirJ: good[4].workByReservoirJ)
    #expect(throws: BenchmarkFailure.self) {
      try AdiabaticResult.evaluate(
        model: "fixture", caseSpecification: c, environment: environment,
        steps: 16, runtimeS: 0, samples: wrong)
    }
    let drifting = good.enumerated().map { n, s in
      AdiabaticSample(
        timeS: s.timeS, volumeM3: s.volumeM3, energyJ: s.energyJ,
        pressurePa: s.pressurePa, workByReservoirJ: s.workByReservoirJ, massKg: 1 + Double(n) * 0.01
      )
    }
    let result = try AdiabaticResult.evaluate(
      model: "fixture", caseSpecification: c,
      environment: environment, steps: 16, runtimeS: 0, samples: drifting)
    #expect(result.errors!.maximumRelativeMassChange! > 0.15)
    #expect(throws: BenchmarkFailure.self) {
      try AdiabaticBenchmark.checkRefinement(
        [result, result, result], metric: "work", expectedOrder: 1.8...2.2)
    }
  }

  @Test("Decoded invalid case versions are validated before evaluation")
  func invalidCase() throws {
    let c = try AdiabaticCase.standard()[0]
    var data = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as? [String: Any])
    data["version"] = 2
    let decoded = try JSONDecoder().decode(
      AdiabaticCase.self,
      from: JSONSerialization.data(withJSONObject: data))
    #expect(throws: BenchmarkFailure.self) { try decoded.validate() }
  }
  @Test("A balanced but wrong pressure history does not pass accuracy checks")
  func budgetIsNotAccuracy() throws {
    let c = try AdiabaticCase.standard()[0]
    let results = try AdiabaticBenchmark.resolutions.map { n in
      let samples = (0...n).map { index in
        AdiabaticSample(
          timeS: Double(index) / Double(n),
          volumeM3: c.volume(atFraction: Double(index) / Double(n)), energyJ: c.initialEnergyJ,
          pressurePa: c.initialPressurePa, workByReservoirJ: 0)
      }
      return try AdiabaticResult.evaluate(
        model: "balanced-but-wrong", caseSpecification: c,
        environment: environment, steps: n, runtimeS: 0, samples: samples)
    }
    #expect(results.last!.errors!.maximumEnergyBudgetNormalized == 0)
    #expect(results.last!.errors!.maximumRelativePressure > 1)
    #expect(throws: BenchmarkFailure.self) {
      try AdiabaticBenchmark.checkRefinement(results, metric: "pressure", expectedOrder: 0.8...1.2)
    }
  }

}
