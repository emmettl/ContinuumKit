import Foundation

public struct MaskedBox: Codable, Equatable, Sendable {
  public let minimum, maximum: [Double]
  public let modes: [Int]
  public let driven: Bool
  public init(minimum: [Double], maximum: [Double], modes: [Int], driven: Bool) {
    self.minimum = minimum
    self.maximum = maximum
    self.modes = modes
    self.driven = driven
  }
  public var lengths: [Double] { zip(maximum, minimum).map { $0 - $1 } }
  public var waveNumbers: [Double] { zip(modes, lengths).map { Double($0) * Double.pi / $1 } }
}
public struct MaskedModeCase: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable { case interiorBox, splitChambers }
  public let version: Int, id: String, kind: Kind
  public let lengths: [Double], boxes: [MaskedBox]
  public let density, speed, amplitude, inactivePressure: Double
  public init(id: String, kind: Kind) throws {
    version = 1
    self.id = id
    self.kind = kind
    lengths = [0.25, 0.125, 0.125]
    boxes = Self.geometry(kind)
    density = 1.25
    speed = 320
    amplitude = 1
    inactivePressure = 100
    try validate()
  }
  static func geometry(_ kind: Kind) -> [MaskedBox] {
    if kind == .interiorBox {
      return [
        MaskedBox(
          minimum: [0.03125, 0.015625, 0.015625], maximum: [0.21875, 0.109375, 0.109375],
          modes: [2, 1, 1], driven: true)
      ]
    }
    return [
      MaskedBox(
        minimum: [0.03125, 0.015625, 0.015625], maximum: [0.109375, 0.109375, 0.109375],
        modes: [1, 1, 1], driven: true),
      MaskedBox(
        minimum: [0.140625, 0.015625, 0.015625], maximum: [0.21875, 0.109375, 0.109375],
        modes: [1, 1, 1], driven: false),
    ]
  }
  public func validate() throws {
    guard version == 1, !id.isEmpty, lengths == [0.25, 0.125, 0.125], boxes == Self.geometry(kind),
      density == 1.25, speed == 320, amplitude == 1, inactivePressure == 100
    else { throw BenchmarkFailure.invalidCase }
  }
  public var duration: Double {
    2 * Double.pi / (speed * sqrt(boxes[0].waveNumbers.reduce(0) { $0 + $1 * $1 }))
  }
  public var energy: Double {
    boxes.filter(\.driven).reduce(0) {
      $0 + amplitude * amplitude * $1.lengths.reduce(1, *) / (16 * density * speed * speed)
    }
  }
  public static func standard() throws -> [Self] {
    try [
      Self(id: "interior-box", kind: .interiorBox),
      Self(id: "split-chambers", kind: .splitChambers),
    ]
  }
}
public struct MaskedModeResolution: Codable, Equatable, Sendable {
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
  public var captures: [Int] { (0...8).map { $0 * steps / 8 } }
  public static func standard(_ c: MaskedModeCase) -> [Self] {
    func count(_ n: Int, _ courant: Double) -> Int {
      8 * Int(ceil(c.duration * c.speed * sqrt(3) * Double(n) / c.lengths[0] / courant / 8))
    }
    return [16, 32, 64].map {
      Self(axis: "space", nx: $0, ny: $0 / 2, nz: $0 / 2, steps: count(64, 0.25))
    }
      + [0.8, 0.4, 0.2].map { Self(axis: "time", nx: 32, ny: 16, nz: 16, steps: count(32, $0)) }
  }
}
/// Independent integer occupancy and face connectivity; not produced by an application's mesh code.
public struct MaskedGrid: Codable, Sendable {
  public let dimensions: [Int], spacing: [Double], labels: [Int]
  public let openFields: [[Bool]]
  public var inside: [UInt8] { labels.map { $0 < 0 ? 0 : 1 } }
  /// Matches the declared rigid-face contract; inactive coefficients are unused -1 sentinels.
  public var faces: [Float] {
    let count = labels.count
    var result = [Float](repeating: -1, count: 6 * count)
    let offsets = [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]]
    for index in labels.indices where labels[index] >= 0 {
      let xyz = coordinates(index, shape: dimensions)
      for side in 0..<6 {
        let other = zip(xyz, offsets[side]).map(+)
        result[side * count + index] = label(other) >= 0 ? -1 : 0
      }
    }
    return result
  }
  public init(_ c: MaskedModeCase, _ r: MaskedModeResolution) throws {
    try c.validate()
    guard r.dimensions.allSatisfy({ $0 >= 2 && $0 <= 128 }), r.steps > 0,
      ["space", "time"].contains(r.axis)
    else { throw BenchmarkFailure.invalidCase }
    dimensions = r.dimensions
    spacing = zip(c.lengths, r.dimensions).map { $0 / Double($1) }
    var bounds: [([Int], [Int])] = []
    for box in c.boxes {
      let lower = zip(box.minimum, spacing).map { $0 / $1 }
      let upper = zip(box.maximum, spacing).map { $0 / $1 }
      guard (lower + upper).allSatisfy({ abs($0 - $0.rounded()) < 1e-9 }) else {
        throw BenchmarkFailure.invalidCase
      }
      bounds.append((lower.map { Int($0.rounded()) }, upper.map { Int($0.rounded()) }))
    }
    labels = (0..<r.dimensions.reduce(1, *)).map { index in
      let xyz = [index % r.nx, index / r.nx % r.ny, index / (r.nx * r.ny)]
      return bounds.firstIndex(where: { b in
        (0..<3).allSatisfy { xyz[$0] >= b.0[$0] && xyz[$0] < b.1[$0] }
      }) ?? -1
    }
    let storedLabels = labels
    let dims = dimensions
    func labelAt(_ xyz: [Int]) -> Int {
      guard (0..<3).allSatisfy({ xyz[$0] >= 0 && xyz[$0] < dims[$0] }) else { return -1 }
      return storedLabels[xyz[0] + dims[0] * (xyz[1] + dims[1] * xyz[2])]
    }
    openFields =
      [labels.map { $0 >= 0 }]
      + (0..<3).map { axis in
        var shape = dims
        shape[axis] += 1
        return (0..<shape.reduce(1, *)).map { index in
          let xyz = [index % shape[0], index / shape[0] % shape[1], index / (shape[0] * shape[1])]
          var left = xyz
          left[axis] -= 1
          let a = labelAt(left)
          let b = labelAt(xyz)
          return a >= 0 && a == b
        }
      }
  }
  public func fieldDimensions(_ field: Int) -> [Int] {
    var d = dimensions
    if field > 0 { d[field - 1] += 1 }
    return d
  }
  public func coordinates(_ index: Int, shape: [Int]) -> [Int] {
    [index % shape[0], index / shape[0] % shape[1], index / (shape[0] * shape[1])]
  }
  public func label(_ xyz: [Int]) -> Int {
    guard xyz.count == 3, (0..<3).allSatisfy({ xyz[$0] >= 0 && xyz[$0] < dimensions[$0] }) else {
      return -1
    }
    return labels[xyz[0] + dimensions[0] * (xyz[1] + dimensions[1] * xyz[2])]
  }
  public func component(field: Int, index: Int) -> Int {
    label(coordinates(index, shape: fieldDimensions(field)))
  }
}
public enum MaskedModeOracle {
  public static func history(
    _ c: MaskedModeCase, _ r: MaskedModeResolution,
    spacing: [Double]? = nil, dt: Double? = nil, captures: [Int]? = nil
  ) throws -> RigidModeHistory {
    let grid = try MaskedGrid(c, r)
    let spacing = spacing ?? grid.spacing
    let dt = dt ?? c.duration / Double(r.steps)
    guard spacing.count == 3, spacing.allSatisfy({ $0.isFinite && $0 > 0 }), dt.isFinite, dt > 0
    else { throw BenchmarkFailure.invalidSamples }
    let waveNumbers = c.boxes.map(\.waveNumbers)
    let wave = waveNumbers.map { k in
      (0..<3).map { r.axis == "time" ? 2 * sin(k[$0] * spacing[$0] / 2) / spacing[$0] : k[$0] }
    }
    let norms = wave.map { sqrt($0.reduce(0) { $0 + $1 * $1 }) }
    let centres = c.boxes.indices.map { component in
      (0..<3).map { axis in
        (0..<r.dimensions[axis]).map {
          cos(
            waveNumbers[component][axis]
              * ((Double($0) + 0.5) * spacing[axis] - c.boxes[component].minimum[axis]))
        }
      }
    }
    let faces = c.boxes.indices.map { component in
      (0..<3).map { axis in
        (0...r.dimensions[axis]).map {
          sin(
            waveNumbers[component][axis]
              * (Double($0) * spacing[axis] - c.boxes[component].minimum[axis]))
        }
      }
    }
    let fieldsPerCapture = (captures ?? r.captures).map { step in
      (0...3).map { field in
        let shape = grid.fieldDimensions(field)
        let t = Double(step) * dt - (field > 0 ? dt / 2 : 0)
        let scale = c.boxes.indices.map { component in
          field == 0
            ? c.amplitude * cos(c.speed * norms[component] * t)
            : c.amplitude / (c.density * c.speed) * wave[component][field - 1] / norms[component]
              * sin(c.speed * norms[component] * t)
        }
        return (0..<shape.reduce(1, *)).map { index -> Double in
          guard grid.openFields[field][index] else { return field == 0 ? c.inactivePressure : 0 }
          let i = index % shape[0]
          let j = index / shape[0] % shape[1]
          let k = index / (shape[0] * shape[1])
          let component = grid.labels[i + r.nx * (j + r.ny * k)]
          guard c.boxes[component].driven else { return 0 }
          let x = field == 1 ? faces[component][0][i] : centres[component][0][i]
          let y = field == 2 ? faces[component][1][j] : centres[component][1][j]
          let z = field == 3 ? faces[component][2][k] : centres[component][2][k]
          return scale[component] * x * y * z
        }
      }
    }
    let frames = zip(captures ?? r.captures, fieldsPerCapture).map {
      RigidModeFrame(step: $0, p: $1[0], u: $1[1], v: $1[2], w: $1[3])
    }
    return RigidModeHistory(spacing: spacing, dt: dt, frames: frames)
  }
  public static func initial(
    _ c: MaskedModeCase, _ r: MaskedModeResolution, spacing: [Double], dt: Double
  ) throws -> RigidModeFrame {
    let grid = try MaskedGrid(c, r)
    let p = try history(c, r, spacing: spacing, dt: dt, captures: [0]).frames[0].p
    let velocities = (0..<3).map { axis in
      let shape = grid.fieldDimensions(axis + 1)
      let stride = axis == 0 ? 1 : (axis == 1 ? r.nx : r.nx * r.ny)
      return (0..<shape.reduce(1, *)).map { index -> Double in
        guard grid.openFields[axis + 1][index] else { return 0 }
        let xyz = grid.coordinates(index, shape: shape)
        let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
        return dt * (p[plus] - p[plus - stride]) / (2 * c.density * spacing[axis])
      }
    }
    return RigidModeFrame(step: 0, p: p, u: velocities[0], v: velocities[1], w: velocities[2])
  }
}
