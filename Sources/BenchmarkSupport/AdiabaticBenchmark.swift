import Foundation
import Thermodynamics

public enum AdiabaticBenchmark {
  public static let resolutions = [16, 32, 64, 128]

  /// Endpoint states are exact potential evaluations; only p dV quadrature is refined here.
  public static func trapezoidalSamples(
    caseSpecification c: AdiabaticCase, steps: Int,
    evaluate: (Double) throws -> (energy: Double, pressure: Double)
  ) throws -> [AdiabaticSample] {
    try c.validate()
    guard steps > 0, steps % c.legs == 0 else { throw BenchmarkFailure.invalidSamples }
    var samples: [AdiabaticSample] = []
    var work = 0.0
    for index in 0...steps {
      let fraction = Double(index) / Double(steps)
      let volume = c.volume(atFraction: fraction)
      let state = try evaluate(volume)
      if let previous = samples.last {
        work += 0.5 * (previous.pressurePa + state.pressure) * (volume - previous.volumeM3)
      }
      samples.append(
        AdiabaticSample(
          timeS: c.durationS * fraction, volumeM3: volume,
          energyJ: state.energy, pressurePa: state.pressure, workByReservoirJ: work))
    }
    return samples
  }

  public static func reservoirSamples(caseSpecification c: AdiabaticCase, steps: Int) throws
    -> [AdiabaticSample]
  {
    let reservoir = try AdiabaticReservoir(
      referenceVolume: c.initialVolumeM3,
      referenceEnergy: c.initialEnergyJ, heatCapacityRatio: c.heatCapacityRatio)
    return try trapezoidalSamples(caseSpecification: c, steps: steps) {
      let state = try reservoir.state(atVolume: $0)
      return (state.energy, state.pressure)
    }
  }

  /// Complete-history error must refine, and the finest case must meet declared accuracy/budget bounds.
  /// Pressure/energy algebra errors at roundoff are not assigned a spurious temporal order.
  public static func checkRefinement(
    _ results: [AdiabaticResult], metric: String,
    expectedOrder: ClosedRange<Double>
  ) throws -> [Double] {
    guard results.count >= 3, let first = results.first,
      results.allSatisfy({
        $0.status == "supported" && $0.caseSpecification == first.caseSpecification
          && $0.model == first.model && $0.environment == first.environment
      }),
      let finest = results.last, let errors = finest.errors
    else { throw BenchmarkFailure.failedConformance("Missing or unsupported required result") }
    guard errors.maximumRelativePressure < 0.01, errors.maximumEnergyNormalized < 0.01,
      errors.maximumWorkNormalized < 0.01, errors.maximumEnergyBudgetNormalized < 1e-3,
      errors.maximumRelativeMassChange.map({ $0 < 1e-12 }) ?? true
    else { throw BenchmarkFailure.failedConformance("Finest accuracy or budget bound failed") }
    func value(_ result: AdiabaticResult) throws -> Double {
      guard let e = result.errors else { throw BenchmarkFailure.invalidSamples }
      switch metric {
      case "work": return e.maximumWorkNormalized
      case "pressure": return e.maximumRelativePressure
      default: throw BenchmarkFailure.failedConformance("Unknown refinement metric")
      }
    }
    var orders: [Double] = []
    for index in 1..<results.count {
      let before = results[index - 1]
      let after = results[index]
      guard after.steps == before.steps * 2 else { throw BenchmarkFailure.invalidSamples }
      let old = try value(before)
      let new = try value(after)
      guard old > 0, new > 0, new < old else {
        throw BenchmarkFailure.failedConformance("Error did not decrease under refinement")
      }
      let order = log(old / new) / log(2)
      guard expectedOrder.contains(order) else {
        throw BenchmarkFailure.failedConformance("Observed order \(order) outside \(expectedOrder)")
      }
      orders.append(order)
    }
    return orders
  }
}
