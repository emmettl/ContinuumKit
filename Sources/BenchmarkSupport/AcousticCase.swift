import Foundation

/// Plane pulse, uniform across transverse axes. Pressure is a perturbation in Pa.
public struct AcousticCase: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case travellingPulse, rigidWall }
  public let version: Int
  public let id: String
  public let kind: Kind
  public let lengthM, densityKgM3, soundSpeedMps, amplitudePa, centreM, halfWidthM,
    durationS: Double

  public init(
    id: String, kind: Kind, lengthM: Double = 0.25, densityKgM3: Double = 1.25,
    soundSpeedMps: Double = 320, amplitudePa: Double = 1, centreM: Double = 0.075,
    halfWidthM: Double = 0.025, durationS: Double
  ) throws {
    version = 1
    self.id = id
    self.kind = kind
    self.lengthM = lengthM
    self.densityKgM3 = densityKgM3
    self.soundSpeedMps = soundSpeedMps
    self.amplitudePa = amplitudePa
    self.centreM = centreM
    self.halfWidthM = halfWidthM
    self.durationS = durationS
    try validate()
  }

  public func validate() throws {
    guard version == 1, !id.isEmpty,
      [lengthM, densityKgM3, soundSpeedMps, amplitudePa, centreM, halfWidthM, durationS]
        .allSatisfy({ $0.isFinite && $0 > 0 }),
      centreM > halfWidthM, centreM + halfWidthM < lengthM,
      (densityKgM3 * soundSpeedMps * soundSpeedMps).isFinite,
      referenceEnergyJPerM2.isFinite, referenceEnergyJPerM2 > 0,
      (amplitudePa / (densityKgM3 * soundSpeedMps)).isFinite,
      soundSpeedMps * durationS < 2 * lengthM - centreM - halfWidthM
    else { throw BenchmarkFailure.invalidCase }
    if kind == .travellingPulse {
      guard centreM + halfWidthM + soundSpeedMps * durationS < lengthM else {
        throw BenchmarkFailure.invalidCase
      }
    } else {
      guard soundSpeedMps * durationS > lengthM - centreM + halfWidthM else {
        throw BenchmarkFailure.invalidCase
      }
    }
  }

  /// C³ compact pulse; the support does not touch either wall at initialization.
  public func profile(at x: Double) -> Double {
    let coordinate = (x - centreM) / halfWidthM
    guard abs(coordinate) < 1 else { return 0 }
    let value = cos(.pi * coordinate / 2)
    return amplitudePa * value * value * value * value
  }

  public var wallHitTimeS: Double { (lengthM - centreM) / soundSpeedMps }
  /// Exact continuum energy per unit transverse area (J/m²), integral of cos⁸.
  public var referenceEnergyJPerM2: Double {
    amplitudePa * amplitudePa * halfWidthM * 35 / (64 * densityKgM3 * soundSpeedMps * soundSpeedMps)
  }
  public static func standard() throws -> [Self] {
    try [
      Self(id: "acoustic-travelling-pulse", kind: .travellingPulse, durationS: 0.1 / 320),
      Self(id: "acoustic-rigid-wall", kind: .rigidWall, durationS: 0.275 / 320),
    ]
  }
}

public struct AcousticResolution: Codable, Equatable, Sendable {
  public enum Axis: String, Codable, Sendable { case space, time }
  public let axis: Axis
  public let cells, steps: Int
  public init(axis: Axis, cells: Int, steps: Int) {
    self.axis = axis
    self.cells = cells
    self.steps = steps
  }
  public static func standard(for c: AcousticCase) -> [Self] {
    let fineSteps = Int(ceil(c.soundSpeedMps * c.durationS * 384 / (0.3 * c.lengthM)))
    return [96, 192, 384].map { Self(axis: .space, cells: $0, steps: fineSteps) }
      + [0.6, 0.3, 0.15].map {
        Self(
          axis: .time, cells: 192,
          steps: Int(ceil(c.soundSpeedMps * c.durationS * 192 / ($0 * c.lengthM))))
      }
  }
  public func captureSteps(for c: AcousticCase) -> [Int] {
    var captures = (0...24).map { Int((Double($0) * Double(steps) / 24).rounded()) }
    if c.kind == .rigidWall {
      captures.append(Int((c.wallHitTimeS / c.durationS * Double(steps)).rounded()))
    }
    return Array(Set(captures)).sorted()
  }
}
