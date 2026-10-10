import CompressibleFlow
import Foundation
import Testing

@Suite("Independent planar ideal-gas wall reference")
struct IdealGasWallTests {
  func close(_ a: Double, _ b: Double, _ tolerance: Double = 2e-12) -> Bool {
    abs(a - b) <= tolerance * max(abs(a), abs(b), 1e-300)
  }

  @Test("Shock pressure obeys independently parameterized normal-shock states")
  func shocks() throws {
    for gamma in [1.1, 1.4, 5.0 / 3, 3] {
      for mach in [1.01, 1.3, 3, 10] {
        let rho = 1.225
        let p = 101325.0
        let c = sqrt(gamma * p / rho)
        let compression = (gamma + 1) * mach * mach / ((gamma - 1) * mach * mach + 2)
        let expected = p * (1 + 2 * gamma / (gamma + 1) * (mach * mach - 1))
        let u = mach * c * (1 - 1 / compression)
        let result = try IdealGasWallRiemann.solve(
          density: rho, pressure: p, normalVelocity: u, gamma: gamma)
        #expect(close(result.pressure, expected))
        #expect(!result.vacuum)
      }
    }
  }

  @Test("Shock states close mass, momentum, total-energy jumps and entropy increase")
  func jumpConservation() throws {
    let gamma = 1.4
    let rho = 1.7
    let p = 24000.0
    for u in [1.0, 80, 700] {
      let result = try IdealGasWallRiemann.solve(density: rho, pressure: p, normalVelocity: u)
      let ratio = result.pressure / p
      let beta = (gamma - 1) / (gamma + 1)
      let starRho = rho * (ratio + beta) / (beta * ratio + 1)
      let shock = -rho * u / (starRho - rho)
      let a = u - shock
      let b = -shock
      #expect(close(rho * a, starRho * b))
      #expect(close(p + rho * a * a, result.pressure + starRho * b * b))
      let h1 = gamma * p / ((gamma - 1) * rho) + a * a / 2
      let h2 = gamma * result.pressure / ((gamma - 1) * starRho) + b * b / 2
      #expect(close(h1, h2, 2e-10))
      #expect(log(ratio) - gamma * log(starRho / rho) >= -1e-14)
    }
  }

  @Test("Rarefaction pressure agrees with prescribed isentropic sound ratios")
  func rarefaction() throws {
    for gamma in [1.1, 1.4, 5.0 / 3] {
      let rho = 2.3
      let p = 90000.0
      let c = sqrt(gamma * p / rho)
      for fraction in [0.1, 0.5, 0.9] {
        let u = 2 * c * (fraction - 1) / (gamma - 1)
        let result = try IdealGasWallRiemann.solve(
          density: rho, pressure: p, normalVelocity: u, gamma: gamma)
        let starRho = rho * pow(fraction, 2 / (gamma - 1))
        #expect(close(result.pressure, p * pow(starRho / rho, gamma)))
        #expect(close(sqrt(gamma * result.pressure / starRho), c * fraction))
        #expect(!result.vacuum)
      }
    }
  }

  @Test("Analytic vacuum threshold and adjacent representable branches remain distinct")
  func vacuum() throws {
    let c = sqrt(1.4)
    let threshold = -2 * c / 0.4
    let inside = try IdealGasWallRiemann.solve(
      density: 1, pressure: 1, normalVelocity: threshold * 0.999)
    let outside = try IdealGasWallRiemann.solve(
      density: 1, pressure: 1, normalVelocity: threshold * 1.001)
    #expect(inside.pressure > 0 && !inside.vacuum)
    #expect(outside.pressure == 0 && outside.vacuum)
  }

  @Test("Static state and weak-wave acoustic impedance are recovered")
  func acoustic() throws {
    let rho = 1.225
    let p = 101325.0
    let c = sqrt(1.4 * p / rho)
    let u = 0.001
    let rest = try IdealGasWallRiemann.solve(density: rho, pressure: p, normalVelocity: 0)
    let a = try IdealGasWallRiemann.solve(density: rho, pressure: p, normalVelocity: u)
    let b = try IdealGasWallRiemann.solve(density: rho, pressure: p, normalVelocity: -u)
    #expect(rest.pressure == p && rest.signalSpeed == c && !rest.vacuum)
    #expect(close((a.pressure - b.pressure) / (2 * u), rho * c, 1e-8))
  }

  @Test("Independent density-pressure-speed scaling covariance")
  func scaling() throws {
    for u in [-200.0, 0, 100] {
      let base = try IdealGasWallRiemann.solve(density: 1.3, pressure: 80000, normalVelocity: u)
      let a = 3.0
      let b = 7.0
      let speed = sqrt(b / a)
      let scaled = try IdealGasWallRiemann.solve(
        density: 1.3 * a, pressure: 80000 * b, normalVelocity: u * speed)
      #expect(close(scaled.pressure, base.pressure * b))
      #expect(close(scaled.signalSpeed, base.signalSpeed * speed))
      #expect(scaled.vacuum == base.vacuum)
    }
  }

  @Test("Rarefaction approaches the isothermal limit without rounded-away increments")
  func isothermalLimit() throws {
    for gamma in [(1.0).nextUp, 1 + 1e-12, 1 + 1e-10] {
      let c = sqrt(gamma)
      let u = -0.2 * c
      let result = try IdealGasWallRiemann.solve(
        density: 1, pressure: 1, normalVelocity: u, gamma: gamma)
      #expect(close(result.pressure, exp(-0.2), 1e-9))
      #expect(!result.vacuum)
    }
  }

  @Test("Invalid incident states reject without floors")
  func invalid() {
    for rho in [0.0, -1, .infinity, .nan] {
      #expect(throws: IdealGasWallRiemann.Failure.invalidState) {
        try IdealGasWallRiemann.solve(density: rho, pressure: 1, normalVelocity: 0)
      }
    }
    for p in [0.0, -1, .infinity, .nan] {
      #expect(throws: IdealGasWallRiemann.Failure.invalidState) {
        try IdealGasWallRiemann.solve(density: 1, pressure: p, normalVelocity: 0)
      }
    }
    for gamma in [1.0, 0, .infinity, .nan] {
      #expect(throws: IdealGasWallRiemann.Failure.invalidState) {
        try IdealGasWallRiemann.solve(density: 1, pressure: 1, normalVelocity: 0, gamma: gamma)
      }
    }
    #expect(throws: IdealGasWallRiemann.Failure.invalidState) {
      try IdealGasWallRiemann.solve(density: 1, pressure: 1, normalVelocity: .nan)
    }
  }

  @Test("Overflowed sound or compression and underflowed sound reject explicitly")
  func intermediateFailures() {
    #expect(throws: IdealGasWallRiemann.Failure.unrepresentableState) {
      try IdealGasWallRiemann.solve(
        density: 1, pressure: .greatestFiniteMagnitude, normalVelocity: 0)
    }
    #expect(throws: IdealGasWallRiemann.Failure.unrepresentableState) {
      try IdealGasWallRiemann.solve(
        density: .greatestFiniteMagnitude, pressure: .leastNormalMagnitude, normalVelocity: 0)
    }
    #expect(throws: IdealGasWallRiemann.Failure.unrepresentableState) {
      try IdealGasWallRiemann.solve(
        density: 1, pressure: 1, normalVelocity: .greatestFiniteMagnitude)
    }
  }

  @Test("Underflowed non-vacuum expansion is not returned as physical vacuum")
  func pressureUnderflow() {
    let gamma = 1.001
    let c = sqrt(gamma)
    let u = -0.9 * 2 * c / (gamma - 1)
    #expect(throws: IdealGasWallRiemann.Failure.unrepresentableState) {
      try IdealGasWallRiemann.solve(density: 1, pressure: 1, normalVelocity: u, gamma: gamma)
    }
  }

  @Test("Legacy incident signal estimate is distinct from shock-front travel")
  func signalMeaning() throws {
    let rho = 1.0
    let p = 1.0
    let u = 2.0
    let gamma = 1.4
    let result = try IdealGasWallRiemann.solve(density: rho, pressure: p, normalVelocity: u)
    let ratio = result.pressure / p
    let beta = (gamma - 1) / (gamma + 1)
    let starRho = rho * (ratio + beta) / (beta * ratio + 1)
    let shock = -rho * u / (starRho - rho)
    #expect(result.signalSpeed > abs(shock))
    let retreat = try IdealGasWallRiemann.solve(density: rho, pressure: p, normalVelocity: -0.2)
    #expect(retreat.signalSpeed == 0.2 + sqrt(gamma * p / rho))
  }
}
