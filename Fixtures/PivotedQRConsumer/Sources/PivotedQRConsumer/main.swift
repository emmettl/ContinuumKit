import Foundation
import Numerics

@main struct Main {
  static func main() throws {
    let output = URL(
      fileURLWithPath: ProcessInfo.processInfo.environment["CONTINUUMKIT_QR_OUTPUT"]!)
    let original =
      try JSONSerialization.jsonObject(
        with: Data(contentsOf: output.appendingPathComponent("original-audit/original.json")))
      as! [String: Any]
    func scalar(_ v: Double) -> [String: String] {
      ["value": String(v), "bits": String(v.bitPattern, radix: 16)]
    }
    func vector(_ v: [Double]) -> [[String: String]] { v.map(scalar) }
    func matrix(_ v: [[Double]]) -> [[[String: String]]] { v.map(vector) }
    func decodeVector(_ v: Any) -> [Double] {
      (v as! [[String: String]]).map { Double($0["value"]!)! }
    }
    func decodeMatrix(_ v: Any) -> [[Double]] { (v as! [Any]).map(decodeVector) }
    func dot(_ a: [Double], _ b: [Double]) -> Double {
      zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
    }
    func solve(_ qr: PivotedQR, _ id: String, _ rhs: [Double], _ rows: [[Double]]) -> [String: Any]
    {
      var record: [String: Any] = ["id": id, "rhs": vector(rhs)]
      do {
        let result = try qr.solve(rhs: rhs)
        record["coefficients"] = vector(result.coefficients)
        record["scaledResidualNorm"] = scalar(result.scaledResidualNorm)
        record["rhsScaleExponent"] = result.rhsScaleExponent
        record["predictions"] = vector(rows.map { dot($0, result.coefficients) })
      } catch let error as PivotedQR.Failure { record["error"] = error.rawValue } catch {
        preconditionFailure("Unexpected solve failure: \(error)")
      }
      return record
    }
    var records: [[String: Any]] = []
    func run(_ id: String, _ rows: [[Double]], _ rhs: [Double], _ tolerance: Double = 1e-10) throws
    {
      var record: [String: Any] = [
        "id": id, "rows": matrix(rows), "primaryRHS": vector(rhs), "tolerance": scalar(tolerance),
      ]
      do {
        let qr = try PivotedQR(rows: rows, relativeRankTolerance: tolerance)
        record["rowCount"] = qr.rowCount
        record["columnCount"] = qr.columnCount
        record["matrixScaleExponent"] = qr.matrixScaleExponent
        record["permutation"] = qr.permutation
        record["orthogonalColumns"] = matrix(qr.orthogonalColumns())
        record["scaledUpperTriangular"] = matrix(qr.scaledUpperTriangular)
        record["reciprocalConditionEstimate"] = scalar(qr.reciprocalConditionEstimate)
        let primary = solve(qr, "primary", rhs, rows)
        let alternate = rows.map { row in
          dot(row, row.indices.map { Double(($0 % 2 == 0 ? -1 : 1) * ($0 + 1)) / 32 })
        }
        record["solves"] = [
          primary, solve(qr, "alternate", alternate, rows),
          solve(qr, "zero", [Double](repeating: 0, count: rows.count), rows),
        ]
        let repeated = solve(qr, "primary", rhs, rows)
        record["repeatPrimaryIdentical"] =
          try JSONSerialization.data(withJSONObject: primary, options: .sortedKeys)
          == JSONSerialization.data(withJSONObject: repeated, options: .sortedKeys)
      } catch let error as PivotedQR.Failure { record["factorError"] = error.rawValue } catch {
        preconditionFailure("Unexpected factor failure: \(error)")
      }
      records.append(record)
    }
    for row in original["direct"] as! [[String: Any]] {
      try run(
        "audit/" + (row["id"] as! String), decodeMatrix(row["rows"]!), decodeVector(row["rhs"]!))
    }
    for row in original["geometry"] as! [[String: Any]] {
      for key in ["quadraticFactor", "linearFactor"] {
        let factor = row[key] as! [String: Any]
        try run(
          "audit/" + (row["id"] as! String) + "/" + key,
          decodeMatrix(factor["rows"]!), decodeVector(factor["rhs"]!))
      }
    }
    for width in [1, 2, 3, 9, 16] {
      for exponent in [-1074, -1022, -1000, -600, -100, 0, 100, 600, 1000, 1023] {
        let scale = Double(sign: .plus, exponent: exponent, significand: 1)
        let rows = (0..<(width + 3)).map { i in
          (0..<width).map { j -> Double in
            let value =
              i < width ? Double(i == j ? 1 : 0) : Double(((i - width + 1) * (j + 2)) % 7 - 3) / 8
            return value * scale
          }
        }
        let coefficients = (0..<width).map { Double(($0 % 2 == 0 ? 1 : -1) * ($0 + 1)) / 32 }
        try run("scale/\(width)/\(exponent)", rows, rows.map { dot($0, coefficients) })
      }
    }
    for (toleranceIndex, tolerance) in [Double.ulpOfOne, 1e-14, 1e-10, 1e-6, 0.5].enumerated() {
      let deltas: [Double] = [
        0, pow(2.0, -50.0), pow(2.0, -40.0), pow(2.0, -34.0), pow(2.0, -33.0), pow(2.0, -20.0), 0.5,
        1, tolerance,
      ]
      for (deltaIndex, delta) in deltas.enumerated() {
        try run(
          "rank/\(toleranceIndex)/\(deltaIndex)", [[1, 0], [0, delta]], [0.25, delta / 4], tolerance
        )
      }
    }
    let h = Double.greatestFiniteMagnitude
    let tiny = Double.leastNonzeroMagnitude
    try run("extreme/greatest", [[h], [-h], [h / 2]], [h / 2, -h / 2, h / 4])
    try run("extreme/normalization-A", [[tiny], [h]], [0, 1])
    try run("extreme/normalization-b", [[1], [1]], [tiny, h])
    try run("extreme/solution-overflow", [[tiny]], [1])
    try run("extreme/solution-underflow", [[h]], [tiny])
    try run(
      "dimension/64", (0..<64).map { i in (0..<64).map { j in Double(i == j ? 1 : 0) } },
      (0..<64).map { Double($0) / 128 })
    let hadamard: [[Double]] = (0..<64).map { i in
      (0..<64).map { j in Double((i & j).nonzeroBitCount % 2 == 0 ? 1 : -1) / 8 }
    }
    let hadamardCoefficients: [Double] = (0..<64).map { j -> Double in
      let sign: Double = j % 2 == 0 ? 1 : -1
      return sign * Double(j + 1) / 128
    }
    try run("dimension/64-hadamard", hadamard, hadamard.map { dot($0, hadamardCoefficients) })
    let tallHadamard =
      hadamard + (0..<16).map { i in (0..<64).map { j in Double(i == j ? 1 : 0) / 2 } }
    let tallRHS = tallHadamard.enumerated().map { i, row in
      dot(row, hadamardCoefficients) + Double((i * 11) % 7 - 3) / 1024
    }
    try run("dimension/64-hadamard-tall-noisy", tallHadamard, tallRHS)
    try run("failure/empty", [], [])
    try run("failure/no-columns", [[]], [0])
    try run("failure/ragged", [[1], [1, 2]], [1, 2])
    try run(
      "failure/too-many-columns", Array(repeating: Array(repeating: 1, count: 65), count: 65),
      Array(repeating: 1, count: 65))
    try run("failure/nan-A", [[.nan]], [1])
    try run("failure/inf-A", [[.infinity]], [1])
    try run("failure/nan-b", [[1]], [.nan])
    try run("failure/inf-b", [[1]], [.infinity])
    for (index, tolerance) in [0.0, -1, Double.nan, Double.infinity, 1, Double.ulpOfOne / 2]
      .enumerated()
    {
      try run("failure/tolerance/\(index)", [[1]], [1], tolerance)
    }
    try JSONSerialization.data(
      withJSONObject: [
        "schemaVersion": 1, "records": records,
        "limits": [
          "columns": PivotedQR.maximumColumns, "elements": PivotedQR.maximumElements,
          "defaultTolerance": scalar(PivotedQR.defaultRelativeRankTolerance),
        ],
      ], options: [.prettyPrinted, .sortedKeys]
    )
    .write(to: output.appendingPathComponent("results.json"))
    print(
      "Retained \(records.count) complete native pivoted QR factor cases and reusable RHS outputs")
  }
}
