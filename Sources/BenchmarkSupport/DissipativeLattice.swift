import Foundation

/// Continuous-time staggered acoustic operator; state is [pressure, rho*c*interior velocity].
/// The east cell loses pressure at c/(xi*dx); a nil impedance closes that wall.
/// Matrix-exponential action uses fixed scaling and a degree-20 Taylor polynomial,
/// independently of the applications' leapfrog and trapezoidal wall update.
public struct DissipativeLattice: Sendable {
  public let cells: Int
  public let rate: Double
  public let impedance: Double?
  public init(cells: Int, speed: Double, dx: Double, impedance: Double?) throws {
    guard cells > 0, cells <= 4096, speed.isFinite, speed > 0, dx.isFinite, dx > 0,
      (speed / dx).isFinite,
      impedance.map({ $0.isFinite && $0 > 0 && (speed / dx / $0).isFinite }) ?? true
    else { throw BenchmarkFailure.invalidCase }
    self.cells = cells
    rate = speed / dx
    self.impedance = impedance
  }
  private func action(_ y: [Double]) -> [Double] {
    var z = [Double](repeating: 0, count: y.count)
    for i in 0..<cells {
      let left = i == 0 ? 0 : y[cells + i - 1]
      let right = i == cells - 1 ? 0 : y[cells + i]
      z[i] = rate * (left - right)
    }
    if let xi = impedance { z[cells - 1] -= rate / xi * y[cells - 1] }
    for i in 1..<cells { z[cells + i - 1] = rate * (y[i - 1] - y[i]) }
    return z
  }
  /// Supports a small negative time for the native velocity half-step clock.
  /// ||A*h||_infinity <= 1/2. Each polynomial's relative remainder is bounded by
  /// exp(1/2)*(1/2)^21/21! < 1.6e-26 (roundoff is the practical limit).
  public func evolve(_ initial: [Double], time: Double) throws -> [Double] {
    guard initial.count == 2 * cells - 1, initial.allSatisfy(\.isFinite), time.isFinite else {
      throw BenchmarkFailure.invalidSamples
    }
    let extent = abs(time) * rate * (2 + (impedance.map { 1 / $0 } ?? 0))
    guard extent.isFinite, extent <= 500_000 else { throw BenchmarkFailure.invalidSamples }
    let subdivisions = max(1, Int(ceil(2 * extent)))
    let h = time / Double(subdivisions)
    var y = initial
    for _ in 0..<subdivisions {
      var term = y
      var sum = y
      for k in 1...20 {
        let derivative = action(term)
        for i in y.indices {
          term[i] = derivative[i] * (h / Double(k))
          sum[i] += term[i]
        }
      }
      guard sum.allSatisfy(\.isFinite) else { throw BenchmarkFailure.invalidSamples }
      y = sum
    }
    return y
  }
}

extension BoundaryOracle {
  /// Fixed spatial operator removes spatial truncation from an impedance time-refinement test.
  public static func temporalHistory(
    _ c: BoundaryAcousticCase, _ r: BoundaryResolution,
    dx: Double? = nil, dy: Double? = nil, dt: Double? = nil
  ) throws -> BoundaryHistory {
    try c.validate()
    guard c.kind == .impedancePulse, r.nx >= 2, r.ny >= 2, r.steps > 0 else {
      throw BenchmarkFailure.invalidCase
    }
    let dx = dx ?? c.lengthX / Double(r.nx)
    let dy = dy ?? c.lengthY / Double(r.ny)
    let dt = dt ?? c.duration / Double(r.steps)
    guard dy.isFinite, dy > 0, dt.isFinite, dt > 0 else { throw BenchmarkFailure.invalidCase }
    let lattice = try DissipativeLattice(
      cells: r.nx, speed: c.speed, dx: dx, impedance: c.impedance)
    let initial =
      (0..<r.nx).map { c.pulse((Double($0) + 0.5) * dx) }
      + (1..<r.nx).map { c.pulse(Double($0) * dx) }
    let scale = dx * dy * Double(r.ny) / (2 * c.density * c.speed * c.speed)
    let e0 = initial.reduce(0) { $0 + $1 * $1 } * scale
    var current = initial
    var clock = 0.0
    var frames: [BoundaryFrame] = []
    var previousLoss = 0.0
    for step in r.captures(c) {
      let t = Double(step) * dt
      // Evolve from the preceding capture, then backwards half a step for velocity.
      current = try lattice.evolve(current, time: t - clock)
      clock = t
      let half = try lattice.evolve(current, time: -dt / 2)
      let rowP = Array(current.prefix(r.nx))
      let rowU =
        [0] + half.dropFirst(r.nx).map { $0 / (c.density * c.speed) }
        + [half[r.nx - 1] / (c.density * c.speed * c.impedance!)]
      let loss = e0 - current.reduce(0) { $0 + $1 * $1 } * scale
      guard loss >= previousLoss - 1e-11 * e0 else { throw BenchmarkFailure.invalidSamples }
      // Energy subtraction before the pulse reaches the wall has roundoff-sized jitter.
      previousLoss = max(previousLoss, loss)
      frames.append(
        BoundaryFrame(
          step: step, p: (0..<r.ny).flatMap { _ in rowP },
          u: (0..<r.ny).flatMap { _ in rowU },
          v: Array(repeating: 0, count: r.nx * (r.ny + 1)), dissipation: previousLoss))
    }
    return BoundaryHistory(dx: dx, dy: dy, dt: dt, frames: frames)
  }
}
