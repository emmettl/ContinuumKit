import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
var records: [[String: Any]] = []
func vector(_ x: [Double]) -> [String: Any] {
    ["values": x.map { String($0) }, "bits": x.map { String($0.bitPattern, radix: 16) }]
}
func scalar(_ x: Double) -> [String: String] { ["value": String(x), "bits": String(x.bitPattern, radix: 16)] }
for count in [2, 3, 8, 17, 64, 257] {
    for offset in [0, 1000, 1_000_000, 1_000_000_000, 1 << 40, 1 << 53] {
        for profile in ["line", "perturbed", "constant"] {
            let y = (0..<count).map { i in
                profile == "constant" ? -10.0 : -10 - Double(i) / 16 + (profile == "perturbed" ? Double((i * 7) % 11 - 5) / 128 : 0)
            }
            let x = (0..<count).map { Double($0 + offset) }
            let result = OriginalIndexFit.line(y, offset: offset)
            records.append(["id": "index/\(count)/\(offset)/\(profile)", "kind": "index", "count": count, "offset": offset, "profile": profile, "x": vector(x), "y": vector(y), "slope": scalar(result.slope), "intercept": scalar(result.intercept)])
        }
    }
}
for count in [3, 8, 17, 64, 480, 4800] {
    for first in [0, 480, 48000, 480000] {
        for rate in [8000, 48000] {
            for profile in (count > 64 ? ["decay-window"] : ["line", "perturbed"]) {
                // Deliberately a public-input small allocation rather than faking
                // the original absolute-index/coordinate conversion.
                var curve = [Double](repeating: 0, count: first + count)
                for i in 0..<count { curve[first + i] = profile == "decay-window" ? -5 - 30 * Double(i) / Double(count - 1) : -10 - Double(i) / 16 + (profile == "perturbed" ? Double((i * 7) % 11 - 5) / 128 : 0) }
                let x = (first..<(first + count)).map { Double($0) / Double(rate) }
                let y = Array(curve[first..<(first + count)])
                let slope = OriginalTimeFit.slope(curve, first: first, last: first + count - 1, sampleRate: rate)
                records.append(["id": "time/\(count)/\(first)/\(rate)/\(profile)", "kind": "time", "count": count, "first": first, "rate": rate, "profile": profile, "x": vector(x), "y": vector(y), "slope": scalar(slope)])
            }
        }
    }
}
try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]).write(to: output)
print("PASS \(records.count) complete original fitting arithmetic audit cases")
