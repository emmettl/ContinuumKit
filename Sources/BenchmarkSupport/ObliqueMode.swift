import Foundation

/// Complex values used by the independently specified modal reference, not a production solver API.
public struct ObliqueComplex: Codable, Equatable, Sendable {
  public let real, imag: Double
  public init(_ real: Double, _ imag: Double = 0) {
    self.real = real
    self.imag = imag
  }
  public var magnitude: Double { hypot(real, imag) }
  static let i = Self(0, 1)
  static func + (a: Self, b: Self) -> Self { Self(a.real + b.real, a.imag + b.imag) }
  static func - (a: Self, b: Self) -> Self { Self(a.real - b.real, a.imag - b.imag) }
  static prefix func - (a: Self) -> Self { Self(-a.real, -a.imag) }
  static func * (a: Self, b: Self) -> Self {
    Self(a.real * b.real - a.imag * b.imag, a.real * b.imag + a.imag * b.real)
  }
  static func / (a: Self, b: Self) -> Self {
    let d = b.real * b.real + b.imag * b.imag
    return Self((a.real * b.real + a.imag * b.imag) / d, (a.imag * b.real - a.real * b.imag) / d)
  }
  var exp: Self {
    Self(Foundation.exp(real) * Foundation.cos(imag), Foundation.exp(real) * Foundation.sin(imag))
  }
  var sin: Self { Self(Foundation.sin(real) * cosh(imag), Foundation.cos(real) * sinh(imag)) }
  var cos: Self { Self(Foundation.cos(real) * cosh(imag), -Foundation.sin(real) * sinh(imag)) }
  var sqrt: Self {
    Self(
      Foundation.sqrt(max(0, (magnitude + real) / 2)),
      (imag < 0 ? -1.0 : 1.0) * Foundation.sqrt(max(0, (magnitude - real) / 2)))
  }
}
public struct ObliqueModeCase: Codable, Equatable, Sendable {
  public let version: Int
  public let id: String
  public let impedance: Double
  public let lengthX, lengthY, density, speed, amplitude: Double
  public init(id: String, impedance: Double) throws {
    version = 1
    self.id = id
    self.impedance = impedance
    lengthX = 0.25
    lengthY = 0.125
    density = 1.25
    speed = 320
    amplitude = 1
    try validate()
  }
  public func validate() throws {
    guard version == 1, !id.isEmpty, [0.5, 3].contains(impedance), lengthX == 0.25,
      lengthY == 0.125, density == 1.25, speed == 320, amplitude == 1
    else { throw BenchmarkFailure.invalidCase }
  }
  public static func standard() throws -> [Self] {
    try [Self(id: "positive-oblique", impedance: 3), Self(id: "inverted-oblique", impedance: 0.5)]
  }
}
public struct ObliqueModeReference: Sendable {
  public let specification: ObliqueModeCase
  public let kx, rate, reflection: ObliqueComplex
  public let ky, normalization, duration: Double
  public init(_ c: ObliqueModeCase) throws {
    try c.validate()
    specification = c
    ky = .pi / c.lengthY
    let b = ky * c.lengthX
    var z =
      c.impedance == 3 ? ObliqueComplex(2 * Double.pi, -0.5) : ObliqueComplex(2.5 * Double.pi, -0.4)
    for _ in 0..<40 {
      let q = (z * z + ObliqueComplex(b * b)).sqrt
      let tangent = z.sin / z.cos
      let f = z * tangent + ObliqueComplex.i * q / ObliqueComplex(c.impedance)
      let derivative =
        tangent + z / (z.cos * z.cos) + ObliqueComplex.i * z / (ObliqueComplex(c.impedance) * q)
      let change = f / derivative
      z = z - change
      guard z.real.isFinite, z.imag.isFinite else { throw BenchmarkFailure.invalidSamples }
      if change.magnitude < 2e-14 { break }
    }
    let q = (z * z + ObliqueComplex(b * b)).sqrt
    let residual = z * (z.sin / z.cos) + ObliqueComplex.i * q / ObliqueComplex(c.impedance)
    guard residual.magnitude < 1e-11, z.real > 0, z.imag < 0 else {
      throw BenchmarkFailure.invalidSamples
    }
    kx = z / ObliqueComplex(c.lengthX)
    rate = -ObliqueComplex.i * (kx * kx + ObliqueComplex(ky * ky)).sqrt * ObliqueComplex(c.speed)
    guard rate.real < 0, rate.imag < 0 else { throw BenchmarkFailure.invalidSamples }
    duration = 2 * Double.pi / abs(rate.imag)
    normalization = cosh(kx.imag * c.lengthX)
    let admittance = ObliqueComplex(c.impedance) * kx / (kx * kx + ObliqueComplex(ky * ky)).sqrt
    reflection = (admittance - ObliqueComplex(1)) / (admittance + ObliqueComplex(1))
  }
  public func state(x: Double, y: Double, time: Double) -> (p: Double, u: Double, v: Double) {
    let c = specification
    let q = (rate * ObliqueComplex(time)).exp / ObliqueComplex(normalization)
    let cx = (kx * ObliqueComplex(x)).cos
    let sx = (kx * ObliqueComplex(x)).sin
    return (
      (q * cx).real * cos(ky * y),
      (q * kx * sx / (ObliqueComplex(c.density) * rate)).real * cos(ky * y),
      (q * ObliqueComplex(ky) * cx / (ObliqueComplex(c.density) * rate)).real * sin(ky * y)
    )
  }
  public func energy(time: Double) -> Double {
    let c = specification
    let L = c.lengthX
    let a = kx.real
    let b = kx.imag
    let h = sinh(2 * b * L) / (4 * b)
    let s = sin(2 * a * L) / (4 * a)
    let complexIntegral = (kx * ObliqueComplex(2 * L)).sin / (ObliqueComplex(4) * kx)
    let ic = ObliqueComplex(L / 2) + complexIntegral
    let isn = ObliqueComplex(L / 2) - complexIntegral
    let q = (rate * ObliqueComplex(time)).exp / ObliqueComplex(normalization)
    func integral(_ coefficient: ObliqueComplex, _ norm: Double, _ square: ObliqueComplex) -> Double
    {
      (coefficient.magnitude * coefficient.magnitude * norm
        + (coefficient * coefficient * square).real) / 2
    }
    let p = integral(q, h + s, ic) / (c.density * c.speed * c.speed)
    let u = c.density * integral(q * kx / (ObliqueComplex(c.density) * rate), h - s, isn)
    let v =
      c.density * integral(q * ObliqueComplex(ky) / (ObliqueComplex(c.density) * rate), h + s, ic)
    return c.lengthY * (p + u + v) / 4
  }
  public func dissipated(time: Double) -> Double {
    let c = specification
    let wall = (kx * ObliqueComplex(c.lengthX)).cos / ObliqueComplex(normalization)
    let first = wall.magnitude * wall.magnitude * expm1(2 * rate.real * time) / (2 * rate.real)
    let second =
      (wall * wall * ((rate * ObliqueComplex(2 * time)).exp - ObliqueComplex(1))
      / (ObliqueComplex(2) * rate)).real
    return max(0, c.lengthY * (first + second) / (4 * c.density * c.speed * c.impedance))
  }
}

public struct ObliqueModeResolution: Codable, Equatable, Sendable {
  public let axis: String
  public let nx, ny, steps: Int
  public init(axis: String, nx: Int, ny: Int, steps: Int) {
    self.axis = axis
    self.nx = nx
    self.ny = ny
    self.steps = steps
  }
  public var captures: [Int] { (0...8).map { $0 * steps / 8 } }
  public static func standard(_ c: ObliqueModeCase) throws -> [Self] {
    let reference = try ObliqueModeReference(c)
    func count(_ n: Int, _ courant: Double) -> Int {
      let dx = c.lengthX / Double(n)
      let dy = c.lengthY / Double(n / 2)
      return 8 * Int(ceil(reference.duration * c.speed * hypot(1 / dx, 1 / dy) / courant / 8))
    }
    return [96, 192, 384].map { Self(axis: "space", nx: $0, ny: $0 / 2, steps: count(384, 0.25)) }
      + [0.7, 0.35, 0.175].map { Self(axis: "time", nx: 64, ny: 32, steps: count(64, $0)) }
  }
}

/// Independent continuous-time reduced spatial operator for one transverse cosine mode.
/// State [p, rho*c*ux interior, rho*c*uy amplitude]; no application time-step code.
struct ObliqueLattice {
  let n: Int, c, dx, xi, qy: Double
  func action(_ y: [Double]) -> [Double] {
    var z = [Double](repeating: 0, count: 3 * n - 1)
    for i in 0..<n {
      let left = i == 0 ? 0 : y[n + i - 1]
      let right = i == n - 1 ? 0 : y[n + i]
      z[i] = c / dx * (left - right) - c * qy * y[2 * n - 1 + i]
      z[2 * n - 1 + i] = c * qy * y[i]
    }
    z[n - 1] -= c / (xi * dx) * y[n - 1]
    for i in 1..<n { z[n + i - 1] = c / dx * (y[i - 1] - y[i]) }
    return z
  }
  func evolve(_ initial: [Double], time: Double) throws -> [Double] {
    guard n >= 2, n <= 512, initial.count == 3 * n - 1, initial.allSatisfy(\.isFinite),
      time.isFinite, [c, dx, xi, qy].allSatisfy({ $0.isFinite && $0 > 0 })
    else { throw BenchmarkFailure.invalidSamples }
    let extent = abs(time) * (c / dx * (2 + 1 / xi) + c * qy)
    guard extent.isFinite, extent < 500_000 else { throw BenchmarkFailure.invalidSamples }
    let count = max(1, Int(ceil(2 * extent)))
    let h = time / Double(count)
    var y = initial
    for _ in 0..<count {
      var term = y
      var sum = y
      for degree in 1...20 {
        let derivative = action(term)
        for i in y.indices {
          term[i] = derivative[i] * (h / Double(degree))
          sum[i] += term[i]
        }
      }
      guard sum.allSatisfy(\.isFinite) else { throw BenchmarkFailure.invalidSamples }
      y = sum
    }
    return y
  }
}
public enum ObliqueModeOracle {
  public static func initial(
    _ c: ObliqueModeCase, _ r: ObliqueModeResolution, dx: Double, dy: Double, dt: Double
  ) throws -> BoundaryFrame {
    let ref = try ObliqueModeReference(c)
    let p = (0..<r.nx * r.ny).map {
      ref.state(x: (Double($0 % r.nx) + 0.5) * dx, y: (Double($0 / r.nx) + 0.5) * dy, time: 0).p
    }
    var u = [Double](repeating: 0, count: (r.nx + 1) * r.ny)
    var v = [Double](repeating: 0, count: r.nx * (r.ny + 1))
    for j in 0..<r.ny {
      for i in 1..<r.nx {
        u[j * (r.nx + 1) + i] =
          ref.state(x: Double(i) * dx, y: (Double(j) + 0.5) * dy, time: 0).u
          + dt * (p[j * r.nx + i] - p[j * r.nx + i - 1]) / (2 * c.density * dx)
      }
    }
    for j in 1..<r.ny {
      for i in 0..<r.nx {
        v[j * r.nx + i] =
          ref.state(x: (Double(i) + 0.5) * dx, y: Double(j) * dy, time: 0).v
          + dt * (p[j * r.nx + i] - p[(j - 1) * r.nx + i]) / (2 * c.density * dy)
      }
    }
    // The implicit wall has no exterior buffer. Initialize its negative-half-clock
    // flux by Taylor expanding the same fixed spatial operator from the common physical state.
    for j in 0..<r.ny {
      let x = (Double(r.nx) - 0.5) * dx
      let y = (Double(j) + 0.5) * dy
      let left = ref.state(x: Double(r.nx - 1) * dx, y: y, time: 0).u
      let south = j == 0 ? 0 : ref.state(x: x, y: Double(j) * dy, time: 0).v
      let north = j == r.ny - 1 ? 0 : ref.state(x: x, y: Double(j + 1) * dy, time: 0).v
      let p0 = p[j * r.nx + r.nx - 1]
      let derivative =
        -c.density * c.speed * c.speed
        * ((p0 / (c.density * c.speed * c.impedance) - left) / dx + (north - south) / dy)
      u[j * (r.nx + 1) + r.nx] = (p0 - dt * derivative / 2) / (c.density * c.speed * c.impedance)
    }
    return BoundaryFrame(step: 0, p: p, u: u, v: v)
  }
  public static func history(
    _ c: ObliqueModeCase, _ r: ObliqueModeResolution,
    dx: Double? = nil, dy: Double? = nil, dt: Double? = nil
  ) throws -> BoundaryHistory {
    let ref = try ObliqueModeReference(c)
    guard r.nx >= 2, r.nx <= 512, r.ny >= 2, r.ny <= 256, r.steps > 0,
      ["space", "time"].contains(r.axis)
    else { throw BenchmarkFailure.invalidCase }
    let dx = dx ?? c.lengthX / Double(r.nx)
    let dy = dy ?? c.lengthY / Double(r.ny)
    let dt = dt ?? ref.duration / Double(r.steps)
    guard [dx, dy, dt].allSatisfy({ $0.isFinite && $0 > 0 }) else {
      throw BenchmarkFailure.invalidSamples
    }
    let yc = (0..<r.ny).map { cos(ref.ky * (Double($0) + 0.5) * dy) }
    let yf = (0...r.ny).map { sin(ref.ky * Double($0) * dy) }
    let lattice = ObliqueLattice(
      n: r.nx, c: c.speed, dx: dx, xi: c.impedance, qy: 2 * sin(ref.ky * dy / 2) / dy)
    let initial =
      (0..<r.nx).map { ref.state(x: (Double($0) + 0.5) * dx, y: 0, time: 0).p }
      + (1..<r.nx).map { ref.state(x: Double($0) * dx, y: 0, time: 0).u * c.density * c.speed }
      + (0..<r.nx).map {
        ref.state(x: (Double($0) + 0.5) * dx, y: c.lengthY / 2, time: 0).v * c.density * c.speed
      }
    let energyScale = dx * dy * Double(r.ny) / (4 * c.density * c.speed * c.speed)
    let initialEnergy = initial.reduce(0) { $0 + $1 * $1 } * energyScale
    var state = initial
    var clock = 0.0
    var lastLoss = 0.0
    var frames: [BoundaryFrame] = []
    for step in r.captures {
      let t = Double(step) * dt
      let px: [Double]
      let ux: [Double]
      let vy: [Double]
      let loss: Double
      if r.axis == "time" {
        state = try lattice.evolve(state, time: t - clock)
        clock = t
        let half = try lattice.evolve(state, time: -dt / 2)
        px = Array(state.prefix(r.nx))
        ux =
          [0] + Array(half[r.nx..<2 * r.nx - 1]).map { $0 / (c.density * c.speed) }
          + [half[r.nx - 1] / (c.density * c.speed * c.impedance)]
        vy = Array(half[(2 * r.nx - 1)...]).map { $0 / (c.density * c.speed) }
        let value = initialEnergy - state.reduce(0) { $0 + $1 * $1 } * energyScale
        guard value >= lastLoss - 1e-11 * initialEnergy else {
          throw BenchmarkFailure.invalidSamples
        }
        loss = max(lastLoss, value)
        lastLoss = loss
      } else {
        px = (0..<r.nx).map { ref.state(x: (Double($0) + 0.5) * dx, y: 0, time: t).p }
        ux = (0...r.nx).map { ref.state(x: Double($0) * dx, y: 0, time: t - dt / 2).u }
        vy = (0..<r.nx).map {
          ref.state(x: (Double($0) + 0.5) * dx, y: c.lengthY / 2, time: t - dt / 2).v
        }
        loss = ref.dissipated(time: t)
      }
      frames.append(
        BoundaryFrame(
          step: step,
          p: (0..<r.nx * r.ny).map { px[$0 % r.nx] * yc[$0 / r.nx] },
          u: (0..<(r.nx + 1) * r.ny).map { ux[$0 % (r.nx + 1)] * yc[$0 / (r.nx + 1)] },
          v: (0..<r.nx * (r.ny + 1)).map { vy[$0 % r.nx] * yf[$0 / r.nx] }, dissipation: loss))
    }
    return BoundaryHistory(dx: dx, dy: dy, dt: dt, frames: frames)
  }
}
