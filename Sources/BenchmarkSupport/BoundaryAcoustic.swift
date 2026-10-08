import Foundation

/// Additional contracts: mixed-axis rigid-box modes and normal-incidence real impedance.
public struct BoundaryAcousticCase: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case obliqueMode, impedancePulse }
  public let version: Int
  public let id: String
  public let kind: Kind
  public let modeX, modeY: Int
  public let impedance: Double?
  public let lengthX, lengthY, density, speed, amplitude: Double
  public init(id: String, kind: Kind, modeX: Int = 0, modeY: Int = 0, impedance: Double? = nil)
    throws
  {
    lengthX = 0.25
    lengthY = 0.125
    density = 1.25
    speed = 320
    amplitude = 1
    version = 1
    self.id = id
    self.kind = kind
    self.modeX = modeX
    self.modeY = modeY
    self.impedance = impedance
    try validate()
  }
  public func validate() throws {
    guard version == 1, !id.isEmpty, lengthX == 0.25, lengthY == 0.125, density == 1.25,
      speed == 320, amplitude == 1
    else { throw BenchmarkFailure.invalidCase }
    if kind == .obliqueMode {
      guard (1...6).contains(modeX), (1...3).contains(modeY), impedance == nil else {
        throw BenchmarkFailure.invalidCase
      }
    } else {
      guard modeX == 0, modeY == 0, let xi = impedance, xi.isFinite, xi > 0 else {
        throw BenchmarkFailure.invalidCase
      }
    }
  }
  public var kx: Double { .pi * Double(modeX) / lengthX }
  public var ky: Double { .pi * Double(modeY) / lengthY }
  public var omega: Double { speed * hypot(kx, ky) }
  public var duration: Double { kind == .obliqueMode ? 2 * .pi / omega : 0.275 / speed }
  public var reflection: Double { impedance.map { ($0 - 1) / ($0 + 1) } ?? 1 }
  public var energy: Double {
    kind == .obliqueMode
      ? amplitude * amplitude * lengthX * lengthY / (8 * density * speed * speed)
      : 35 * 0.025 * lengthY / (64 * density * speed * speed)
  }
  public func pulse(_ x: Double) -> Double {
    let z = (x - 0.075) / 0.025
    guard abs(z) < 1 else { return 0 }
    let a = cos(.pi * z / 2)
    return a * a * a * a
  }
  public func state(x: Double, y: Double, t: Double, dx: Double? = nil, dy: Double? = nil) -> (
    p: Double, u: Double, v: Double
  ) {
    if kind == .impedancePulse {
      let a = pulse(x - speed * t)
      let b = reflection * pulse(2 * lengthX - x - speed * t)
      return (a + b, (a - b) / (density * speed), 0)
    }
    let qx = dx.map { 2 * sin(kx * $0 / 2) / $0 } ?? kx
    let qy = dy.map { 2 * sin(ky * $0 / 2) / $0 } ?? ky
    let q = hypot(qx, qy)
    let phase = speed * q * t
    return (
      amplitude * cos(kx * x) * cos(ky * y) * cos(phase),
      amplitude / (density * speed) * qx / q * sin(kx * x) * cos(ky * y) * sin(phase),
      amplitude / (density * speed) * qy / q * cos(kx * x) * sin(ky * y) * sin(phase)
    )
  }
  public static func standard() throws -> [Self] {
    try [
      Self(id: "mode-45-degrees", kind: .obliqueMode, modeX: 4, modeY: 2),
      Self(id: "mode-26-degrees", kind: .obliqueMode, modeX: 4, modeY: 1),
      Self(id: "impedance-matched", kind: .impedancePulse, impedance: 1),
      Self(id: "impedance-positive", kind: .impedancePulse, impedance: 3),
      Self(id: "impedance-inverted", kind: .impedancePulse, impedance: 0.5),
    ]
  }
}

public struct BoundaryResolution: Codable, Equatable, Sendable {
  public let axis: String
  public let nx, ny, steps: Int
  public init(axis: String, nx: Int, ny: Int, steps: Int) {
    self.axis = axis
    self.nx = nx
    self.ny = ny
    self.steps = steps
  }
  public static func standard(_ c: BoundaryAcousticCase) -> [Self] {
    func count(_ n: Int, _ courant: Double) -> Int {
      let interval = c.kind == .obliqueMode ? 8 : 24
      return Int(ceil(c.duration * c.speed * Double(n) / (courant * c.lengthX) / Double(interval)))
        * interval
    }
    if c.kind == .obliqueMode {
      let fine = count(192, 0.25)
      return [48, 96, 192].map { Self(axis: "space", nx: $0, ny: $0 / 2, steps: fine) }
        + [0.6, 0.3, 0.15].map { Self(axis: "time", nx: 96, ny: 48, steps: count(96, $0)) }
    }
    let fine = count(512, 0.25)
    return [128, 256, 512].map { Self(axis: "space", nx: $0, ny: 4, steps: fine) }
      + [Self(axis: "time-sensitivity", nx: 512, ny: 4, steps: 2 * fine)]
  }
  public func captures(_ c: BoundaryAcousticCase) -> [Int] {
    let intervals = c.kind == .obliqueMode ? 8 : 24
    var values = (0...intervals).map { $0 * steps / intervals }
    if c.kind == .impedancePulse {
      values.append(Int(((c.lengthX - 0.075) / c.speed / c.duration * Double(steps)).rounded()))
    }
    return Array(Set(values)).sorted()
  }
}
public struct BoundaryFrame: Codable, Sendable {
  public let step: Int
  public let p, u, v: [Double]
  public let dissipation: Double
  public init(step: Int, p: [Double], u: [Double], v: [Double], dissipation: Double = 0) {
    self.step = step
    self.p = p
    self.u = u
    self.v = v
    self.dissipation = dissipation
  }
}
public struct BoundaryHistory: Codable, Sendable {
  public let dx, dy, dt: Double
  public let frames: [BoundaryFrame]
  public init(dx: Double, dy: Double, dt: Double, frames: [BoundaryFrame]) {
    self.dx = dx
    self.dy = dy
    self.dt = dt
    self.frames = frames
  }
}
public enum BoundaryOracle {
  public static func initial(
    _ c: BoundaryAcousticCase, _ r: BoundaryResolution, dx: Double, dy: Double, dt: Double
  ) -> BoundaryFrame {
    let p = (0..<r.nx * r.ny).map {
      c.state(x: (Double($0 % r.nx) + 0.5) * dx, y: (Double($0 / r.nx) + 0.5) * dy, t: 0).p
    }
    var u = [Double](repeating: 0, count: (r.nx + 1) * r.ny)
    var v = [Double](repeating: 0, count: r.nx * (r.ny + 1))
    for j in 0..<r.ny {
      for i in 1..<r.nx {
        u[j * (r.nx + 1) + i] =
          c.state(x: Double(i) * dx, y: (Double(j) + 0.5) * dy, t: 0).u + dt
          * (p[j * r.nx + i] - p[j * r.nx + i - 1]) / (2 * c.density * dx)
      }
    }
    for j in 1..<r.ny {
      for i in 0..<r.nx {
        v[j * r.nx + i] =
          c.state(x: (Double(i) + 0.5) * dx, y: Double(j) * dy, t: 0).v + dt
          * (p[j * r.nx + i] - p[(j - 1) * r.nx + i]) / (2 * c.density * dy)
      }
    }
    return BoundaryFrame(step: 0, p: p, u: u, v: v)
  }
  public static func dissipated(_ c: BoundaryAcousticCase, t: Double) -> Double {
    guard c.kind == .impedancePulse else { return 0 }
    func integral(_ x: Double) -> Double {
      let z = min(max((x - 0.075) / 0.025, -1), 1)
      return 0.025 / 128
        * (35 * z + 56 * sin(.pi * z) / Double.pi + 28 * sin(2 * .pi * z) / (2 * .pi) + 8
          * sin(3 * .pi * z) / (3 * .pi) + sin(4 * .pi * z) / (4 * .pi))
    }
    return (1 - c.reflection * c.reflection)
      * (integral(c.lengthX) - integral(c.lengthX - c.speed * t)) / (c.density * c.speed * c.speed)
      * c.lengthY
  }
  public static func history(_ c: BoundaryAcousticCase, _ r: BoundaryResolution) -> BoundaryHistory
  {
    let dx = c.lengthX / Double(r.nx)
    let dy = c.lengthY / Double(r.ny)
    let dt = c.duration / Double(r.steps)
    let frames = r.captures(c).map { step in
      let t = Double(step) * dt
      let half = t - dt / 2
      func s(_ x: Double, _ y: Double, _ time: Double) -> (p: Double, u: Double, v: Double) {
        c.state(
          x: x, y: y, t: time, dx: r.axis == "time" ? dx : nil, dy: r.axis == "time" ? dy : nil)
      }
      return BoundaryFrame(
        step: step,
        p: (0..<r.nx * r.ny).map {
          s((Double($0 % r.nx) + 0.5) * dx, (Double($0 / r.nx) + 0.5) * dy, t).p
        },
        u: (0..<(r.nx + 1) * r.ny).map {
          s(Double($0 % (r.nx + 1)) * dx, (Double($0 / (r.nx + 1)) + 0.5) * dy, half).u
        },
        v: (0..<r.nx * (r.ny + 1)).map {
          s((Double($0 % r.nx) + 0.5) * dx, Double($0 / r.nx) * dy, half).v
        },
        dissipation: dissipated(c, t: t))
    }
    return BoundaryHistory(dx: dx, dy: dy, dt: dt, frames: frames)
  }
}
