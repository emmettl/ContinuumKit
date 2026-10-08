import Foundation

public enum BenchmarkFailure: Error {
  case invalidCase, invalidSamples
  case unsupported(String)
  case failedConformance(String)
}

/// Piecewise-linear prescribed volume; each leg occupies the same fraction of the clock.
/// The clock labels samples, rather than asserting a finite-speed piston or acoustic solution.
public struct AdiabaticCase: Codable, Equatable, Sendable {
  public let id: String
  public let version: Int
  public let initialVolumeM3: Double
  public let initialEnergyJ: Double
  public let heatCapacityRatio: Double
  public let durationS: Double
  public let volumeRatios: [Double]

  public init(
    id: String, initialVolumeM3: Double, initialEnergyJ: Double,
    heatCapacityRatio: Double = 1.4, durationS: Double = 1, volumeRatios: [Double]
  ) throws {
    self.id = id
    version = 1
    self.initialVolumeM3 = initialVolumeM3
    self.initialEnergyJ = initialEnergyJ
    self.heatCapacityRatio = heatCapacityRatio
    self.durationS = durationS
    self.volumeRatios = volumeRatios
    try validate()
  }

  public func validate() throws {
    guard !id.isEmpty, version == 1, initialVolumeM3.isFinite, initialVolumeM3 > 0,
      initialEnergyJ.isFinite, initialEnergyJ > 0, heatCapacityRatio.isFinite,
      heatCapacityRatio > 1,
      durationS.isFinite, durationS > 0, volumeRatios.count >= 2, volumeRatios.first == 1,
      volumeRatios.allSatisfy({ $0.isFinite && $0 > 0 && (initialVolumeM3 * $0).isFinite }),
      initialPressurePa.isFinite, initialPressurePa > 0
    else { throw BenchmarkFailure.invalidCase }
  }

  public var initialPressurePa: Double {
    (heatCapacityRatio - 1) * initialEnergyJ / initialVolumeM3
  }
  public var legs: Int { volumeRatios.count - 1 }

  public func volume(atFraction fraction: Double) -> Double {
    let coordinate = min(max(fraction, 0), 1) * Double(legs)
    let leg = min(Int(coordinate), legs - 1)
    let local = coordinate - Double(leg)
    return initialVolumeM3 * (volumeRatios[leg] * (1 - local) + volumeRatios[leg + 1] * local)
  }

  /// Independent oracle uses p V^gamma and U = pV/(gamma-1), not the extracted model's energy call.
  public func reference(atVolume volume: Double) -> (pressure: Double, energy: Double, work: Double)
  {
    let pressure = initialPressurePa * pow(initialVolumeM3 / volume, heatCapacityRatio)
    let energy = pressure * volume / (heatCapacityRatio - 1)
    let work = (initialPressurePa * initialVolumeM3 - pressure * volume) / (heatCapacityRatio - 1)
    return (pressure, energy, work)
  }

  public static func standard() throws -> [Self] {
    try [
      Self(
        id: "adiabatic-expansion", initialVolumeM3: 0.001, initialEnergyJ: 12, volumeRatios: [1, 2]),
      Self(
        id: "adiabatic-compression", initialVolumeM3: 0.001, initialEnergyJ: 12,
        volumeRatios: [1, 0.9]),
      Self(
        id: "adiabatic-cycle", initialVolumeM3: 0.001, initialEnergyJ: 12, volumeRatios: [1, 2, 1]),
    ]
  }
}
