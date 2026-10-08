import Foundation

/// Standing modes in a uniform rigid 0.25 x 0.125 x 0.125 metre box.
public struct RigidModeCase: Codable, Equatable, Sendable {
  public let version: Int
  public let id: String
  public let modes: [Int]
  public let anisotropicGrid: Bool
  public let lengths: [Double]
  public let density, speed, amplitude: Double
  public init(id: String, modes: [Int], anisotropicGrid: Bool) throws {
    version = 1
    self.id = id
    self.modes = modes
    self.anisotropicGrid = anisotropicGrid
    lengths = [0.25, 0.125, 0.125]
    density = 1.25
    speed = 320
    amplitude = 1
    try validate()
  }
  public func validate() throws {
    guard version == 1, !id.isEmpty, modes.count == 3,
      modes.allSatisfy({ (1...3).contains($0) }), lengths == [0.25, 0.125, 0.125],
      density == 1.25, speed == 320, amplitude == 1
    else { throw BenchmarkFailure.invalidCase }
  }
  public var waveNumbers: [Double] { zip(modes, lengths).map { .pi * Double($0) / $1 } }
  public var duration: Double { 2 * .pi / (speed * sqrt(waveNumbers.reduce(0) { $0 + $1 * $1 })) }
  public var energy: Double {
    amplitude * amplitude * lengths.reduce(1, *) / (16 * density * speed * speed)
  }
  public func state(_ xyz: [Double], time: Double, spacing: [Double]? = nil) -> [Double] {
    let k = waveNumbers
    let q = (0..<3).map { axis in
      spacing.map { 2 * sin(k[axis] * $0[axis] / 2) / $0[axis] } ?? k[axis]
    }
    let norm = sqrt(q.reduce(0) { $0 + $1 * $1 })
    let phase = speed * norm * time
    let cs = (0..<3).map { cos(k[$0] * xyz[$0]) }
    let sn = (0..<3).map { sin(k[$0] * xyz[$0]) }
    return [amplitude * cs.reduce(1, *) * cos(phase)]
      + (0..<3).map { axis in
        amplitude / (density * speed) * q[axis] / norm * sn[axis]
          * cs[(axis + 1) % 3] * cs[(axis + 2) % 3] * sin(phase)
      }
  }
  public static func standard() throws -> [Self] {
    try [
      Self(id: "body-diagonal", modes: [2, 1, 1], anisotropicGrid: false),
      Self(id: "anisotropic-grid", modes: [1, 1, 1], anisotropicGrid: true),
    ]
  }
}

public struct RigidModeResolution: Codable, Equatable, Sendable {
  public let axis: String
  public let nx, ny, nz, steps: Int
  public init(axis: String, nx: Int, ny: Int, nz: Int, steps: Int) {
    self.axis = axis
    self.nx = nx
    self.ny = ny
    self.nz = nz
    self.steps = steps
  }
  public var dimensions: [Int] { [nx, ny, nz] }
  public static func standard(_ c: RigidModeCase) -> [Self] {
    func count(_ n: Int, _ courant: Double) -> Int {
      let dims = [n, n / 2, c.anisotropicGrid ? n / 4 : n / 2]
      let inverseSpacingSquared = zip(dims, c.lengths).reduce(0.0) {
        $0 + pow(Double($1.0) / $1.1, 2)
      }
      return 8 * Int(ceil(c.duration * c.speed * sqrt(inverseSpacingSquared) / courant / 8))
    }
    func resolution(_ axis: String, _ n: Int, _ steps: Int) -> Self {
      Self(axis: axis, nx: n, ny: n / 2, nz: c.anisotropicGrid ? n / 4 : n / 2, steps: steps)
    }
    return [16, 32, 64].map { resolution("space", $0, count(64, 0.25)) }
      + [0.8, 0.4, 0.2].map { resolution("time", 32, count(32, $0)) }
  }
  public var captures: [Int] { (0...8).map { $0 * steps / 8 } }
}
public struct RigidModeFrame: Codable, Sendable {
  public let step: Int
  public let p, u, v, w: [Double]
  public init(step: Int, p: [Double], u: [Double], v: [Double], w: [Double]) {
    self.step = step
    self.p = p
    self.u = u
    self.v = v
    self.w = w
  }
  public var fields: [[Double]] { [p, u, v, w] }
}
public struct RigidModeHistory: Codable, Sendable {
  public let spacing: [Double]
  public let dt: Double
  public let frames: [RigidModeFrame]
  public init(spacing: [Double], dt: Double, frames: [RigidModeFrame]) {
    self.spacing = spacing
    self.dt = dt
    self.frames = frames
  }
}
public enum RigidModeOracle {
  public static func fieldDimensions(_ r: RigidModeResolution, field: Int) -> [Int] {
    var dimensions = r.dimensions
    if field > 0 { dimensions[field - 1] += 1 }
    return dimensions
  }
  public static func position(_ index: Int, dimensions: [Int], field: Int, spacing: [Double])
    -> [Double]
  {
    let ijk = [
      index % dimensions[0], index / dimensions[0] % dimensions[1],
      index / (dimensions[0] * dimensions[1]),
    ]
    return (0..<3).map { (Double(ijk[$0]) + (field == $0 + 1 ? 0 : 0.5)) * spacing[$0] }
  }
  public static func initial(
    _ c: RigidModeCase, _ r: RigidModeResolution, spacing: [Double], dt: Double
  ) -> RigidModeFrame {
    let h = history(c, r, spacing: spacing, dt: dt, captures: [0])
    let p = h.frames[0].p
    var velocities: [[Double]] = []
    for axis in 0..<3 {
      let dims = fieldDimensions(r, field: axis + 1)
      let stride = axis == 0 ? 1 : (axis == 1 ? r.nx : r.nx * r.ny)
      velocities.append(
        (0..<dims.reduce(1, *)).map { index in
          let xyz = [index % dims[0], index / dims[0] % dims[1], index / (dims[0] * dims[1])]
          guard xyz[axis] > 0 && xyz[axis] < r.dimensions[axis] else { return 0 }
          let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
          return dt * (p[plus] - p[plus - stride]) / (2 * c.density * spacing[axis])
        })
    }
    return RigidModeFrame(step: 0, p: p, u: velocities[0], v: velocities[1], w: velocities[2])
  }
  public static func history(
    _ c: RigidModeCase, _ r: RigidModeResolution, spacing: [Double]? = nil,
    dt: Double? = nil, captures: [Int]? = nil
  ) -> RigidModeHistory {
    let spacing = spacing ?? zip(c.lengths, r.dimensions).map { $0 / Double($1) }
    let dt = dt ?? c.duration / Double(r.steps)
    let k = c.waveNumbers
    let q = (0..<3).map { axis in
      r.axis == "time" ? 2 * sin(k[axis] * spacing[axis] / 2) / spacing[axis] : k[axis]
    }
    let norm = sqrt(q.reduce(0) { $0 + $1 * $1 })
    let centres = (0..<3).map { axis in
      (0..<r.dimensions[axis]).map { cos(k[axis] * (Double($0) + 0.5) * spacing[axis]) }
    }
    let faces = (0..<3).map { axis in
      (0...r.dimensions[axis]).map { sin(k[axis] * Double($0) * spacing[axis]) }
    }
    let frames = (captures ?? r.captures).map { step in
      let fields = (0...3).map { field in
        let dims = fieldDimensions(r, field: field)
        let t = Double(step) * dt - (field > 0 ? dt / 2 : 0)
        let scale =
          field == 0
          ? c.amplitude * cos(c.speed * norm * t)
          : c.amplitude / (c.density * c.speed) * q[field - 1] / norm * sin(c.speed * norm * t)
        return (0..<dims.reduce(1, *)).map { index in
          let i = index % dims[0]
          let j = index / dims[0] % dims[1]
          let z = index / (dims[0] * dims[1])
          let xValue = field == 1 ? faces[0][i] : centres[0][i]
          let yValue = field == 2 ? faces[1][j] : centres[1][j]
          let zValue = field == 3 ? faces[2][z] : centres[2][z]
          return scale * xValue * yValue * zValue
        }
      }
      return RigidModeFrame(step: step, p: fields[0], u: fields[1], v: fields[2], w: fields[3])
    }
    return RigidModeHistory(spacing: spacing, dt: dt, frames: frames)
  }
}
