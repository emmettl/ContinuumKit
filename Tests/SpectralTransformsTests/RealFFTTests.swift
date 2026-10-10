import Foundation
import Testing
import SpectralTransforms

private func packedDFT(_ x: [Double]) -> RealFFT.Spectrum {
    let n = x.count
    var r = [Double](repeating: 0, count: n / 2)
    var i = r
    r[0] = 2 * x.reduce(0, +)
    i[0] = 2 * x.enumerated().reduce(0) { $0 + ($1.offset.isMultiple(of: 2) ? $1.element : -$1.element) }
    if n > 2 {
        for k in 1..<(n / 2) {
            for j in 0..<n {
                let angle = 2 * Double.pi * Double(k * j) / Double(n)
                r[k] += 2 * x[j] * cos(angle)
                i[k] -= 2 * x[j] * sin(angle)
            }
        }
    }
    return (r, i)
}
private func directInverse(_ s: RealFFT.Spectrum) -> [Double] {
    let n = 2 * s.real.count
    return (0..<n).map { j in
        var value = s.real[0] + (j.isMultiple(of: 2) ? s.imag[0] : -s.imag[0])
        if n > 2 {
            for k in 1..<(n / 2) {
                let angle = 2 * Double.pi * Double(k * j) / Double(n)
                value += 2 * (s.real[k] * cos(angle) - s.imag[k] * sin(angle))
            }
        }
        return value / Double(2 * n)
    }
}
private func close(_ a: [Double], _ b: [Double], scale: Double = 1) {
    #expect(a.count == b.count)
    for (x, y) in zip(a, b) { #expect(abs(x - y) <= 2e-11 * max(scale, abs(y))) }
}

@Suite struct RealFFTTests {
    @Test func packedEndpointsSignsAndAllBins() throws {
        for n in [2, 4, 8, 16, 32] {
            let fft = try RealFFT(length: n)
            var signals = [[Double](repeating: 1.25, count: n), (0..<n).map { $0.isMultiple(of: 2) ? 0.75 : -0.75 }, (0..<n).map { Double(($0 * 7) % 13 - 6) / 8 }]
            for j in [0, 1, n / 2, n - 1] { var x = [Double](repeating: 0, count: n); x[j] = 1; signals.append(x) }
            if n > 2 {
                for k in 1..<(n / 2) {
                    signals.append((0..<n).map { cos(2 * .pi * Double(k * $0) / Double(n) + 0.37) })
                    signals.append((0..<n).map { sin(2 * .pi * Double(k * $0) / Double(n)) })
                }
            }
            for x in signals {
                let actual = try fft.forward(x), reference = packedDFT(x)
                close(actual.real, reference.real, scale: Double(n))
                close(actual.imag, reference.imag, scale: Double(n))
                close(try fft.inverse(real: actual.real, imag: actual.imag), x)
                let spectral = (actual.real[0] * actual.real[0] + actual.imag[0] * actual.imag[0] + 2 * zip(actual.real.dropFirst(), actual.imag.dropFirst()).reduce(0) { $0 + $1.0 * $1.0 + $1.1 * $1.1 }) / Double(4 * n)
                #expect(abs(spectral - x.reduce(0) { $0 + $1 * $1 }) < 1e-10 * Double(n))
            }
        }
    }
    @Test func inverseOfIndependentlyConstructedSpectrum() throws {
        for n in [2, 4, 8, 32] {
            let s = (real: (0..<(n / 2)).map { Double($0 + 1) / 4 }, imag: (0..<(n / 2)).map { -Double($0 + 2) / 8 })
            close(try RealFFT(length: n).inverse(real: s.real, imag: s.imag), directInverse(s))
        }
    }
    @Test func weightedSumFrequenciesAndNegativeGains() throws {
        let fft = try RealFFT(length: 8)
        let s = try fft.forward([1, 2, 0, -1, 3, 0, 1, -2])
        var sum: RealFFT.Spectrum = ([1, 2, 3, 4], [-1, -2, -3, -4])
        var frequencies: [Double] = []
        try RealFFT.accumulate(s, into: &sum, sampleRate: 8) { f in frequencies.append(f); return 1 - f / 2 }
        #expect(frequencies == [0, 4, 1, 2, 3])
        close(sum.real, [1 + s.real[0], 2 + 0.5 * s.real[1], 3, 4 - 0.5 * s.real[3]])
        close(sum.imag, [-1 - s.imag[0], -2 + 0.5 * s.imag[1], -3, -4 - 0.5 * s.imag[3]])
        try RealFFT.accumulate(s, into: &sum, sampleRate: 8) { _ in -1 }
        close(sum.real, [1, 2 - 0.5 * s.real[1], 3 - s.real[2], 4 - 1.5 * s.real[3]])
    }
    @Test func circularFilterAndPrefixAreExplicit() throws {
        let x: [Float] = [1, 2, -1, 0, 3]
        for padding in [0, 1, 5, 16] {
            let n = try RealFFT.paddedLength(count: x.count, padding: padding)
            let padded = x.map(Double.init) + [Double](repeating: 0, count: n - x.count)
            let expected = (0..<x.count).map { padded[$0] + 0.25 * (padded[($0 + n - 1) % n] + padded[($0 + 1) % n]) }
            let y = try RealFFT.zeroPhaseFilter(x, sampleRate: 8, padding: padding) { 1 + 0.5 * cos(2 * .pi * $0 / 8) }
            close(y.map(Double.init), expected)
        }
        #expect(try RealFFT.zeroPhaseFilter([], sampleRate: 8, padding: 0) { _ in 1 }.isEmpty)
    }
    @Test func fullLinearConvolutionAgainstDirectSums() throws {
        for m in [1, 2, 3, 7, 8, 9, 17] {
            for n in [1, 2, 3, 7, 9] {
                let a = (0..<m).map { Float(($0 * 7) % 11 - 5) / 8 }
                let b = (0..<n).map { Float(($0 * 3) % 7 - 3) / 4 }
                var y = [Double](repeating: 0, count: m + n - 1)
                for i in 0..<m { for j in 0..<n { y[i + j] += Double(a[i]) * Double(b[j]) } }
                close(try Convolution.convolve(a, b).map(Double.init), y)
            }
        }
        #expect(try Convolution.convolve([], [.nan]).isEmpty)
        #expect(try Convolution.convolve([1], []).isEmpty)
    }
    @Test func constructorAndStorageOverflow() throws {
        for n in [Int.min, -1, 0, 1, 3, 6, Int.max] { #expect(throws: TransformError.invalidLength) { try RealFFT(length: n) } }
        #expect(try RealFFT.paddedLength(count: 0) == 2)
        #expect(try RealFFT.paddedLength(count: 8, padding: 1) == 16)
        #expect(try RealFFT.paddedLength(count: 1 << 61) == 1 << 61)
        for (n, p) in [(Int.max, 1), (Int.max, 0), (1 << 61, 1)] { #expect(throws: TransformError.countOverflow) { try RealFFT.paddedLength(count: n, padding: p) } }
        #expect(throws: TransformError.invalidPadding) { try RealFFT.paddedLength(count: -1) }
        #expect(throws: TransformError.invalidPadding) { try RealFFT.paddedLength(count: 1, padding: -1) }
    }
    @Test func dimensionsRejectBeforePointerAccess() throws {
        let fft = try RealFFT(length: 4)
        #expect(throws: TransformError.invalidDimensions) { try fft.forward([1]) }
        let invalid: [RealFFT.Spectrum] = [([], []), ([1, 2], [1]), ([1, 2, 3], [1, 2, 3])]
        for s in invalid {
            #expect(throws: TransformError.invalidDimensions) { try fft.inverse(real: s.real, imag: s.imag) }
        }
        var sum: RealFFT.Spectrum = ([1, 2], [3, 4])
        #expect(throws: TransformError.invalidDimensions) { try RealFFT.accumulate(([], []), into: &sum, sampleRate: 8) { _ in 1 } }
        #expect(sum.real == [1, 2] && sum.imag == [3, 4])
    }
    @Test func nonFiniteInputsRatesAndCoefficients() throws {
        let fft = try RealFFT(length: 2)
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: TransformError.nonFiniteInput) { try fft.forward([value, 0]) }
            #expect(throws: TransformError.nonFiniteInput) { try fft.inverse(real: [0], imag: [value]) }
        }
        for rate in [0, -1, Double.nan, .infinity] {
            #expect(throws: TransformError.invalidSampleRate) { try RealFFT.zeroPhaseFilter([1], sampleRate: rate, padding: 0) { _ in 1 } }
        }
        #expect(throws: TransformError.nonFiniteInput) { try Convolution.convolve([.nan], [1]) }
        #expect(throws: TransformError.invalidPadding) { try RealFFT.zeroPhaseFilter([1], sampleRate: 8, padding: -1) { _ in 1 } }
    }
    @Test func accumulationRollbackAfterLateResponseFailure() throws {
        let s: RealFFT.Spectrum = ([1, 2, 3, 4], [5, 6, 7, 8])
        var sum = s
        #expect(throws: TransformError.nonFiniteResponse) { try RealFFT.accumulate(s, into: &sum, sampleRate: 8) { $0 == 3 ? .nan : 2 } }
        #expect(sum.real == s.real && sum.imag == s.imag)
        #expect(throws: TransformError.nonFiniteOutput) { try RealFFT.accumulate(s, into: &sum, sampleRate: 8) { _ in .greatestFiniteMagnitude } }
        #expect(sum.real == s.real && sum.imag == s.imag)
    }
    @Test func finiteArithmeticAndFloatOverflowReject() throws {
        #expect(throws: TransformError.nonFiniteOutput) { try RealFFT(length: 2).forward([.greatestFiniteMagnitude, .greatestFiniteMagnitude]) }
        #expect(throws: TransformError.nonFiniteOutput) { try RealFFT(length: 2).inverse(real: [.greatestFiniteMagnitude], imag: [.greatestFiniteMagnitude]) }
        #expect(throws: TransformError.floatOverflow) { try Convolution.convolve([.greatestFiniteMagnitude], [2]) }
        #expect(throws: TransformError.floatOverflow) { try RealFFT.zeroPhaseFilter([.greatestFiniteMagnitude], sampleRate: 8, padding: 0) { _ in 2 } }
    }
}
