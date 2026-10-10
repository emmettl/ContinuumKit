// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.

final class WaveGridIdentity: Sendable {}

/// Checked, fixed uniform-fluid topology for the masked wave update.
/// Pressure is stored divided by density; no geometry or material inference occurs here.
public struct PreparedWaveGrid: Sendable {
  // Copies retain identity; separately prepared grids require separately prepared plans.
  let identity = WaveGridIdentity()
  public let dimensions: SIMD3<Int>
  public let spacing: SIMD3<Double>
  public let soundSpeed, density, timeStep: Double
  public let cellCount: Int
  public let activeCells: [UInt8]
  /// Six N-sized blocks: -x, +x, -y, +y, -z, +z. Exactly -1 is an active link;
  /// otherwise a closed face has a finite, nonnegative timestep-specific wall term.
  public let boundaryTerms: [Float]
  public let velocityCoefficients, pressureCoefficients: SIMD3<Float>

  public init(
    dimensions: SIMD3<Int>, spacing: SIMD3<Double>,
    soundSpeed: Double, density: Double, timeStep: Double,
    activeCells: [UInt8], boundaryTerms: [Float]
  ) throws {
    guard (0..<3).allSatisfy({ dimensions[$0] >= 2 }) else {
      throw WaveError.invalidDimensions
    }
    let (plane, planeOverflow) = dimensions.x.multipliedReportingOverflow(by: dimensions.y)
    let (count, countOverflow) = plane.multipliedReportingOverflow(by: dimensions.z)
    let (faces, faceOverflow) = count.multipliedReportingOverflow(by: 6)
    let (_, bytesOverflow) = faces.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
    guard !planeOverflow, !countOverflow, !faceOverflow, !bytesOverflow,
      faces <= Int(UInt32.max)
    else { throw WaveError.dimensionOverflow }
    guard
      [soundSpeed, density, timeStep, spacing.x, spacing.y, spacing.z]
        .allSatisfy({ $0.isFinite && $0 > 0 })
    else { throw WaveError.invalidParameters }
    // Preserve RoomCAD's Double operation order and single Float conversion.
    let k = SIMD3<Float>(
      Float(timeStep / spacing.x), Float(timeStep / spacing.y), Float(timeStep / spacing.z))
    let b = SIMD3<Float>(
      Float(soundSpeed * soundSpeed * timeStep / spacing.x),
      Float(soundSpeed * soundSpeed * timeStep / spacing.y),
      Float(soundSpeed * soundSpeed * timeStep / spacing.z))
    guard (0..<3).allSatisfy({ k[$0].isFinite && k[$0] > 0 && b[$0].isFinite && b[$0] > 0 }) else {
      throw WaveError.unrepresentableCoefficients
    }
    let cflSquared = (0..<3).reduce(0.0) {
      let ratio = soundSpeed * timeStep / spacing[$1]
      return $0 + ratio * ratio
    }
    let roundedCFL = (0..<3).reduce(0.0) { $0 + Double(k[$1]) * Double(b[$1]) }
    guard cflSquared.isFinite, cflSquared < 1, roundedCFL < 1 else {
      throw WaveError.unstableTimeStep
    }
    try Self.requireCount(activeCells.count, count, "activeCells")
    try Self.requireCount(boundaryTerms.count, faces, "boundaryTerms")
    guard activeCells.allSatisfy({ $0 <= 1 }) else { throw WaveError.invalidMask }
    guard activeCells.contains(1) else { throw WaveError.emptyDomain }
    let strides = [1, dimensions.x, plane]
    for at in 0..<count {
      let xyz = SIMD3(at % dimensions.x, at / dimensions.x % dimensions.y, at / plane)
      var wall: Float = 0
      for side in 0..<6 {
        let f = boundaryTerms[side * count + at]
        if activeCells[at] == 0 {
          guard f == -1 else { throw WaveError.invalidBoundaryTerms(cell: at, face: side) }
          continue
        }
        let axis = side / 2
        let positive = side % 2 == 1
        let within = positive ? xyz[axis] + 1 < dimensions[axis] : xyz[axis] > 0
        let neighbour = at + (positive ? strides[axis] : -strides[axis])
        let live = within && activeCells[neighbour] == 1
        if live {
          guard f == -1, boundaryTerms[(side ^ 1) * count + neighbour] == -1 else {
            throw WaveError.invalidBoundaryTerms(cell: at, face: side)
          }
        } else {
          guard f.isFinite, f >= 0 else {
            throw WaveError.invalidBoundaryTerms(cell: at, face: side)
          }
          wall += f
        }
      }
      guard wall.isFinite, (1 + wall).isFinite else {
        throw WaveError.invalidWallSum(cell: at)
      }
    }
    self.dimensions = dimensions
    self.spacing = spacing
    self.soundSpeed = soundSpeed
    self.density = density
    self.timeStep = timeStep
    cellCount = count
    self.activeCells = activeCells
    self.boundaryTerms = boundaryTerms
    velocityCoefficients = k
    pressureCoefficients = b
  }

  static func requireCount(_ actual: Int, _ expected: Int, _ field: String) throws {
    guard actual == expected else {
      throw WaveError.invalidArrayLength(field: field, expected: expected, actual: actual)
    }
  }
}

public enum WaveError: Error, Equatable, Sendable {
  case invalidDimensions, dimensionOverflow, invalidParameters, unrepresentableCoefficients
  case unstableTimeStep, invalidMask, emptyDomain
  case invalidArrayLength(field: String, expected: Int, actual: Int)
  case invalidBoundaryTerms(cell: Int, face: Int)
  case invalidWallSum(cell: Int)
  case invalidInitialFields
  case closedFaceVelocity(field: Int, cell: Int)
  case invalidStepCount, stepIndexOverflow, stepClockOverflow, nonfiniteOutput, invalidatedState
}
