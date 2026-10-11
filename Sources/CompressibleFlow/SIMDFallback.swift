// The simd module is Apple-only. These stand in for the few functions this module
// uses so that it also builds on Linux; Apple platforms keep using simd itself.
#if !canImport(simd)
  @inline(__always)
  func simd_dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
    a.x * b.x + a.y * b.y + a.z * b.z
  }

  @inline(__always)
  func simd_length_squared(_ v: SIMD3<Double>) -> Double { simd_dot(v, v) }
#endif
