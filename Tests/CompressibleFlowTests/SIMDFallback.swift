import Foundation

// The simd module is Apple-only. These stand in for the few functions the tests use
// so that they also build on Linux; Apple platforms keep using simd itself.
#if !canImport(simd)
  func simd_dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
    a.x * b.x + a.y * b.y + a.z * b.z
  }

  func simd_length_squared(_ v: SIMD3<Double>) -> Double { simd_dot(v, v) }

  func simd_length(_ v: SIMD3<Double>) -> Double { sqrt(simd_length_squared(v)) }
#endif
