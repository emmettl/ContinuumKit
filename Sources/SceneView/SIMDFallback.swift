import Foundation

// The simd module is Apple-only. These stand in for the few functions this module
// uses so that it also builds on Linux; Apple platforms keep using simd itself.
#if !canImport(simd)
    @inline(__always)
    func simd_length(_ v: SIMD3<Float>) -> Float {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }

    @inline(__always)
    func simd_normalize(_ v: SIMD3<Float>) -> SIMD3<Float> { v / simd_length(v) }

    @inline(__always)
    func simd_cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
#endif
