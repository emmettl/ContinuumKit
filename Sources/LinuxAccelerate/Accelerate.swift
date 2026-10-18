// A Linux stand-in for the six vDSP calls that SpectralTransforms' RealFFT makes. The manifest
// builds it as a module named `Accelerate` on Linux only, so the frozen RealFFT.swift compiles
// there unchanged. Apple platforms never build it and keep using Accelerate itself.
//
// It reproduces vDSP's packed real-FFT convention: the forward transform returns twice the
// negative-exponent DFT, with the DC term in the real part and the Nyquist term in the imaginary
// part of element 0, and a forward and inverse pair together scale by 2n. The transform is a plain
// radix-2 FFT, so its results may differ from vDSP's in the last bits.

import Glibc

public typealias vDSP_Length = UInt
public typealias vDSP_Stride = Int
public typealias FFTRadix = Int32
public typealias FFTDirection = Int32

public let kFFTRadix2: Int32 = 0
public let kFFTDirection_Forward: Int32 = 1
public let kFFTDirection_Inverse: Int32 = -1

public struct DSPDoubleComplex {
  public var real: Double
  public var imag: Double

  public init(real: Double, imag: Double) {
    self.real = real
    self.imag = imag
  }
}

public struct DSPDoubleSplitComplex {
  public var realp: UnsafeMutablePointer<Double>
  public var imagp: UnsafeMutablePointer<Double>

  public init(realp: UnsafeMutablePointer<Double>, imagp: UnsafeMutablePointer<Double>) {
    self.realp = realp
    self.imagp = imagp
  }
}

/// Twiddle factors for complex transforms of every power-of-two length up to 2^log2n.
public final class FFTSetupD {
  let log2n: Int
  // cos and sin of 2πk / 2^log2n for k below half that length.
  let cosines: [Double]
  let sines: [Double]

  init(log2n: Int) {
    self.log2n = log2n
    let n = 1 << log2n
    let half = max(n / 2, 1)
    cosines = (0..<half).map { cos(2 * Double.pi * Double($0) / Double(n)) }
    sines = (0..<half).map { sin(2 * Double.pi * Double($0) / Double(n)) }
  }

  /// In-place complex FFT of length 2^m, m <= log2n, with exponent sign `sign`.
  func complexTransform(_ re: inout [Double], _ im: inout [Double], sign: Double) {
    let n = re.count
    guard n > 1 else { return }
    var j = 0
    for i in 1..<n {
      var bit = n >> 1
      while j & bit != 0 {
        j ^= bit
        bit >>= 1
      }
      j |= bit
      if i < j {
        re.swapAt(i, j)
        im.swapAt(i, j)
      }
    }
    let tableLength = 1 << log2n
    var size = 2
    while size <= n {
      let halfSize = size / 2
      let step = tableLength / size
      var start = 0
      while start < n {
        for k in 0..<halfSize {
          let c = cosines[k * step], s = sign * sines[k * step]
          let a = start + k, b = a + halfSize
          let tr = re[b] * c - im[b] * s
          let ti = re[b] * s + im[b] * c
          re[b] = re[a] - tr
          im[b] = im[a] - ti
          re[a] += tr
          im[a] += ti
        }
        start += size
      }
      size <<= 1
    }
  }
}

public func vDSP_create_fftsetupD(_ log2n: vDSP_Length, _ radix: FFTRadix) -> FFTSetupD? {
  guard radix == kFFTRadix2, log2n < 48 else { return nil }
  return FFTSetupD(log2n: Int(log2n))
}

public func vDSP_destroy_fftsetupD(_ setup: FFTSetupD?) {}

/// Copies interleaved complex values into split form. `strideC` counts doubles, as vDSP's does.
public func vDSP_ctozD(
  _ c: UnsafePointer<DSPDoubleComplex>, _ strideC: vDSP_Stride,
  _ z: UnsafePointer<DSPDoubleSplitComplex>, _ strideZ: vDSP_Stride, _ count: vDSP_Length
) {
  let split = z.pointee
  for k in 0..<Int(count) {
    let value = c[k * strideC / 2]
    split.realp[k * strideZ] = value.real
    split.imagp[k * strideZ] = value.imag
  }
}

/// Copies split complex values into interleaved form. `strideC` counts doubles, as vDSP's does.
public func vDSP_ztocD(
  _ z: UnsafePointer<DSPDoubleSplitComplex>, _ strideZ: vDSP_Stride,
  _ c: UnsafeMutablePointer<DSPDoubleComplex>, _ strideC: vDSP_Stride, _ count: vDSP_Length
) {
  let split = z.pointee
  for k in 0..<Int(count) {
    c[k * strideC / 2] = DSPDoubleComplex(real: split.realp[k * strideZ], imag: split.imagp[k * strideZ])
  }
}

/// In-place real FFT of 2^log2n samples held as packed split complex values.
public func vDSP_fft_zripD(
  _ setup: FFTSetupD, _ z: UnsafePointer<DSPDoubleSplitComplex>, _ stride: vDSP_Stride,
  _ log2n: vDSP_Length, _ direction: FFTDirection
) {
  let n = 1 << Int(log2n)
  precondition(Int(log2n) <= setup.log2n && n >= 2, "FFT length exceeds its setup")
  let half = n / 2
  let split = z.pointee
  if direction == kFFTDirection_Forward {
    // Unpack samples x[2k] + i x[2k+1], transform, and keep twice the non-negative bins.
    var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
    for k in 0..<half {
      re[2 * k] = split.realp[k * stride]
      re[2 * k + 1] = split.imagp[k * stride]
    }
    setup.complexTransform(&re, &im, sign: -1)
    split.realp[0] = 2 * re[0]
    split.imagp[0] = 2 * re[half]
    for k in 1..<half {
      split.realp[k * stride] = 2 * re[k]
      split.imagp[k * stride] = 2 * im[k]
    }
  } else {
    // Rebuild the Hermitian spectrum, sum it with the positive exponent and repack the samples.
    var re = [Double](repeating: 0, count: n), im = [Double](repeating: 0, count: n)
    re[0] = split.realp[0]
    re[half] = split.imagp[0]
    for k in 1..<half {
      re[k] = split.realp[k * stride]
      im[k] = split.imagp[k * stride]
      re[n - k] = re[k]
      im[n - k] = -im[k]
    }
    setup.complexTransform(&re, &im, sign: 1)
    for k in 0..<half {
      split.realp[k * stride] = re[2 * k]
      split.imagp[k * stride] = re[2 * k + 1]
    }
  }
}
