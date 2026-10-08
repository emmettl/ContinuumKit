import Foundation

public struct BenchmarkEnvironment: Codable, Equatable, Sendable {
  public let repository: String
  public let revision: String
  public let sourceHashes: [String: String]
  public let hardware: String
  public let toolchain: String
  public let operatingSystem: String
  public let workingTreeDirty: Bool
  public let precision: String

  public init(
    repository: String, revision: String, sourceHashes: [String: String], hardware: String,
    toolchain: String, operatingSystem: String, precision: String = "Float64",
    workingTreeDirty: Bool = false
  ) {
    self.repository = repository
    self.revision = revision
    self.sourceHashes = sourceHashes
    self.hardware = hardware
    self.toolchain = toolchain
    self.operatingSystem = operatingSystem
    self.precision = precision
    self.workingTreeDirty = workingTreeDirty
  }
}

public struct AdiabaticSample: Codable, Sendable {
  public let timeS: Double
  public let volumeM3: Double
  public let energyJ: Double
  public let pressurePa: Double
  public let workByReservoirJ: Double
  public let massKg: Double?

  public init(
    timeS: Double, volumeM3: Double, energyJ: Double, pressurePa: Double,
    workByReservoirJ: Double, massKg: Double? = nil
  ) {
    self.timeS = timeS
    self.volumeM3 = volumeM3
    self.energyJ = energyJ
    self.pressurePa = pressurePa
    self.workByReservoirJ = workByReservoirJ
    self.massKg = massKg
  }
}

public struct AdiabaticErrors: Codable, Sendable {
  public let maximumRelativePressure: Double
  public let maximumEnergyNormalized: Double
  public let maximumWorkNormalized: Double
  public let maximumEnergyBudgetResidualJ: Double
  public let maximumEnergyBudgetNormalized: Double
  public let maximumRelativeMassChange: Double?
}

public struct AdiabaticResult: Codable, Sendable {
  public let schemaVersion: Int
  public let model: String
  public let status: String
  public let unsupportedReason: String?
  public let caseSpecification: AdiabaticCase
  public let environment: BenchmarkEnvironment
  public let steps: Int
  public let runtimeS: Double
  public let assumptions: [String]
  public let massAccounting: String
  public let samples: [AdiabaticSample]
  public let errors: AdiabaticErrors?

  public static func evaluate(
    model: String, caseSpecification c: AdiabaticCase,
    environment: BenchmarkEnvironment, steps: Int, runtimeS: Double,
    samples: [AdiabaticSample]
  ) throws -> Self {
    try c.validate()
    guard steps > 0, steps % c.legs == 0, samples.count == steps + 1,
      runtimeS.isFinite, runtimeS >= 0
    else { throw BenchmarkFailure.invalidSamples }
    let masses = samples.compactMap(\.massKg)
    guard masses.isEmpty || masses.count == samples.count,
      masses.allSatisfy({ $0.isFinite && $0 > 0 })
    else { throw BenchmarkFailure.invalidSamples }
    var pressureError = 0.0
    var energyError = 0.0
    var workError = 0.0
    var budgetError = 0.0
    var massError = 0.0
    for (index, s) in samples.enumerated() {
      let fraction = Double(index) / Double(steps)
      guard
        [s.timeS, s.volumeM3, s.energyJ, s.pressurePa, s.workByReservoirJ].allSatisfy(\.isFinite),
        s.volumeM3 > 0, s.energyJ > 0, s.pressurePa > 0,
        abs(s.timeS - c.durationS * fraction) <= 1e-12 * c.durationS,
        abs(s.volumeM3 - c.volume(atFraction: fraction)) <= 1e-12 * c.initialVolumeM3
      else { throw BenchmarkFailure.invalidSamples }
      let reference = c.reference(atVolume: s.volumeM3)
      guard [reference.pressure, reference.energy, reference.work].allSatisfy(\.isFinite),
        reference.pressure > 0
      else { throw BenchmarkFailure.invalidCase }
      pressureError = max(pressureError, abs(s.pressurePa / reference.pressure - 1))
      energyError = max(energyError, abs(s.energyJ - reference.energy) / c.initialEnergyJ)
      workError = max(workError, abs(s.workByReservoirJ - reference.work) / c.initialEnergyJ)
      budgetError = max(budgetError, abs(s.energyJ + s.workByReservoirJ - c.initialEnergyJ))
      if let mass = s.massKg, let initial = masses.first {
        massError = max(massError, abs(mass / initial - 1))
      }
    }
    guard [pressureError, energyError, workError, budgetError, massError].allSatisfy(\.isFinite)
    else {
      throw BenchmarkFailure.invalidSamples
    }
    return Self(
      schemaVersion: 1, model: model, status: "supported", unsupportedReason: nil,
      caseSpecification: c, environment: environment, steps: steps, runtimeS: runtimeS,
      assumptions: assumptions,
      massAccounting: masses.isEmpty ? "implicit-fixed-mass" : "tracked-fixed-mass",
      samples: samples,
      errors: AdiabaticErrors(
        maximumRelativePressure: pressureError, maximumEnergyNormalized: energyError,
        maximumWorkNormalized: workError, maximumEnergyBudgetResidualJ: budgetError,
        maximumEnergyBudgetNormalized: budgetError / c.initialEnergyJ,
        maximumRelativeMassChange: masses.isEmpty ? nil : massError))
  }

  public static func unsupported(
    model: String, caseSpecification: AdiabaticCase,
    environment: BenchmarkEnvironment, reason: String
  ) -> Self {
    Self(
      schemaVersion: 1, model: model, status: "unsupported", unsupportedReason: reason,
      caseSpecification: caseSpecification, environment: environment, steps: 0, runtimeS: 0,
      assumptions: assumptions, massAccounting: "not-evaluated", samples: [], errors: nil)
  }

  private static let assumptions = [
    "uniform-pressure", "fixed-mass", "no-heat-or-mass-exchange",
    "constant-heat-capacity-ratio", "prescribed-volume", "no-net-momentum",
  ]

  public var historyCSV: String {
    var csv = "time_s,volume_m3,internal_energy_j,pressure_pa,work_by_reservoir_j,mass_kg\n"
    for sample in samples {
      let mass = sample.massKg.map { String($0) } ?? ""
      csv +=
        "\(sample.timeS),\(sample.volumeM3),\(sample.energyJ),\(sample.pressurePa),\(sample.workByReservoirJ),\(mass)\n"
    }
    return csv
  }
}
