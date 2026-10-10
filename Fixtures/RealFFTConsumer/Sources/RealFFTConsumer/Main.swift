import Foundation
import SpectralTransforms

@main struct Main {
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CONTINUUMKIT_REAL_FFT_OUTPUT"]!)
        func vector(_ x: [Double]) -> [String: Any] {
            ["values": x, "bits": x.map { String($0.bitPattern, radix: 16) }]
        }
        func floats(_ x: [Float]) -> [String: Any] {
            ["values": x.map(Double.init), "bits": x.map { String($0.bitPattern, radix: 16) }]
        }
        func input(_ n: Int, _ profile: String) -> [Double] {
            switch profile {
            case "dc": return [Double](repeating: 1.25, count: n)
            case "nyquist": return (0..<n).map { $0.isMultiple(of: 2) ? 0.75 : -0.75 }
            case "mixed": return (0..<n).map { Double(($0 * 7) % 13 - 6) / 8 }
            default:
                let components = profile.split(separator: "-")
                let k = Int(components[1])!
                if components[0] == "impulse" { var x = [Double](repeating: 0, count: n); x[k] = 1; return x }
                return (0..<n).map { j in
                    let phase = 2 * Double.pi * Double(k * j) / Double(n)
                    return components[0] == "cos" ? cos(phase + 0.37) : sin(phase)
                }
            }
        }
        func gain(_ name: String, _ f: Double, _ rate: Double) -> Double {
            switch name {
            case "identity": return 1
            case "dcReject": return f == 0 ? 0 : 1
            case "tilt": return 1 - 4 * f / rate
            default: return 1 + 0.5 * cos(2 * .pi * f / rate)
            }
        }
        for shared in [false, true] {
            var records: [[String: Any]] = []
            for n in [2, 4, 8, 16, 32] {
                let original = RealFFT(length: n)
                let extracted = try SpectralTransforms.RealFFT(length: n)
                func forward(_ x: [Double]) throws -> SpectralTransforms.RealFFT.Spectrum {
                    shared ? try extracted.forward(x) : original.forward(x)
                }
                func inverse(_ r: [Double], _ i: [Double]) throws -> [Double] {
                    shared ? try extracted.inverse(real: r, imag: i) : original.inverse(real: r, imag: i)
                }
                var profiles = ["dc", "nyquist", "mixed"] + Set([0, 1, n / 2, n - 1]).sorted().map { "impulse-\($0)" }
                if n > 2 { for k in 1..<(n / 2) { profiles += ["cos-\(k)", "sin-\(k)"] } }
                for profile in profiles {
                    let x = input(n, profile), s = try forward(x), y = try inverse(s.real, s.imag)
                    records.append(["id": "forward/\(n)/\(profile)", "kind": "forward", "n": n, "profile": profile, "input": vector(x), "real": vector(s.real), "imag": vector(s.imag), "output": vector(y)])
                }
                for pattern in 0..<4 {
                    let r = (0..<(n / 2)).map { Double(($0 * 5 + pattern * 3) % 11 - 5) / 4 }
                    let i = (0..<(n / 2)).map { Double(($0 * 3 + pattern * 7) % 13 - 6) / 8 }
                    records.append(["id": "inverse/\(n)/\(pattern)", "kind": "inverse", "n": n, "pattern": pattern, "real": vector(r), "imag": vector(i), "output": vector(try inverse(r, i))])
                }
                for rate in [8.0, 44100, 48000] {
                    for response in ["identity", "dcReject", "tilt", "center3tap"] {
                        var sum = (real: (0..<(n / 2)).map { Double($0 + 1) / 8 }, imag: (0..<(n / 2)).map { -Double($0 + 1) / 16 })
                        let seed = sum
                        var frequencies: [Double] = []
                        var spectra: [[String: Any]] = []
                        for profile in ["mixed", "nyquist"] {
                            let x = input(n, profile), s = try forward(x)
                            spectra.append(["input": vector(x), "real": vector(s.real), "imag": vector(s.imag)])
                            let responseBlock: (Double) -> Double = { f in frequencies.append(f); return gain(response, f, rate) }
                            if shared { try SpectralTransforms.RealFFT.accumulate(s, into: &sum, sampleRate: rate, response: responseBlock) }
                            else { RealFFT.accumulate(s, into: &sum, sampleRate: rate, response: responseBlock) }
                        }
                        records.append(["id": "accumulate/\(n)/\(Int(rate))/\(response)", "kind": "accumulate", "n": n, "rate": rate, "response": response, "spectra": spectra, "seedReal": vector(seed.real), "seedImag": vector(seed.imag), "real": vector(sum.real), "imag": vector(sum.imag), "frequencies": vector(frequencies), "output": vector(try inverse(sum.real, sum.imag))])
                    }
                }
            }
            for count in [0, 1, 3, 8, 17] {
                for padding in [0, 1, 5, 16] {
                    for response in ["identity", "dcReject", "tilt", "center3tap"] {
                        let x = (0..<count).map { Float(($0 * 7) % 13 - 6) / 8 }
                        let rate = 48000.0
                        let y: [Float]
                        var frequencies: [Double] = []
                        let responseBlock: (Double) -> Double = { f in frequencies.append(f); return gain(response, f, rate) }
                        if shared { y = try SpectralTransforms.RealFFT.zeroPhaseFilter(x, sampleRate: rate, padding: padding, response: responseBlock) }
                        else { y = RealFFT.zeroPhaseFilter(x, sampleRate: rate, padding: padding, response: responseBlock) }
                        records.append(["id": "filter/\(count)/\(padding)/\(response)", "kind": "filter", "count": count, "padding": padding, "n": try SpectralTransforms.RealFFT.paddedLength(count: count, padding: padding), "rate": rate, "response": response, "input": floats(x), "output": floats(y), "frequencies": vector(frequencies)])
                    }
                }
            }
            for m in [0, 1, 2, 3, 7, 8, 9, 17] {
                for n in [0, 1, 2, 3, 7, 8, 9, 17] {
                    for profile in ["impulse", "mixed", "nyquist"] {
                        let a: [Float] = (0..<m).map { j in profile == "impulse" ? (j == m - 1 ? 1 : 0) : profile == "nyquist" ? (j.isMultiple(of: 2) ? 1 : -1) : Float((j * 7) % 11 - 5) / 8 }
                        let b: [Float] = (0..<n).map { j in profile == "impulse" ? (j == 0 ? 0.5 : 0) : profile == "nyquist" ? (j.isMultiple(of: 2) ? 0.75 : -0.75) : Float((j * 3) % 7 - 3) / 4 }
                        let y = shared ? try SpectralTransforms.Convolution.convolve(a, b) : Convolution.convolve(a, b)
                        records.append(["id": "convolution/\(m)/\(n)/\(profile)", "kind": "convolution", "m": m, "n": n, "profile": profile, "input": floats(a), "responseInput": floats(b), "output": floats(y)])
                    }
                }
            }
            let data = try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys])
            try data.write(to: root.appendingPathComponent(shared ? "shared.json" : "original.json"))
            print("PASS \(shared ? "shared" : "original") \(records.count) complete FFT records")
        }
        var failures: [[String: Any]] = []
        func failure(_ id: String, _ expected: TransformError, _ body: () throws -> Void) throws {
            do { try body(); throw NSError(domain: "Accepted invalid FFT input: \(id)", code: 1) }
            catch let error as TransformError {
                guard error == expected else { throw error }
                failures.append(["id": id, "error": error.rawValue])
            }
        }
        let fft = try SpectralTransforms.RealFFT(length: 4)
        for n in [-1, 0, 1, 3, Int.max] { try failure("length/\(n)", .invalidLength) { _ = try SpectralTransforms.RealFFT(length: n) } }
        try failure("forward/count", .invalidDimensions) { _ = try fft.forward([1]) }
        try failure("inverse/empty", .invalidDimensions) { _ = try fft.inverse(real: [], imag: []) }
        try failure("inverse/short", .invalidDimensions) { _ = try fft.inverse(real: [1, 2], imag: [1]) }
        try failure("forward/nan", .nonFiniteInput) { _ = try fft.forward([1, .nan, 2, 3]) }
        try failure("inverse/infinity", .nonFiniteInput) { _ = try fft.inverse(real: [.infinity, 0], imag: [0, 0]) }
        for rate in [0.0, -1, .infinity] { try failure("rate/\(rate)", .invalidSampleRate) { _ = try SpectralTransforms.RealFFT.zeroPhaseFilter([1], sampleRate: rate, padding: 0) { _ in 1 } } }
        try failure("padding/negative", .invalidPadding) { _ = try SpectralTransforms.RealFFT.paddedLength(count: 1, padding: -1) }
        try failure("count/overflow", .countOverflow) { _ = try SpectralTransforms.RealFFT.paddedLength(count: Int.max, padding: 1) }
        try failure("count/roundingOverflow", .countOverflow) { _ = try SpectralTransforms.RealFFT.paddedLength(count: 1 << 61, padding: 1) }
        var sum: SpectralTransforms.RealFFT.Spectrum = ([1, 2], [3, 4])
        try failure("accumulate/dimensions", .invalidDimensions) { try SpectralTransforms.RealFFT.accumulate(([], []), into: &sum, sampleRate: 8) { _ in 1 } }
        try failure("accumulate/coefficient", .nonFiniteResponse) { try SpectralTransforms.RealFFT.accumulate(([1, 2], [3, 4]), into: &sum, sampleRate: 8) { $0 == 2 ? .nan : 1 } }
        guard sum.real == [1, 2], sum.imag == [3, 4] else { throw NSError(domain: "Failed rollback", code: 1) }
        try failure("convolution/nan", .nonFiniteInput) { _ = try SpectralTransforms.Convolution.convolve([.nan], [1]) }
        try failure("convolution/floatOverflow", .floatOverflow) { _ = try SpectralTransforms.Convolution.convolve([.greatestFiniteMagnitude], [2]) }
        try JSONSerialization.data(withJSONObject: failures, options: [.sortedKeys]).write(to: root.appendingPathComponent("failures.json"))
        print("PASS \(failures.count) checked failures and transactional accumulation")
    }
}
