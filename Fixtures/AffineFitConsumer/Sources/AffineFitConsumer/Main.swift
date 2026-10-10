import Foundation
import Numerics

@main struct Main {
  static func main() throws {
    let env = ProcessInfo.processInfo.environment
    let output = URL(fileURLWithPath: env["CONTINUUMKIT_AFFINE_OUTPUT"]!)
    let originals =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: output.appendingPathComponent("original-audit.json")))
      as! [[String: Any]]
    func scalar(_ x: Double) -> [String: String] {
      ["value": String(x), "bits": String(x.bitPattern, radix: 16)]
    }
    func vector(_ x: [Double]) -> [String: Any] {
      ["values": x.map { String($0) }, "bits": x.map { String($0.bitPattern, radix: 16) }]
    }
    func decode(_ v: Any) -> [Double] {
      ((v as! [String: Any])["values"] as! [String]).map { Double($0)! }
    }
    var records: [[String: Any]] = []
    func run(_ id: String, _ x: [Double], _ y: [Double], parameters: [String: Any] = [:]) {
      var row: [String: Any] = ["id": id, "x": vector(x), "y": vector(y), "parameters": parameters]
      do {
        let fit = try AffineLeastSquares.fit(x: x, y: y)
        row["count"] = fit.count
        row["origin"] = scalar(fit.origin)
        row["valueAtOrigin"] = scalar(fit.valueAtOrigin)
        row["slope"] = scalar(fit.slope)
        row["normalizedVariance"] = scalar(fit.normalizedVariance)
        row["covarianceCancellationRatio"] = scalar(fit.covarianceCancellationRatio)
        var queries: [[String: Any]] = []
        for a in x {
          do { queries.append(["x": scalar(a), "value": scalar(try fit.value(at: a))]) } catch {
            queries.append(["x": scalar(a), "error": String(describing: error)])
          }
        }
        row["predictions"] = queries
        do { row["intercept"] = scalar(try fit.intercept()) } catch {
          row["interceptError"] = String(describing: error)
        }
        var inverse: [[String: Any]] = []
        for b in [y.first!, y[y.count / 2], y.last!] {
          do {
            inverse.append(["y": scalar(b), "coordinate": scalar(try fit.coordinate(at: b))])
          } catch { inverse.append(["y": scalar(b), "error": String(describing: error)]) }
        }
        row["crossings"] = inverse
      } catch let error as AffineLeastSquares.Failure { row["error"] = error.rawValue } catch {
        preconditionFailure("Unexpected fit error: \(error)")
      }
      records.append(row)
    }
    for r in originals { run("audit/" + (r["id"] as! String), decode(r["x"]!), decode(r["y"]!)) }
    for ex in [-1000, -600, -100, 0, 100, 600, 1000] {
      for ey in [-1000, -600, -100, 0, 100, 600, 1000] {
        let sx = Double(sign: .plus, exponent: ex, significand: 1)
        let sy = Double(sign: .plus, exponent: ey, significand: 1)
        for reversed in [false, true] {
          var x = [-2.0, -1, 0, 1, 2].map { $0 * sx }
          var y = [-2.0, 0, 2, 4, 6].map { $0 * sy }
          if reversed {
            x.reverse()
            y.reverse()
          }
          run(
            "scale/\(ex)/\(ey)/\(reversed)", x, y,
            parameters: ["ex": ex, "ey": ey, "reversed": reversed])
        }
      }
    }
    let h = Double.greatestFiniteMagnitude
    let tiny = Double.leastNonzeroMagnitude
    run("extreme/opposite", [-h, 0, h], [-h / 2, 0, h / 2])
    run("extreme/translated", [h, h / 2], [h / 2, h / 4])
    run("extreme/subnormal", [0, tiny, 2 * tiny], [0, tiny, 2 * tiny])
    run("extreme/normalization-x", [0, 1e-300, 1e300], [0, 1, 2])
    run("extreme/normalization-y", [0, 1, 2, 3, 4], [1e-300, 1e300, -2e300, 1e300, 0])
    run("extreme/repeated", [0, 0, 1, 1], [1, 1, 3, 3])
    run("extreme/zero-covariance", [0, 1e-100, 2e-100], [1e300, -1e300, 1e300])
    run("failure/empty", [], [])
    run("failure/count", [1, 2], [1])
    run("failure/nan", [1, .nan], [1, 2])
    run("failure/infinity", [1, 2], [1, .infinity])
    run("failure/rank", [2, 2], [1, 3])
    run("failure/slope-overflow", [0, tiny], [0, 1])
    run("failure/slope-underflow", [0, h], [0, tiny])
    try JSONSerialization.data(withJSONObject: records, options: [.sortedKeys]).write(
      to: output.appendingPathComponent("shared.json"))
    print("PASS \(records.count) complete public affine fit records")
  }
}
