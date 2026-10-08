import Foundation

/// Analytic references, independent of application update kernels.
public enum AcousticOracle {
  /// D'Alembert translation plus a positive pressure image at x=L (negative velocity image).
  /// The left-wall image is zero over each case's supported time interval.
  public static func continuum(_ c: AcousticCase, xM: Double, timeS: Double)
    -> (pressurePa: Double, velocityMps: Double)
  {
    let incident = c.profile(at: xM - c.soundSpeedMps * timeS)
    let reflected = c.profile(at: 2 * c.lengthM - xM - c.soundSpeedMps * timeS)
    return (incident + reflected, (incident - reflected) / (c.densityKgM3 * c.soundSpeedMps))
  }

  public static func initialFields(
    _ c: AcousticCase, cells: Int, spacingM dx: Double, timeStepS dt: Double
  )
    -> (pressurePa: [Double], velocityMinusHalfMps: [Double])
  {
    let pressure = (0..<cells).map { c.profile(at: (Double($0) + 0.5) * dx) }
    var velocity = (0...cells).map {
      c.profile(at: Double($0) * dx) / (c.densityKgM3 * c.soundSpeedMps)
    }
    velocity[0] = 0
    velocity[cells] = 0
    // Taylor half kick binds the same p(0),u(0) on every temporal refinement.
    for i in 1..<cells {
      velocity[i] += dt * (pressure[i] - pressure[i - 1]) / (2 * c.densityKgM3 * dx)
    }
    return (pressure, velocity)
  }

  /// Exact continuous-time solution of the fixed, rigid staggered spatial lattice.
  /// Cosine/sine eigenmodes remove the spatial-error floor from temporal refinement.
  public struct SpatialLattice: Sendable {
    private let c: AcousticCase
    private let cells: Int
    private let spacingM: Double
    private let pressureCoefficients, velocityCoefficients, frequencies: [Double]

    public init(_ c: AcousticCase, cells: Int, spacingM dx: Double) throws {
      try c.validate()
      guard cells >= 2, dx.isFinite, dx > 0, abs(dx * Double(cells) / c.lengthM - 1) < 1e-6 else {
        throw BenchmarkFailure.invalidCase
      }
      self.c = c
      self.cells = cells
      spacingM = dx
      let pressure = (0..<cells).map { c.profile(at: (Double($0) + 0.5) * dx) }
      let velocity = (0...cells).map {
        c.profile(at: Double($0) * dx) / (c.densityKgM3 * c.soundSpeedMps)
      }
      var a = [Double](repeating: 0, count: cells)
      var g = a
      var omega = a
      for mode in 0..<cells {
        let k = .pi * Double(mode) / Double(cells)
        a[mode] =
          (0..<cells).reduce(0) { $0 + pressure[$1] * cos(k * (Double($1) + 0.5)) }
          * (mode == 0 ? 1 : 2) / Double(cells)
        if mode > 0 {
          g[mode] =
            (1..<cells).reduce(0) { $0 + velocity[$1] * sin(k * Double($1)) } * 2 / Double(cells)
          omega[mode] = 2 * c.soundSpeedMps / dx * sin(k / 2)
        }
      }
      pressureCoefficients = a
      velocityCoefficients = g
      frequencies = omega
    }

    public func fields(timeS t: Double) -> (pressurePa: [Double], velocityMps: [Double]) {
      var p = [Double](repeating: pressureCoefficients[0], count: cells)
      var u = [Double](repeating: 0, count: cells + 1)
      let impedance = c.densityKgM3 * c.soundSpeedMps
      for mode in 1..<cells {
        let k = .pi * Double(mode) / Double(cells)
        let phase = frequencies[mode] * t
        let a =
          pressureCoefficients[mode] * cos(phase) - impedance * velocityCoefficients[mode]
          * sin(phase)
        let g =
          velocityCoefficients[mode] * cos(phase) + pressureCoefficients[mode] / impedance
          * sin(phase)
        for i in 0..<cells { p[i] += a * cos(k * (Double(i) + 0.5)) }
        for i in 1..<cells { u[i] += g * sin(k * Double(i)) }
      }
      return (p, u)
    }
  }
}
