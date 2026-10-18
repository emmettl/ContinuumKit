// A Linux stand-in for the part of Apple's simd module that SolidMechanics and its tests use.
// The manifest builds it as a module named `simd` on Linux only, so the frozen SolidMechanics
// sources compile there unchanged. Apple platforms never build it and keep using simd itself.
// Its arithmetic is written out plainly and may differ from Apple's simd in the last bits.

// Apple's simd brings the C maths functions with it, so this does too.
@_exported import Glibc

public func simd_dot<T: BinaryFloatingPoint & SIMDScalar>(_ a: SIMD3<T>, _ b: SIMD3<T>) -> T {
  a.x * b.x + a.y * b.y + a.z * b.z
}

public func simd_length_squared<T: BinaryFloatingPoint & SIMDScalar>(_ v: SIMD3<T>) -> T { simd_dot(v, v) }

public func simd_length<T: BinaryFloatingPoint & SIMDScalar>(_ v: SIMD3<T>) -> T { simd_length_squared(v).squareRoot() }

public func simd_distance<T: BinaryFloatingPoint & SIMDScalar>(_ a: SIMD3<T>, _ b: SIMD3<T>) -> T { simd_length(a - b) }

public func simd_normalize<T: BinaryFloatingPoint & SIMDScalar>(_ v: SIMD3<T>) -> SIMD3<T> { v / simd_length(v) }

public func simd_cross<T: BinaryFloatingPoint & SIMDScalar>(_ a: SIMD3<T>, _ b: SIMD3<T>) -> SIMD3<T> {
  SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

/// A column-major 3 × 3 matrix of doubles, laid out as Apple's `simd_double3x3` is.
public struct simd_double3x3: Equatable, Sendable {
  public var columns: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)

  public init() { columns = (.zero, .zero, .zero) }

  public init(columns: (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)) { self.columns = columns }

  public init(_ c0: SIMD3<Double>, _ c1: SIMD3<Double>, _ c2: SIMD3<Double>) { columns = (c0, c1, c2) }

  public init(diagonal d: SIMD3<Double>) {
    columns = (SIMD3(d.x, 0, 0), SIMD3(0, d.y, 0), SIMD3(0, 0, d.z))
  }

  public init(rows: [SIMD3<Double>]) {
    precondition(rows.count == 3)
    columns = (
      SIMD3(rows[0].x, rows[1].x, rows[2].x), SIMD3(rows[0].y, rows[1].y, rows[2].y),
      SIMD3(rows[0].z, rows[1].z, rows[2].z))
  }

  /// The rotation matrix of a unit quaternion.
  public init(_ q: simd_quatd) {
    columns = (q.act(SIMD3(1, 0, 0)), q.act(SIMD3(0, 1, 0)), q.act(SIMD3(0, 0, 1)))
  }

  public subscript(column: Int) -> SIMD3<Double> {
    get {
      switch column {
      case 0: return columns.0
      case 1: return columns.1
      case 2: return columns.2
      default: preconditionFailure("column index out of range")
      }
    }
    set {
      switch column {
      case 0: columns.0 = newValue
      case 1: columns.1 = newValue
      case 2: columns.2 = newValue
      default: preconditionFailure("column index out of range")
      }
    }
  }

  public subscript(column: Int, row: Int) -> Double {
    get { self[column][row] }
    set { self[column][row] = newValue }
  }

  public var transpose: simd_double3x3 { simd_transpose(self) }

  public var inverse: simd_double3x3 { simd_inverse(self) }

  public var determinant: Double { simd_determinant(self) }

  public static func == (a: simd_double3x3, b: simd_double3x3) -> Bool {
    a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1 && a.columns.2 == b.columns.2
  }

  public static func + (a: simd_double3x3, b: simd_double3x3) -> simd_double3x3 {
    simd_double3x3(a.columns.0 + b.columns.0, a.columns.1 + b.columns.1, a.columns.2 + b.columns.2)
  }

  public static func - (a: simd_double3x3, b: simd_double3x3) -> simd_double3x3 {
    simd_double3x3(a.columns.0 - b.columns.0, a.columns.1 - b.columns.1, a.columns.2 - b.columns.2)
  }

  public static prefix func - (a: simd_double3x3) -> simd_double3x3 {
    simd_double3x3(-a.columns.0, -a.columns.1, -a.columns.2)
  }

  public static func * (a: simd_double3x3, s: Double) -> simd_double3x3 {
    simd_double3x3(a.columns.0 * s, a.columns.1 * s, a.columns.2 * s)
  }

  public static func * (s: Double, a: simd_double3x3) -> simd_double3x3 { a * s }

  public static func / (a: simd_double3x3, s: Double) -> simd_double3x3 {
    simd_double3x3(a.columns.0 / s, a.columns.1 / s, a.columns.2 / s)
  }

  public static func * (a: simd_double3x3, v: SIMD3<Double>) -> SIMD3<Double> {
    a.columns.0 * v.x + a.columns.1 * v.y + a.columns.2 * v.z
  }

  public static func * (v: SIMD3<Double>, a: simd_double3x3) -> SIMD3<Double> {
    SIMD3(simd_dot(v, a.columns.0), simd_dot(v, a.columns.1), simd_dot(v, a.columns.2))
  }

  public static func * (a: simd_double3x3, b: simd_double3x3) -> simd_double3x3 {
    simd_double3x3(a * b.columns.0, a * b.columns.1, a * b.columns.2)
  }

  public static func += (a: inout simd_double3x3, b: simd_double3x3) { a = a + b }

  public static func -= (a: inout simd_double3x3, b: simd_double3x3) { a = a - b }

  public static func *= (a: inout simd_double3x3, s: Double) { a = a * s }

  public static func *= (a: inout simd_double3x3, b: simd_double3x3) { a = a * b }
}

public let matrix_identity_double3x3 = simd_double3x3(diagonal: SIMD3(1, 1, 1))

public func simd_transpose(_ m: simd_double3x3) -> simd_double3x3 {
  let (a, b, c) = m.columns
  return simd_double3x3(SIMD3(a.x, b.x, c.x), SIMD3(a.y, b.y, c.y), SIMD3(a.z, b.z, c.z))
}

public func simd_determinant(_ m: simd_double3x3) -> Double {
  simd_dot(m.columns.0, simd_cross(m.columns.1, m.columns.2))
}

/// The inverse by cofactors. A singular matrix gives infinite or NaN entries, as simd does.
public func simd_inverse(_ m: simd_double3x3) -> simd_double3x3 {
  let (a, b, c) = m.columns
  let r0 = simd_cross(b, c), r1 = simd_cross(c, a), r2 = simd_cross(a, b)
  let det = simd_dot(a, r0)
  return simd_transpose(simd_double3x3(r0, r1, r2)) / det
}

public func simd_mul(_ a: simd_double3x3, _ b: simd_double3x3) -> simd_double3x3 { a * b }

public func simd_mul(_ a: simd_double3x3, _ v: SIMD3<Double>) -> SIMD3<Double> { a * v }

/// A quaternion of doubles: `vector` holds the imaginary parts in x, y and z and the real part in w.
public struct simd_quatd: Equatable, Sendable {
  public var vector: SIMD4<Double>

  public init(vector: SIMD4<Double>) { self.vector = vector }

  public init(ix: Double, iy: Double, iz: Double, r: Double) { vector = SIMD4(ix, iy, iz, r) }

  /// The rotation by `angle` radians about the unit vector `axis`.
  public init(angle: Double, axis: SIMD3<Double>) {
    let s = sin(angle / 2)
    vector = SIMD4(axis.x * s, axis.y * s, axis.z * s, cos(angle / 2))
  }

  public var real: Double { vector.w }

  public var imag: SIMD3<Double> { SIMD3(vector.x, vector.y, vector.z) }

  /// Rotates `v` by this quaternion, which must be of unit length.
  public func act(_ v: SIMD3<Double>) -> SIMD3<Double> {
    let t = 2 * simd_cross(imag, v)
    return v + real * t + simd_cross(imag, t)
  }
}
