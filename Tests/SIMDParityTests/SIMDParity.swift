import simd

/// Digests of the simd functions the Linux stand-in (Sources/LinuxSIMD) provides, each over the
/// same few thousand inputs: on Linux of the stand-in, on the Mac of Apple's simd. Only what both
/// modules have is called here, so the same source compiles against either.
/// LinuxSIMDParityTests compares them with the digests recorded for the stand-in.
enum SIMDParity {
  static let samples = 4096

  /// A digest (FNV-1a, 64 bits, of each result's bits; every NaN counts alike) by function name.
  static func digests() -> [String: UInt64] {
    var out: [String: UInt64] = [:]
    func record(_ name: String, _ body: (inout Digest, inout Inputs) -> Void) {
      var digest = Digest()
      var inputs = Inputs()
      for _ in 0..<samples { body(&digest, &inputs) }
      out[name] = digest.value
    }
    // Vectors
    record("dot.float3") { d, i in d.add(simd_dot(i.float3(), i.float3())) }
    record("dot.double3") { d, i in d.add(simd_dot(i.double3(), i.double3())) }
    record("dot.float2") { d, i in d.add(simd_dot(i.float2(), i.float2())) }
    record("dot.double4") { d, i in d.add(simd_dot(i.double4(), i.double4())) }
    record("length.float3") { d, i in d.add(simd_length(i.float3())) }
    record("length.double3") { d, i in d.add(simd_length(i.double3())) }
    record("length.float2") { d, i in d.add(simd_length(i.float2())) }
    record("length_squared.double3") { d, i in d.add(simd_length_squared(i.double3())) }
    record("distance.float3") { d, i in d.add(simd_distance(i.float3(), i.float3())) }
    record("distance.double3") { d, i in d.add(simd_distance(i.double3(), i.double3())) }
    record("distance_squared.float3") { d, i in d.add(simd_distance_squared(i.float3(), i.float3())) }
    record("normalize.float3") { d, i in d.add(simd_normalize(i.scaledFloat3())) }
    record("normalize.double3") { d, i in d.add(simd_normalize(i.scaledDouble3())) }
    record("normalize.float2") { d, i in d.add(simd_normalize(i.float2())) }
    record("cross.float3") { d, i in d.add(simd_cross(i.float3(), i.float3())) }
    record("cross.double3") { d, i in d.add(simd_cross(i.double3(), i.double3())) }
    record("overlay.cross_dot.double3") { d, i in
      let a = i.double3()
      let b = i.double3()
      d.add(cross(a, b))
      d.add(dot(a, b))
    }
    record("min.float3") { d, i in d.add(simd_min(i.edgyFloat3(), i.edgyFloat3())) }
    record("max.double3") { d, i in d.add(simd_max(i.edgyDouble3(), i.edgyDouble3())) }
    record("min.float") { d, i in d.add(simd_min(i.edgyFloat3().x, i.edgyFloat3().y)) }
    record("max.double") { d, i in d.add(simd_max(i.edgyDouble(), i.edgyDouble())) }
    record("clamp.float3") { d, i in
      let a = i.float3()
      let b = i.float3()
      d.add(simd_clamp(i.edgyFloat3(), simd_min(a, b), simd_max(a, b)))
    }
    record("clamp.double") { d, i in
      let a = i.double()
      let b = i.double()
      d.add(simd_clamp(i.edgyDouble(), Swift.min(a, b), Swift.max(a, b)))
    }
    record("min_max_clamp.int3") { d, i in
      let a = i.int3()
      let b = i.int3()
      let x = i.int3()
      d.add(simd_min(a, b))
      d.add(simd_max(a, b))
      d.add(simd_clamp(x, simd_min(a, b), simd_max(a, b)))
    }
    record("abs.float3") { d, i in d.add(simd_abs(i.edgyFloat3())) }
    record("overlay.abs.double3") { d, i in d.add(abs(i.edgyDouble3())) }
    record("reduce_min.float3") { d, i in d.add(simd_reduce_min(i.edgyFloat3())) }
    record("reduce_max.double3") { d, i in d.add(simd_reduce_max(i.edgyDouble3())) }
    record("floor.float3") { d, i in d.add(floor(i.float3())) }
    record("ceil_trunc_floor.double3") { d, i in
      let v = i.edgyDouble3()
      d.add(ceil(v))
      d.add(trunc(v))
      d.add(floor(v))
    }
    // Matrices
    record("matrix.vector.double3x3") { d, i in d.add(i.double3x3() * i.double3()) }
    record("simd_mul.vector.double3x3") { d, i in d.add(simd_mul(i.double3x3(), i.double3())) }
    record("vector.matrix.double3x3") { d, i in d.add(i.double3() * i.double3x3()) }
    record("matrix.matrix.double3x3") { d, i in d.add(i.double3x3() * i.double3x3()) }
    record("simd_mul.matrix.double3x3") { d, i in d.add(simd_mul(i.double3x3(), i.double3x3())) }
    record("determinant.double3x3") { d, i in d.add(simd_determinant(i.double3x3())) }
    record("inverse.double3x3") { d, i in d.add(simd_inverse(i.double3x3())) }
    record("transpose.double3x3") { d, i in
      let m = i.double3x3()
      d.add(m.transpose)
      d.add(simd_transpose(m))
    }
    record("rows.diagonal.double3x3") { d, i in
      d.add(simd_double3x3(rows: [i.double3(), i.double3(), i.double3()]))
      d.add(simd_double3x3(diagonal: i.double3()))
      d.add(matrix_identity_double3x3)
    }
    record("sum.double3x3") { d, i in
      let a = i.edgyDouble3x3()
      let b = i.edgyDouble3x3()
      var c = a
      c += b
      var e = a
      e -= b
      d.add(a + b)
      d.add(a - b)
      d.add(c)
      d.add(e)
    }
    record("negate.double3x3") { d, i in d.add(-i.edgyDouble3x3()) }
    record("scaled.double3x3") { d, i in
      let s = i.double()
      let m = i.double3x3()
      var n = m
      n *= s
      d.add(s * m)
      d.add(m * s)
      d.add(n)
    }
    record("product.assign.double3x3") { d, i in
      var m = i.double3x3()
      m *= i.double3x3()
      d.add(m)
    }
    record("equal.double3x3") { d, i in
      let a = i.edgyDouble3x3()
      var b = a
      b[i.index(), i.index()] = i.edgyDouble()
      d.add(bits: a == b ? 1 : 0)
      d.add(bits: a == a ? 1 : 0)
    }
    record("subscript.double3x3") { d, i in
      var m = i.double3x3()
      m[i.index()] = i.double3()
      m[i.index(), i.index()] = i.double()
      d.add(m)
      d.add(m[i.index()])
      d.add(m[i.index(), i.index()])
    }
    record("matrix.quatd.double3x3") { d, i in d.add(simd_double3x3(i.unitQuatd())) }
    record("matrix.vector.float3x3") { d, i in d.add(i.float3x3() * i.float3()) }
    record("matrix.matrix.float3x3") { d, i in d.add(i.float3x3() * i.float3x3()) }
    record("determinant.float3x3") { d, i in d.add(i.float3x3().determinant) }
    record("transpose.float3x3") { d, i in d.add(i.float3x3().transpose) }
    record("scaled.sum.float3x3") { d, i in
      var m = simd_float3x3()
      m += i.float3().x * i.float3x3()
      d.add(m)
    }
    record("sum.difference.float3x3") { d, i in
      let a = i.float3x3()
      let b = i.float3x3()
      var c = a
      c -= b
      d.add(a + b)
      d.add(a - b)
      d.add(c)
      d.add(b * i.float3().y)
      d.add(simd_float3x3(diagonal: i.float3()))
    }
    // Quaternions
    record("quatd.angle_axis") { d, i in
      d.add(simd_quatd(angle: i.double3().x, axis: simd_normalize(i.double3())).vector)
    }
    record("quatd.act") { d, i in d.add(i.quatd().act(i.double3())) }
    record("quatd.simd_act") { d, i in d.add(simd_act(i.quatd(), i.double3())) }
    record("quatd.product") { d, i in d.add((i.quatd() * i.quatd()).vector) }
    record("quatd.simd_mul") { d, i in d.add(simd_mul(i.quatd(), i.quatd()).vector) }
    record("quatd.inverse") { d, i in d.add(i.quatd().inverse.vector) }
    record("quatd.simd_inverse") { d, i in d.add(simd_inverse(i.quatd()).vector) }
    record("quatd.normalized") { d, i in d.add(simd_quatd(vector: i.double4()).normalized.vector) }
    record("quatd.simd_normalize") { d, i in d.add(simd_normalize(simd_quatd(vector: i.double4())).vector) }
    record("quatd.conjugate_length") { d, i in
      let q = i.quatd()
      d.add(q.conjugate.vector)
      d.add(q.length)
      d.add(q.real)
      d.add(q.imag)
    }
    record("quatd.sum_scaled") { d, i in
      let p = i.quatd()
      let q = i.quatd()
      let a = i.double()
      d.add((p + q).vector)
      d.add((p - q).vector)
      d.add((a * q).vector)
      d.add((q * a).vector)
      d.add(simd_quatd(ix: p.vector.x, iy: p.vector.y, iz: p.vector.z, r: p.vector.w).vector)
    }
    record("quatd.angle") { d, i in d.add(i.quatd().angle) }
    record("quatd.axis") { d, i in d.add(i.quatd().axis) }
    record("quatd.from_to") { d, i in
      d.add(simd_quatd(from: simd_normalize(i.double3()), to: simd_normalize(i.double3())).vector)
    }
    record("quatd.from_to.opposite") { d, i in
      let from = simd_normalize(i.double3())
      // Exactly opposite, and opposite but for a nudge of one part in 2^20 to 2^60.
      let nudge = Double(sign: .plus, exponent: -20 - Int(i.next() % 41), significand: 1)
      d.add(simd_quatd(from: from, to: -from).vector)
      d.add(simd_quatd(from: from, to: simd_normalize(-from + nudge * i.double3())).vector)
    }
    record("quatf.angle_axis") { d, i in
      d.add(simd_quatf(angle: i.float3().x, axis: simd_normalize(i.float3())).vector)
    }
    record("quatf.act") { d, i in
      let q = simd_quatf(vector: simd_normalize(i.float3()).x * SIMD4(i.float3(), i.float3().y))
      d.add(q.act(i.float3()))
    }
    record("quatf.product") { d, i in
      let p = simd_quatf(vector: SIMD4(i.float3(), i.float3().x))
      let q = simd_quatf(ix: i.float(), iy: i.float(), iz: i.float(), r: i.float())
      d.add((p * q).vector)
      d.add(q.real)
      d.add(q.imag)
    }
    return out
  }

  /// The two ways clang could have compiled `simd_cross`, written out, for telling which one
  /// this platform's is when its digest differs from the one recorded.
  static func crossVariants() -> (rounded: UInt64, fused: UInt64) {
    var rounded = Digest()
    var fused = Digest()
    var inputs = Inputs()
    for _ in 0..<samples {
      let a = inputs.float3()
      let b = inputs.float3()
      rounded.add(SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x))
      fused.add(
        SIMD3(
          (-(a.z * b.y)).addingProduct(a.y, b.z), (-(a.x * b.z)).addingProduct(a.z, b.x),
          (-(a.y * b.x)).addingProduct(a.x, b.y)))
    }
    return (rounded.value, fused.value)
  }

  struct Digest {
    var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func add(bits: UInt64) {
      for shift in stride(from: 0, to: 64, by: 8) {
        value ^= (bits >> UInt64(shift)) & 0xff
        value = value &* 0x0000_0100_0000_01b3
      }
    }

    mutating func add(_ x: Float) { add(bits: x.isNaN ? 0x7fc0_0000 : UInt64(x.bitPattern)) }

    mutating func add(_ x: Double) { add(bits: x.isNaN ? 0x7ff8_0000_0000_0000 : x.bitPattern) }

    mutating func add<V: SIMD>(_ v: V) where V.Scalar == Float { for k in v.indices { add(v[k]) } }

    mutating func add<V: SIMD>(_ v: V) where V.Scalar == Double { for k in v.indices { add(v[k]) } }

    mutating func add<V: SIMD>(_ v: V) where V.Scalar == Int32 {
      for k in v.indices { add(bits: UInt64(UInt32(bitPattern: v[k]))) }
    }

    mutating func add(_ m: simd_double3x3) {
      add(m.columns.0)
      add(m.columns.1)
      add(m.columns.2)
    }

    mutating func add(_ m: simd_float3x3) {
      add(m.columns.0)
      add(m.columns.1)
      add(m.columns.2)
    }
  }

  /// Fixed pseudo-random inputs (SplitMix64), the same on every machine.
  struct Inputs {
    var state: UInt64 = 0x2545_f491_4f6c_dd1d

    mutating func next() -> UInt64 {
      state = state &+ 0x9e37_79b9_7f4a_7c15
      var z = state
      z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
      z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
      return z ^ (z >> 31)
    }

    /// Uniform in [-8, 8), with 53 random bits.
    mutating func double() -> Double { Double(next() >> 11) * 0x1p-53 * 16 - 8 }

    mutating func float() -> Float { Float(double()) }

    /// A value or, one time in eight, a zero of either sign, a NaN or an infinity.
    mutating func edgyDouble() -> Double {
      switch next() % 32 {
      case 0: return 0
      case 1: return -0.0
      case 2: return .nan
      case 3: return .infinity
      default: return double()
      }
    }

    mutating func index() -> Int { Int(next() % 3) }

    mutating func int3() -> SIMD3<Int32> {
      SIMD3(Int32(truncatingIfNeeded: next()), Int32(truncatingIfNeeded: next()), Int32(truncatingIfNeeded: next()))
    }

    mutating func float2() -> SIMD2<Float> { SIMD2(float(), float()) }
    mutating func float3() -> SIMD3<Float> { SIMD3(float(), float(), float()) }
    mutating func double3() -> SIMD3<Double> { SIMD3(double(), double(), double()) }
    mutating func double4() -> SIMD4<Double> { SIMD4(double(), double(), double(), double()) }
    mutating func edgyFloat3() -> SIMD3<Float> {
      SIMD3(Float(edgyDouble()), Float(edgyDouble()), Float(edgyDouble()))
    }
    mutating func edgyDouble3() -> SIMD3<Double> { SIMD3(edgyDouble(), edgyDouble(), edgyDouble()) }

    /// Scaled by 2^-40 to 2^40, so that the reciprocal square roots see many exponents.
    mutating func scaledFloat3() -> SIMD3<Float> {
      float3() * Float(sign: .plus, exponent: Int(next() % 81) - 40, significand: 1)
    }

    mutating func scaledDouble3() -> SIMD3<Double> {
      double3() * Double(sign: .plus, exponent: Int(next() % 81) - 40, significand: 1)
    }

    mutating func double3x3() -> simd_double3x3 {
      simd_double3x3(columns: (double3(), double3(), double3()))
    }

    mutating func edgyDouble3x3() -> simd_double3x3 {
      simd_double3x3(columns: (edgyDouble3(), edgyDouble3(), edgyDouble3()))
    }

    mutating func float3x3() -> simd_float3x3 {
      simd_float3x3(columns: (float3(), float3(), float3()))
    }

    mutating func quatd() -> simd_quatd { simd_quatd(vector: double4() / 8) }

    /// A quaternion of length one but for rounding.
    mutating func unitQuatd() -> simd_quatd {
      let v = double4()
      return simd_quatd(vector: v / simd_length(v))
    }
  }
}
