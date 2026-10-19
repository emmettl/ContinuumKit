// swift-format-ignore-file: AlwaysUseLowerCamelCase, TypeNamesShouldBeCapitalized
// A Linux stand-in for the part of Apple's simd module that ContinuumKit's CPU libraries and
// their consumers use. The manifest builds it as a module named `simd` on Linux only, so the
// frozen SolidMechanics and Numerics sources compile there unchanged. Apple platforms never
// build it and keep using simd itself.
//
// Each function follows the operation order of Apple's simd headers (macOS SDK, usr/include/simd:
// common.h, geometry.h, math.h, matrix.h and quaternion.h) and of the Swift overlay that calls
// them, compiled for arm64: the same products and sums in the same order, fused where Apple's
// code is fused and nowhere else. Apple fuses where its headers ask for fused multiply-adds
// (`simd_muladd`, and `#pragma STDC FP_CONTRACT ON` in the quaternion products), and also where
// clang contracts an expression by default: `simd_cross`, `simd_determinant` and the rotation
// matrix of a quaternion. `float` reciprocal square roots use the arm64 estimate and step
// instructions as Apple's do, written out from the Arm Architecture Reference Manual's
// pseudocode (FPRSqrtEstimate, RecipSqrtEstimate, FPRSqrtStepFused). Minimum and maximum follow
// FMINNM and FMAXNM: a NaN loses to a number, and -0 is less than +0.
//
// Tests/SIMDParityTests holds digests of these functions' results over fixed inputs. On Linux
// they check this stand-in against the record; on the Mac they check Apple's simd against the
// same record. Every function matches Apple's bit for bit except these, which the test reports
// without failing:
//
// - `simd_inverse` of a matrix: Apple's is a library function whose method is not published.
//   The inverse here is by cofactors.
// - The sines, cosines and arc tangents of the quaternions' angles: Glibc's and Apple's libm may
//   round differently in the last place.
//
// Two things here are not in Apple's simd and have no counterpart to match: division of a matrix
// by a scalar, and `sqrt` of a vector (lane by lane, correctly rounded).
//
// The arithmetic was first written for BombCAD's BlastModel (its Sources/BlastModel/
// LinuxSIMD.swift, 19 October 2026) and moved here so that it lives in one place.

// Apple's simd brings the C maths functions with it, so this does too.
@_exported import Glibc

// MARK: Lanes

/// FMINNM: the lesser, a NaN losing to a number, -0 below +0.
@inlinable func laneMin<T: BinaryFloatingPoint>(_ a: T, _ b: T) -> T {
  if a.isNaN { return b.isNaN ? a : b }
  if b.isNaN { return a }
  if a == b { return a.sign == .minus ? a : b }
  return a < b ? a : b
}

/// FMAXNM: the greater, a NaN losing to a number, +0 above -0.
@inlinable func laneMax<T: BinaryFloatingPoint>(_ a: T, _ b: T) -> T {
  if a.isNaN { return b.isNaN ? a : b }
  if b.isNaN { return a }
  if a == b { return a.sign == .minus ? b : a }
  return a > b ? a : b
}

/// `simd_reduce_add`: x + y for two lanes, (x + y) + z for three, (x + z) + (y + w) for four.
@inlinable func reduceAdd<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint {
  switch v.scalarCount {
  case 2: return v[0] + v[1]
  case 3: return v[0] + v[1] + v[2]
  case 4: return (v[0] + v[2]) + (v[1] + v[3])
  default:
    var sum = V.Scalar.zero
    for i in v.indices { sum += v[i] }
    return sum
  }
}

/// Arm's reciprocal square root estimate, FRSQRTE, for a float: 8 bits.
@usableFromInline func reciprocalSquareRootEstimate(_ x: Float) -> Float {
  if x.isNaN { return x + x }
  if x == 0 { return x.sign == .minus ? -.infinity : .infinity }
  if x < 0 { return .nan }
  if x == .infinity { return 0 }
  let bits = x.bitPattern
  var exponent = Int((bits >> 23) & 0xff)
  var fraction = UInt64(bits & 0x7f_ffff) << 29  // 52 bits, as the pseudocode has it
  if exponent == 0 {
    while fraction & (1 << 51) == 0 {
      fraction <<= 1
      exponent -= 1
    }
    fraction = (fraction << 1) & ((1 << 52) - 1)
  }
  var a =
    exponent & 1 == 0
    ? 0x100 | Int((fraction >> 44) & 0xff) : 0x80 | Int((fraction >> 45) & 0x7f)
  // RecipSqrtEstimate
  if a < 256 {
    a = a * 2 + 1
  } else {
    a = (a >> 1) << 1
    a = (a + 1) * 2
  }
  var b = 512
  while a * (b + 1) * (b + 1) < 1 << 28 { b += 1 }
  let estimate = (b + 1) / 2
  let resultExponent = (380 - exponent) / 2
  return Float(bitPattern: UInt32(resultExponent & 0xff) << 23 | UInt32(estimate & 0xff) << 15)
}

/// Arm's reciprocal square root step, FRSQRTS: (3 - a b) / 2, rounded once.
@usableFromInline func reciprocalSquareRootStep(_ a: Float, _ b: Float) -> Float {
  if (a.isInfinite && b == 0) || (a == 0 && b.isInfinite) { return 1.5 }
  return Float(3).addingProduct(-a, b) / 2
}

/// `simd_precise_rsqrt` for a float on arm64: the estimate and two Newton steps.
@usableFromInline func preciseReciprocalSquareRoot(_ x: Float) -> Float {
  var r = reciprocalSquareRootEstimate(x)
  r = r * reciprocalSquareRootStep(x, r * r)
  return r * reciprocalSquareRootStep(x, r * r)
}

/// `simd_precise_rsqrt`: for a float as above, for a double 1 / sqrt(x).
@inlinable func reciprocalSquareRoot<T: BinaryFloatingPoint>(_ x: T) -> T {
  if T.self == Float.self { return T(preciseReciprocalSquareRoot(Float(x))) }
  return 1 / x.squareRoot()
}

// MARK: Vectors

@inlinable public func simd_dot<V: SIMD>(_ a: V, _ b: V) -> V.Scalar
where V.Scalar: BinaryFloatingPoint { reduceAdd(a * b) }

@inlinable public func simd_length_squared<V: SIMD>(_ v: V) -> V.Scalar
where V.Scalar: BinaryFloatingPoint { simd_dot(v, v) }

@inlinable public func simd_length<V: SIMD>(_ v: V) -> V.Scalar
where V.Scalar: BinaryFloatingPoint { simd_length_squared(v).squareRoot() }

@inlinable public func simd_distance<V: SIMD>(_ a: V, _ b: V) -> V.Scalar
where V.Scalar: BinaryFloatingPoint { simd_length(a - b) }

@inlinable public func simd_distance_squared<V: SIMD>(_ a: V, _ b: V) -> V.Scalar
where V.Scalar: BinaryFloatingPoint { simd_length_squared(a - b) }

/// x times the reciprocal square root of its squared length, as Apple's is; not x / |x|.
@inlinable public func simd_normalize<V: SIMD>(_ v: V) -> V where V.Scalar: BinaryFloatingPoint {
  v * reciprocalSquareRoot(simd_length_squared(v))
}

/// `(x.zxy * y - x * y.zxy).zxy`, which clang contracts: each lane is
/// fma(first product, -(second product, rounded)).
@inlinable public func simd_cross<T: BinaryFloatingPoint & SIMDScalar>(_ a: SIMD3<T>, _ b: SIMD3<T>)
  -> SIMD3<T>
{
  SIMD3(
    (-(a.z * b.y)).addingProduct(a.y, b.z), (-(a.x * b.z)).addingProduct(a.z, b.x),
    (-(a.y * b.x)).addingProduct(a.x, b.y))
}

/// The simd overlay's `cross` and `dot`, which call `simd_cross` and `simd_dot`.
@inlinable public func cross<T: BinaryFloatingPoint & SIMDScalar>(_ a: SIMD3<T>, _ b: SIMD3<T>) -> SIMD3<T> {
  simd_cross(a, b)
}

@inlinable public func dot<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint {
  simd_dot(a, b)
}

@inlinable public func simd_min<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: BinaryFloatingPoint {
  var r = a
  for i in r.indices { r[i] = laneMin(a[i], b[i]) }
  return r
}

@inlinable public func simd_max<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: BinaryFloatingPoint {
  var r = a
  for i in r.indices { r[i] = laneMax(a[i], b[i]) }
  return r
}

@inlinable public func simd_min<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: FixedWidthInteger {
  pointwiseMin(a, b)
}

@inlinable public func simd_max<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: FixedWidthInteger {
  pointwiseMax(a, b)
}

@inlinable public func simd_min<T: BinaryFloatingPoint>(_ a: T, _ b: T) -> T { laneMin(a, b) }

@inlinable public func simd_max<T: BinaryFloatingPoint>(_ a: T, _ b: T) -> T { laneMax(a, b) }

/// `simd_min(simd_max(x, low), high)`.
@inlinable public func simd_clamp<V: SIMD>(_ x: V, _ low: V, _ high: V) -> V
where V.Scalar: BinaryFloatingPoint { simd_min(simd_max(x, low), high) }

@inlinable public func simd_clamp<V: SIMD>(_ x: V, _ low: V, _ high: V) -> V
where V.Scalar: FixedWidthInteger { pointwiseMin(pointwiseMax(x, low), high) }

@inlinable public func simd_clamp<T: BinaryFloatingPoint>(_ x: T, _ low: T, _ high: T) -> T {
  laneMin(laneMax(x, low), high)
}

@inlinable public func simd_abs<V: SIMD>(_ v: V) -> V where V.Scalar: BinaryFloatingPoint {
  var r = v
  for i in r.indices { r[i] = v[i].magnitude }
  return r
}

/// The simd overlay's `abs` of a vector: each lane's magnitude (its sign bit cleared).
@inlinable public func abs<V: SIMD>(_ v: V) -> V where V.Scalar: BinaryFloatingPoint { simd_abs(v) }

/// The simd overlay's elementwise floor, ceil, trunc and sqrt: exact or correctly rounded,
/// lane by lane, as Apple's arm64 instructions (FRINTM, FRINTP, FRINTZ, FSQRT) are.
@inlinable public func floor<V: SIMD>(_ v: V) -> V where V.Scalar: BinaryFloatingPoint {
  var r = v
  for i in r.indices { r[i] = v[i].rounded(.down) }
  return r
}

@inlinable public func ceil<V: SIMD>(_ v: V) -> V where V.Scalar: BinaryFloatingPoint {
  var r = v
  for i in r.indices { r[i] = v[i].rounded(.up) }
  return r
}

@inlinable public func trunc<V: SIMD>(_ v: V) -> V where V.Scalar: BinaryFloatingPoint {
  var r = v
  for i in r.indices { r[i] = v[i].rounded(.towardZero) }
  return r
}

@inlinable public func sqrt<V: SIMD>(_ v: V) -> V where V.Scalar: BinaryFloatingPoint {
  var r = v
  for i in r.indices { r[i] = v[i].squareRoot() }
  return r
}

/// For three lanes, min(min(x, z), y), as Apple's is.
@inlinable public func simd_reduce_min<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint {
  switch v.scalarCount {
  case 2: return laneMin(v[0], v[1])
  case 3: return laneMin(laneMin(v[0], v[2]), v[1])
  case 4: return laneMin(laneMin(v[0], v[2]), laneMin(v[1], v[3]))
  default: return v.indices.dropFirst().reduce(v[0]) { laneMin($0, v[$1]) }
  }
}

@inlinable public func simd_reduce_max<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: BinaryFloatingPoint {
  switch v.scalarCount {
  case 2: return laneMax(v[0], v[1])
  case 3: return laneMax(laneMax(v[0], v[2]), v[1])
  case 4: return laneMax(laneMax(v[0], v[2]), laneMax(v[1], v[3]))
  default: return v.indices.dropFirst().reduce(v[0]) { laneMax($0, v[$1]) }
  }
}

// MARK: Matrices

/// `simd_mul(matrix, vector)`: c0 y0, then two fused multiply-adds (`simd_muladd`).
@inlinable func multiply<T: BinaryFloatingPoint & SIMDScalar>(
  _ c0: SIMD3<T>, _ c1: SIMD3<T>, _ c2: SIMD3<T>, _ v: SIMD3<T>
) -> SIMD3<T> {
  var r = c0 * v.x
  for i in 0..<3 { r[i] = r[i].addingProduct(c1[i], v.y) }
  for i in 0..<3 { r[i] = r[i].addingProduct(c2[i], v.z) }
  return r
}

/// `simd_reduce_add(c0 * (rotate1(c1) * rotate2(c2) - rotate2(c1) * rotate1(c2)))`, the
/// difference contracted as in `simd_cross`.
@inlinable func matrixDeterminant<T: BinaryFloatingPoint & SIMDScalar>(
  _ c0: SIMD3<T>, _ c1: SIMD3<T>, _ c2: SIMD3<T>
) -> T {
  let p = SIMD3(c1.y, c1.z, c1.x)
  let q = SIMD3(c2.z, c2.x, c2.y)
  let s = SIMD3(c1.z, c1.x, c1.y)
  let t = SIMD3(c2.y, c2.z, c2.x)
  var d = SIMD3<T>()
  for i in 0..<3 { d[i] = (-(s[i] * t[i])).addingProduct(p[i], q[i]) }
  return reduceAdd(c0 * d)
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

  /// The rotation matrix of a unit quaternion, as `simd_matrix4x4(simd_quatd)` writes it out and
  /// clang contracts it. A diagonal entry is four squares summed left to right, the first two
  /// fused on the first square and each later square fused onto the running sum; any other
  /// entry is twice a sum or difference of two products, fused on the first.
  public init(_ q: simd_quatd) {
    let v = q.vector
    /// a a ± b b ± c c ± d d, with the signs of the last three.
    func diagonal(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ signs: SIMD3<Double>)
      -> Double
    {
      (signs.x * (b * b)).addingProduct(a, a).addingProduct(signs.y * c, c).addingProduct(signs.z * d, d)
    }
    /// 2 (a b ± c d).
    func twice(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ sign: Double) -> Double {
      2 * (sign * (c * d)).addingProduct(a, b)
    }
    columns = (
      SIMD3(
        diagonal(v.x, v.y, v.z, v.w, SIMD3(-1, -1, 1)), twice(v.x, v.y, v.z, v.w, 1),
        twice(v.x, v.z, v.y, v.w, -1)),
      SIMD3(
        twice(v.x, v.y, v.z, v.w, -1), diagonal(v.y, v.z, v.w, v.x, SIMD3(-1, 1, -1)),
        twice(v.y, v.z, v.x, v.w, 1)),
      SIMD3(
        twice(v.z, v.x, v.y, v.w, 1), twice(v.y, v.z, v.x, v.w, -1),
        diagonal(v.z, v.w, v.x, v.y, SIMD3(1, -1, -1)))
    )
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

  public var determinant: Double { matrixDeterminant(columns.0, columns.1, columns.2) }

  public static func == (a: simd_double3x3, b: simd_double3x3) -> Bool {
    a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1 && a.columns.2 == b.columns.2
  }

  /// `simd_add`: each column 1 a + 1 b, which is a + b exactly.
  public static func + (a: simd_double3x3, b: simd_double3x3) -> simd_double3x3 {
    simd_double3x3(a.columns.0 + b.columns.0, a.columns.1 + b.columns.1, a.columns.2 + b.columns.2)
  }

  /// `simd_sub`: each column 1 a - 1 b, which is a - b exactly.
  public static func - (a: simd_double3x3, b: simd_double3x3) -> simd_double3x3 {
    simd_double3x3(a.columns.0 - b.columns.0, a.columns.1 - b.columns.1, a.columns.2 - b.columns.2)
  }

  /// The zero matrix minus a, as the overlay has it, so a zero entry negates to +0.
  public static prefix func - (a: simd_double3x3) -> simd_double3x3 { simd_double3x3() - a }

  public static func * (a: simd_double3x3, s: Double) -> simd_double3x3 {
    simd_double3x3(a.columns.0 * s, a.columns.1 * s, a.columns.2 * s)
  }

  public static func * (s: Double, a: simd_double3x3) -> simd_double3x3 { a * s }

  /// Each column divided by s. Apple's simd has no such operator.
  public static func / (a: simd_double3x3, s: Double) -> simd_double3x3 {
    simd_double3x3(a.columns.0 / s, a.columns.1 / s, a.columns.2 / s)
  }

  public static func * (a: simd_double3x3, v: SIMD3<Double>) -> SIMD3<Double> {
    multiply(a.columns.0, a.columns.1, a.columns.2, v)
  }

  /// `simd_mul(vector, matrix)`: the transpose times the vector.
  public static func * (v: SIMD3<Double>, a: simd_double3x3) -> SIMD3<Double> {
    let t = simd_transpose(a)
    return multiply(t.columns.0, t.columns.1, t.columns.2, v)
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

public func simd_determinant(_ m: simd_double3x3) -> Double { m.determinant }

/// The inverse by cofactors. A singular matrix gives infinite or NaN entries, as simd does.
/// Apple's method is not published, so this may differ from it in the last bits.
public func simd_inverse(_ m: simd_double3x3) -> simd_double3x3 {
  let (a, b, c) = m.columns
  let r0 = simd_cross(b, c), r1 = simd_cross(c, a), r2 = simd_cross(a, b)
  let det = simd_dot(a, r0)
  return simd_transpose(simd_double3x3(r0, r1, r2)) / det
}

public func simd_mul(_ a: simd_double3x3, _ b: simd_double3x3) -> simd_double3x3 { a * b }

public func simd_mul(_ a: simd_double3x3, _ v: SIMD3<Double>) -> SIMD3<Double> { a * v }

/// A column-major 3 × 3 matrix of floats, laid out as Apple's `simd_float3x3` is.
public struct simd_float3x3: Equatable, Sendable {
  public var columns: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

  public init() { columns = (.zero, .zero, .zero) }

  public init(columns: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)) { self.columns = columns }

  public init(_ c0: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>) { columns = (c0, c1, c2) }

  public init(diagonal d: SIMD3<Float>) {
    columns = (SIMD3(d.x, 0, 0), SIMD3(0, d.y, 0), SIMD3(0, 0, d.z))
  }

  public subscript(column: Int) -> SIMD3<Float> {
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

  public var transpose: simd_float3x3 {
    let (a, b, c) = columns
    return simd_float3x3(SIMD3(a.x, b.x, c.x), SIMD3(a.y, b.y, c.y), SIMD3(a.z, b.z, c.z))
  }

  public var determinant: Float { matrixDeterminant(columns.0, columns.1, columns.2) }

  public static func == (a: simd_float3x3, b: simd_float3x3) -> Bool {
    a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1 && a.columns.2 == b.columns.2
  }

  /// `simd_add`: each column 1 a + 1 b, which is a + b exactly.
  public static func + (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 {
    simd_float3x3(a.columns.0 + b.columns.0, a.columns.1 + b.columns.1, a.columns.2 + b.columns.2)
  }

  public static func - (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 {
    simd_float3x3(a.columns.0 - b.columns.0, a.columns.1 - b.columns.1, a.columns.2 - b.columns.2)
  }

  public static func * (s: Float, a: simd_float3x3) -> simd_float3x3 {
    simd_float3x3(a.columns.0 * s, a.columns.1 * s, a.columns.2 * s)
  }

  public static func * (a: simd_float3x3, s: Float) -> simd_float3x3 { s * a }

  public static func * (a: simd_float3x3, v: SIMD3<Float>) -> SIMD3<Float> {
    multiply(a.columns.0, a.columns.1, a.columns.2, v)
  }

  public static func * (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 {
    simd_float3x3(a * b.columns.0, a * b.columns.1, a * b.columns.2)
  }

  public static func += (a: inout simd_float3x3, b: simd_float3x3) { a = a + b }

  public static func -= (a: inout simd_float3x3, b: simd_float3x3) { a = a - b }
}

// MARK: Quaternions

/// `_simd_mul_vq(v, q)`, arm64: v.x S1(q) + v.y S2(q) + v.z S3(q), contracted as clang does
/// under `FP_CONTRACT ON`: fma(v.z, S3, fma(v.x, S1, v.y S2)).
@inlinable func multiplyVectorQuaternion<T: BinaryFloatingPoint & SIMDScalar>(
  _ v: SIMD3<T>, _ q: SIMD4<T>
) -> SIMD4<T> {
  let s1 = SIMD4(q.w, -q.z, q.y, -q.x)
  let s2 = SIMD4(q.z, q.w, -q.x, -q.y)
  let s3 = SIMD4(-q.y, q.x, q.w, -q.z)
  var r = SIMD4<T>()
  for i in 0..<4 { r[i] = (v.y * s2[i]).addingProduct(v.x, s1[i]).addingProduct(v.z, s3[i]) }
  return r
}

/// `simd_mul(p, q)`: (p.x S1(q) + p.y S2(q)) + (p.z S3(q) + p.w q), each bracket one fused
/// multiply-add on the second product, then a plain sum.
@inlinable func multiplyQuaternions<T: BinaryFloatingPoint & SIMDScalar>(
  _ p: SIMD4<T>, _ q: SIMD4<T>
) -> SIMD4<T> {
  let s1 = SIMD4(q.w, -q.z, q.y, -q.x)
  let s2 = SIMD4(q.z, q.w, -q.x, -q.y)
  let s3 = SIMD4(-q.y, q.x, q.w, -q.z)
  var r = SIMD4<T>()
  for i in 0..<4 {
    let a = (p.y * s2[i]).addingProduct(p.x, s1[i])
    let b = (p.w * q[i]).addingProduct(p.z, s3[i])
    r[i] = a + b
  }
  return r
}

/// `simd_act(q, v)`, arm64: the imaginary part of q (v q*).
@inlinable func quaternionAct<T: BinaryFloatingPoint & SIMDScalar>(_ q: SIMD4<T>, _ v: SIMD3<T>) -> SIMD3<T> {
  let conjugate = q * SIMD4(-1, -1, -1, 1)
  let r = multiplyQuaternions(q, multiplyVectorQuaternion(v, conjugate))
  return SIMD3(r.x, r.y, r.z)
}

/// A quaternion of doubles: `vector` holds the imaginary parts in x, y and z and the real part in w.
public struct simd_quatd: Equatable, Sendable {
  public var vector: SIMD4<Double>

  public init(vector: SIMD4<Double>) { self.vector = vector }

  public init(ix: Double, iy: Double, iz: Double, r: Double) { vector = SIMD4(ix, iy, iz, r) }

  /// The rotation by `angle` radians about the unit vector `axis`: sin(angle / 2) times the
  /// axis, and cos(angle / 2).
  public init(angle: Double, axis: SIMD3<Double>) {
    let s = sin(angle / 2)
    vector = SIMD4(s * axis.x, s * axis.y, s * axis.z, cos(angle / 2))
  }

  /// `simd_quaternion(from, to)`: the rotation from one unit vector to another, in two halves
  /// where they are more than 90 degrees apart. As the macOS 27 SDK's header has it: past 90
  /// degrees the halfway vector is the sum of the two vectors normalised, and they count as
  /// opposite when its squared length is at most 2^-104.
  public init(from: SIMD3<Double>, to: SIMD3<Double>) {
    func reduced(_ from: SIMD3<Double>, _ to: SIMD3<Double>) -> simd_quatd {
      let half = simd_normalize(from + to)
      let i = simd_cross(from, half)
      return simd_quatd(vector: SIMD4(i.x, i.y, i.z, simd_dot(from, half)))
    }
    if simd_dot(from, to) >= 0 {
      self = reduced(from, to)
      return
    }
    let half = simd_normalize(from) + simd_normalize(to)
    if simd_length_squared(half) <= 0x1p-104 {
      let a = simd_abs(from)
      let other: SIMD3<Double> =
        a.x <= a.y && a.x <= a.z ? SIMD3(1, 0, 0) : a.y <= a.z ? SIMD3(0, 1, 0) : SIMD3(0, 0, 1)
      let i = simd_normalize(simd_cross(from, other))
      self.init(vector: SIMD4(i.x, i.y, i.z, 0))
      return
    }
    let unit = simd_normalize(half)
    self = reduced(from, unit) * reduced(unit, to)
  }

  public var real: Double { vector.w }

  public var imag: SIMD3<Double> { SIMD3(vector.x, vector.y, vector.z) }

  /// Rotates `v` by this quaternion, which must be of unit length.
  public func act(_ v: SIMD3<Double>) -> SIMD3<Double> { quaternionAct(vector, v) }

  public var conjugate: simd_quatd { simd_quatd(vector: vector * SIMD4(-1, -1, -1, 1)) }

  /// The conjugate times 1 / |q|^2.
  public var inverse: simd_quatd {
    simd_quatd(vector: conjugate.vector * (1 / simd_length_squared(vector)))
  }

  public var length: Double { simd_length(vector) }

  /// q times 1 / sqrt(|q|^2); the identity for q = 0.
  public var normalized: simd_quatd {
    let lengthSquared = simd_length_squared(vector)
    if lengthSquared == 0 { return simd_quatd(vector: SIMD4(0, 0, 0, 1)) }
    return simd_quatd(vector: vector * (1 / lengthSquared.squareRoot()))
  }

  /// 2 atan2(|imag|, real).
  public var angle: Double { 2 * atan2(simd_length(imag), real) }

  public var axis: SIMD3<Double> { simd_normalize(imag) }

  public static func * (p: simd_quatd, q: simd_quatd) -> simd_quatd {
    simd_quatd(vector: multiplyQuaternions(p.vector, q.vector))
  }

  public static func * (a: Double, q: simd_quatd) -> simd_quatd { simd_quatd(vector: a * q.vector) }

  public static func * (q: simd_quatd, a: Double) -> simd_quatd { simd_quatd(vector: a * q.vector) }

  public static func + (p: simd_quatd, q: simd_quatd) -> simd_quatd { simd_quatd(vector: p.vector + q.vector) }

  public static func - (p: simd_quatd, q: simd_quatd) -> simd_quatd { simd_quatd(vector: p.vector - q.vector) }
}

public func simd_normalize(_ q: simd_quatd) -> simd_quatd { q.normalized }

public func simd_inverse(_ q: simd_quatd) -> simd_quatd { q.inverse }

public func simd_mul(_ p: simd_quatd, _ q: simd_quatd) -> simd_quatd { p * q }

public func simd_act(_ q: simd_quatd, _ v: SIMD3<Double>) -> SIMD3<Double> { q.act(v) }

/// A quaternion of floats: `vector` holds the imaginary parts in x, y and z and the real part
/// in w.
public struct simd_quatf: Equatable, Sendable {
  public var vector: SIMD4<Float>

  public init() { vector = .zero }

  public init(vector: SIMD4<Float>) { self.vector = vector }

  public init(ix: Float, iy: Float, iz: Float, r: Float) { vector = SIMD4(ix, iy, iz, r) }

  /// sinf(angle / 2) times the axis, and cosf(angle / 2): the simd headers reach the float
  /// functions through tgmath.h.
  public init(angle: Float, axis: SIMD3<Float>) {
    let s = sinf(angle / 2)
    vector = SIMD4(s * axis.x, s * axis.y, s * axis.z, cosf(angle / 2))
  }

  public var real: Float { vector.w }

  public var imag: SIMD3<Float> { SIMD3(vector.x, vector.y, vector.z) }

  public func act(_ v: SIMD3<Float>) -> SIMD3<Float> { quaternionAct(vector, v) }

  public static func * (p: simd_quatf, q: simd_quatf) -> simd_quatf {
    simd_quatf(vector: multiplyQuaternions(p.vector, q.vector))
  }
}
