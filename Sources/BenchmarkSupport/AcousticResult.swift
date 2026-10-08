import Foundation

public struct AcousticFrame: Codable, Sendable {
  public let step: Int
  public let pressurePa, normalVelocityMps: [Double]
  public init(step: Int, pressurePa: [Double], normalVelocityMps: [Double]) {
    self.step = step
    self.pressurePa = pressurePa
    self.normalVelocityMps = normalVelocityMps
  }
}
public struct AcousticHistory: Codable, Sendable {
  public let spacingM, timeStepS: Double
  public let frames: [AcousticFrame]
  public init(spacingM: Double, timeStepS: Double, frames: [AcousticFrame]) {
    self.spacingM = spacingM
    self.timeStepS = timeStepS
    self.frames = frames
  }
}
public struct AcousticErrors: Codable, Sendable {
  public let pressureRelativeL2, maximumPressureNormalized, maximumVelocityNormalized: Double
  public let maximumAmplitudeRelative, maximumPhaseRad, maximumSpeedRelative: Double
  public let maximumDiscreteEnergyDrift, initialContinuumEnergyRelative,
    maximumMeanPressureDrift: Double
  public let maximumBoundaryVelocityNormalized: Double
  public let reflectionWallPressureRatio, returnedPulseAmplitudeRatio: Double?
}
public struct AcousticResult: Codable, Sendable {
  public let schemaVersion: Int
  public let model, status: String
  public let failureReason: String?
  public let caseSpecification: AcousticCase
  public let resolution: AcousticResolution
  public let environment: BenchmarkEnvironment
  public let runtimeS: Double
  public let reference: String
  public let assumptions: [String]
  public let history: AcousticHistory?
  public let errors: AcousticErrors?

  public static func unavailable(
    model: String, status: String, reason: String, caseSpecification c: AcousticCase,
    resolution: AcousticResolution, environment: BenchmarkEnvironment
  ) -> Self {
    Self(
      schemaVersion: 1, model: model, status: status, failureReason: reason,
      caseSpecification: c, resolution: resolution, environment: environment, runtimeS: 0,
      reference: reference(for: resolution), assumptions: assumptions, history: nil, errors: nil)
  }
  private static func reference(for r: AcousticResolution) -> String {
    r.axis == .space
      ? "continuum-translation-and-Neumann-image" : "exact-fixed-spatial-lattice-eigenmodes"
  }
  private static let assumptions = [
    "linear-lossless-homogeneous-acoustics", "plane-pulse-uniform-transverse-fields",
    "rigid-normal-boundaries", "no-source-after-initialization", "pressure-cell-centres",
    "normal-velocity-faces-at-minus-half-time-step", "Taylor-half-kick-from-fixed-initial-state",
  ]

  public static func evaluate(
    model: String, caseSpecification c: AcousticCase, resolution r: AcousticResolution,
    environment: BenchmarkEnvironment, runtimeS: Double, history h: AcousticHistory,
    status: String = "supported"
  ) throws -> Self {
    try c.validate()
    guard r.cells >= 2, r.steps > 0, runtimeS.isFinite, runtimeS >= 0,
      h.spacingM.isFinite, h.spacingM > 0, h.timeStepS.isFinite, h.timeStepS > 0,
      abs(h.spacingM * Double(r.cells) / c.lengthM - 1) < 1e-6,
      abs(h.timeStepS * Double(r.steps) / c.durationS - 1) < 1e-6,
      h.frames.map(\.step) == r.captureSteps(for: c),
      c.soundSpeedMps * h.timeStepS / h.spacingM <= 0.61
    else { throw BenchmarkFailure.invalidSamples }
    let lattice =
      r.axis == .time
      ? try AcousticOracle.SpatialLattice(c, cells: r.cells, spacingM: h.spacingM) : nil
    let impedance = c.densityKgM3 * c.soundSpeedMps
    let dx = h.spacingM
    let dt = h.timeStepS
    var sumError = 0.0
    var sumReference = 0.0
    var maxPressure = 0.0
    var maxVelocity = 0.0
    var maxAmplitude = 0.0
    var maxPhase = 0.0
    var maxSpeed = 0.0
    var maxBoundary = 0.0
    var maxEnergyDrift = 0.0
    var maxMeanDrift = 0.0
    var initialEnergy: Double?
    var initialMean: Double?
    var wallRatio: Double?
    let waveNumber = 2 * Double.pi / c.lengthM
    for frame in h.frames {
      let p = frame.pressurePa
      let u = frame.normalVelocityMps
      guard p.count == r.cells, u.count == r.cells + 1, p.allSatisfy(\.isFinite),
        u.allSatisfy(\.isFinite)
      else {
        throw BenchmarkFailure.invalidSamples
      }
      let time = Double(frame.step) * dt
      let velocityTime = time - dt / 2
      let referenceP =
        lattice?.fields(timeS: time).pressurePa
        ?? (0..<r.cells).map {
          AcousticOracle.continuum(c, xM: (Double($0) + 0.5) * dx, timeS: time).pressurePa
        }
      let referenceU =
        lattice?.fields(timeS: velocityTime).velocityMps
        ?? (0...r.cells).map {
          AcousticOracle.continuum(c, xM: Double($0) * dx, timeS: velocityTime).velocityMps
        }
      var measuredRe = 0.0
      var measuredIm = 0.0
      var referenceRe = 0.0
      var referenceIm = 0.0
      for i in 0..<r.cells {
        let difference = p[i] - referenceP[i]
        sumError += difference * difference
        sumReference += referenceP[i] * referenceP[i]
        maxPressure = max(maxPressure, abs(difference) / c.amplitudePa)
        let phase = -waveNumber * (Double(i) + 0.5) * dx
        measuredRe += p[i] * cos(phase)
        measuredIm += p[i] * sin(phase)
        referenceRe += referenceP[i] * cos(phase)
        referenceIm += referenceP[i] * sin(phase)
      }
      for i in 0...r.cells {
        maxVelocity = max(maxVelocity, abs(u[i] - referenceU[i]) * impedance / c.amplitudePa)
      }
      let referenceMagnitude = hypot(referenceRe, referenceIm)
      guard referenceMagnitude > 1e-6 * c.amplitudePa else { throw BenchmarkFailure.invalidCase }
      maxAmplitude = max(maxAmplitude, abs(hypot(measuredRe, measuredIm) / referenceMagnitude - 1))
      let phase = abs(
        atan2(
          measuredIm * referenceRe - measuredRe * referenceIm,
          measuredRe * referenceRe + measuredIm * referenceIm))
      maxPhase = max(maxPhase, phase)
      if r.axis == .space, time > 0, time < c.wallHitTimeS - c.halfWidthM / c.soundSpeedMps {
        maxSpeed = max(maxSpeed, phase / (waveNumber * c.soundSpeedMps * time))
      }
      maxBoundary = max(maxBoundary, max(abs(u[0]), abs(u[r.cells])) * impedance / c.amplitudePa)
      // Conserved leapfrog quadratic form, not instantaneous continuum energy.
      var energy =
        p.reduce(0) { $0 + $1 * $1 } * dx / (2 * c.densityKgM3 * c.soundSpeedMps * c.soundSpeedMps)
      for i in 1..<r.cells {
        let plusHalf = u[i] - dt * (p[i] - p[i - 1]) / (c.densityKgM3 * dx)
        energy += c.densityKgM3 * dx * u[i] * plusHalf / 2
      }
      let mean = p.reduce(0, +) / Double(r.cells)
      guard energy.isFinite, mean.isFinite else { throw BenchmarkFailure.invalidSamples }
      if initialEnergy == nil {
        initialEnergy = energy
        initialMean = mean
      }
      guard let e0 = initialEnergy, e0 > 0 else { throw BenchmarkFailure.invalidSamples }
      maxEnergyDrift = max(maxEnergyDrift, abs(energy / e0 - 1))
      maxMeanDrift = max(maxMeanDrift, abs(mean - initialMean!) / c.amplitudePa)
      if c.kind == .rigidWall,
        frame.step == Int((c.wallHitTimeS / c.durationS * Double(r.steps)).rounded())
      {
        // Quadratic Neumann extrapolation from the last two pressure centres.
        wallRatio = (9 * p[r.cells - 1] - p[r.cells - 2]) / (8 * c.amplitudePa)
      }
    }
    guard sumReference.isFinite, sumReference > 0, sumError.isFinite, let e0 = initialEnergy else {
      throw BenchmarkFailure.invalidSamples
    }
    let errors = AcousticErrors(
      pressureRelativeL2: sqrt(sumError / sumReference),
      maximumPressureNormalized: maxPressure, maximumVelocityNormalized: maxVelocity,
      maximumAmplitudeRelative: maxAmplitude, maximumPhaseRad: maxPhase,
      maximumSpeedRelative: maxSpeed,
      maximumDiscreteEnergyDrift: maxEnergyDrift,
      initialContinuumEnergyRelative: abs(e0 / c.referenceEnergyJPerM2 - 1),
      maximumMeanPressureDrift: maxMeanDrift, maximumBoundaryVelocityNormalized: maxBoundary,
      reflectionWallPressureRatio: wallRatio,
      returnedPulseAmplitudeRatio: c.kind == .rigidWall
        ? h.frames.last!.pressurePa.max()! / c.amplitudePa : nil)
    return Self(
      schemaVersion: 1, model: model, status: status, failureReason: nil,
      caseSpecification: c, resolution: r, environment: environment, runtimeS: runtimeS,
      reference: reference(for: r), assumptions: assumptions, history: h, errors: errors)
  }

  public var fieldCSV: String {
    guard let h = history else { return "" }
    var csv = "step,pressure_time_s,velocity_time_s,grid_kind,index,x_m,value,unit\n"
    for f in h.frames {
      let t = Double(f.step) * h.timeStepS
      for (i, p) in f.pressurePa.enumerated() {
        csv +=
          "\(f.step),\(t),\(t-h.timeStepS/2),pressure,\(i),\((Double(i)+0.5)*h.spacingM),\(p),Pa\n"
      }
      for (i, u) in f.normalVelocityMps.enumerated() {
        csv +=
          "\(f.step),\(t),\(t-h.timeStepS/2),normal_velocity,\(i),\(Double(i)*h.spacingM),\(u),m/s\n"
      }
    }
    return csv
  }
}
