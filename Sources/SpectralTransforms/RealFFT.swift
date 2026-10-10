// Extracted from RoomCAD, MIT; see docs/extraction/REAL_FFT.md.
import Accelerate

/// Power-of-two real FFT in vDSP's packed format: element 0 of a spectrum holds the DC term in its real
/// part and the Nyquist term in its imaginary part. Forward uses twice the
/// negative-exponent DFT. Reuse serially; concurrent setup access is unsupported.
public final class RealFFT {
    public typealias Spectrum = (real: [Double], imag: [Double])
    public let length: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetupD

    public init(length: Int) throws {
        guard Self.validLength(length) else { throw TransformError.invalidLength }
        self.length = length
        log2n = vDSP_Length(length.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else {
            throw TransformError.setupUnavailable
        }
        self.setup = setup
    }

    deinit { vDSP_destroy_fftsetupD(setup) }

    /// Spectrum of `signal`, which must have `length` samples. vDSP scales it by 2.
    public func forward(_ signal: [Double]) throws -> Spectrum {
        guard signal.count == length else { throw TransformError.invalidDimensions }
        try Self.requireFinite(signal)
        let half = length / 2
        var real = [Double](repeating: 0, count: half)
        var imag = [Double](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPDoubleSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                signal.withUnsafeBytes { raw in
                    vDSP_ctozD(
                        raw.bindMemory(to: DSPDoubleComplex.self).baseAddress!, 2, &split, 1,
                        vDSP_Length(half))
                }
                vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        try Self.requireFinite(real, output: true)
        try Self.requireFinite(imag, output: true)
        return (real, imag)
    }

    /// Signal whose `forward` spectrum is given, so `inverse(forward(x)) == x`.
    public func inverse(real: [Double], imag: [Double]) throws -> [Double] {
        let half = length / 2
        guard real.count == half, imag.count == half else { throw TransformError.invalidDimensions }
        try Self.requireFinite(real)
        try Self.requireFinite(imag)
        var real = real
        var imag = imag
        var output = [Double](repeating: 0, count: length)
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPDoubleSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                vDSP_fft_zripD(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Inverse))
                output.withUnsafeMutableBytes { raw in
                    vDSP_ztocD(
                        &split, 1, raw.bindMemory(to: DSPDoubleComplex.self).baseAddress!, 2,
                        vDSP_Length(half))
                }
            }
        }
        // A forward and inverse transform together scale by 2n.
        let scale = 1 / Double(2 * length)
        let scaled = output.map { $0 * scale }
        try Self.requireFinite(scaled, output: true)
        return scaled
    }

    /// Adds `spectrum` weighted by a real, zero-phase frequency response into `sum`.
    public static func accumulate(
        _ spectrum: (real: [Double], imag: [Double]), into sum: inout (real: [Double], imag: [Double]),
        sampleRate: Double, response: (Double) -> Double
    ) throws {
        let half = spectrum.real.count
        guard half > 0, half <= Int.max / 2, validLength(2 * half),
            spectrum.imag.count == half, sum.real.count == half, sum.imag.count == half
        else { throw TransformError.invalidDimensions }
        try requireRate(sampleRate)
        try requireFinite(spectrum.real)
        try requireFinite(spectrum.imag)
        try requireFinite(sum.real)
        try requireFinite(sum.imag)
        // Commit only after every coefficient and output passes. Response callbacks
        // occur in the original order: DC, Nyquist, then interior ascending bins.
        var candidate = sum
        func weight(_ frequency: Double) throws -> Double {
            let w = response(frequency)
            guard w.isFinite else { throw TransformError.nonFiniteResponse }
            return w
        }
        let binWidth = sampleRate / Double(2 * half)
        candidate.real[0] += spectrum.real[0] * (try weight(0))
        candidate.imag[0] += spectrum.imag[0] * (try weight(sampleRate / 2))
        for k in 1..<half {
            let w = try weight(Double(k) * binWidth)
            candidate.real[k] += spectrum.real[k] * w
            candidate.imag[k] += spectrum.imag[k] * w
        }
        try requireFinite(candidate.real, output: true)
        try requireFinite(candidate.imag, output: true)
        sum = candidate
    }

    /// Right-pad to the smallest power of two >= count + padding, apply the
    /// sampled real response by circular filtering, and retain the original prefix.
    /// Padding does not promise absent wrap for an arbitrary impulse response.
    public static func zeroPhaseFilter(
        _ signal: [Float], sampleRate: Double, padding: Int = 1 << 14, response: (Double) -> Double
    ) throws -> [Float] {
        try requireRate(sampleRate)
        try requireFinite(signal.map(Double.init))
        let length = try paddedLength(count: signal.count, padding: padding)
        let fft = try RealFFT(length: length)
        var padded = [Double](repeating: 0, count: length)
        for (i, value) in signal.enumerated() { padded[i] = Double(value) }
        var filtered = (
            real: [Double](repeating: 0, count: length / 2), imag: [Double](repeating: 0, count: length / 2)
        )
        try accumulate(fft.forward(padded), into: &filtered, sampleRate: sampleRate, response: response)
        let output = try fft.inverse(real: filtered.real, imag: filtered.imag)
        return try finiteFloats(Array(output.prefix(signal.count)))
    }
    /// Checked storage planning, without allocating or constructing a setup.
    public static func paddedLength(count: Int, padding: Int = 0) throws -> Int {
        guard count >= 0, padding >= 0 else { throw TransformError.invalidPadding }
        let (required, overflow) = count.addingReportingOverflow(padding)
        guard !overflow, required <= Int.max / 2 else { throw TransformError.countOverflow }
        var length = 2
        while length < required {
            guard length <= Int.max / 4 else { throw TransformError.countOverflow }
            length <<= 1
        }
        return length
    }

    private static func validLength(_ length: Int) -> Bool {
        length >= 2 && length <= Int.max / 2 && length & (length - 1) == 0
    }
    private static func requireRate(_ sampleRate: Double) throws {
        guard sampleRate.isFinite, sampleRate > 0 else { throw TransformError.invalidSampleRate }
    }
    fileprivate static func requireFinite(_ values: [Double], output: Bool = false) throws {
        guard values.allSatisfy(\.isFinite) else {
            throw output ? TransformError.nonFiniteOutput : TransformError.nonFiniteInput
        }
    }
    fileprivate static func finiteFloats(_ values: [Double]) throws -> [Float] {
        let result = values.map(Float.init)
        guard result.allSatisfy(\.isFinite) else { throw TransformError.floatOverflow }
        return result
    }
}

/// Checked boundary failures; no partial spectrum or accumulated sum is returned.
public enum TransformError: String, Error, Equatable, Sendable {
    case invalidLength, setupUnavailable, invalidDimensions, invalidPadding, countOverflow
    case invalidSampleRate, nonFiniteInput, nonFiniteResponse, nonFiniteOutput, floatOverflow
}

/// Linear convolution by FFT, accumulated in double precision.
public enum Convolution {
    /// The full convolution of `signal` with `response`: `signal.count + response.count - 1` samples.
    public static func convolve(_ signal: [Float], _ response: [Float]) throws -> [Float] {
        guard !signal.isEmpty, !response.isEmpty else { return [] }
        try RealFFT.requireFinite(signal.map(Double.init))
        try RealFFT.requireFinite(response.map(Double.init))
        let (total, overflow) = signal.count.addingReportingOverflow(response.count)
        guard !overflow else { throw TransformError.countOverflow }
        let count = total - 1
        let length = try RealFFT.paddedLength(count: count)
        let fft = try RealFFT(length: length)
        func padded(_ values: [Float]) -> [Double] {
            var result = [Double](repeating: 0, count: length)
            for (i, value) in values.enumerated() { result[i] = Double(value) }
            return result
        }
        let a = try fft.forward(padded(signal))
        let b = try fft.forward(padded(response))
        var real = [Double](repeating: 0, count: length / 2)
        var imag = [Double](repeating: 0, count: length / 2)
        // Packed element 0 holds two independent real terms; the rest are complex products. Each forward
        // transform carries a factor of 2, so halve the product to keep one.
        real[0] = a.real[0] * b.real[0] / 2
        imag[0] = a.imag[0] * b.imag[0] / 2
        for k in 1..<(length / 2) {
            real[k] = (a.real[k] * b.real[k] - a.imag[k] * b.imag[k]) / 2
            imag[k] = (a.real[k] * b.imag[k] + a.imag[k] * b.real[k]) / 2
        }
        let output = try fft.inverse(real: real, imag: imag)
        return try RealFFT.finiteFloats(Array(output.prefix(count)))
    }
}
