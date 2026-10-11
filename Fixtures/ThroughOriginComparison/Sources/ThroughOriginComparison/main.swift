import Foundation
import Numerics

struct Input: Codable {
  let id: String
  let xBits: [String]
  let yBits: [String]
}
struct Result: Codable {
  let id: String
  var stage: String
  var failure: String?
  var matrixScaleExponent: Int?
  var relativeRankToleranceBits: String?
  var permutation: [Int]?
  var reciprocalConditionBits: String?
  var rBits: [[String]]?
  var qBits: [[String]]?
  var coefficientBits: [String]?
  var scaledResidualNormBits: String?
  var rhsScaleExponent: Int?
}
func decode(_ bits: [String]) throws -> [Double] {
  try bits.map { text in
    guard let word = UInt64(text) else {
      throw NSError(domain: "Invalid binary64 input", code: 1)
    }
    return Double(bitPattern: word)
  }
}
let arguments = CommandLine.arguments
if arguments.count != 3 { fatalError("Usage: ThroughOriginComparison INPUT OUTPUT") }
let inputs = try JSONDecoder().decode(
  [Input].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
var results: [Result] = []
for input in inputs {
  let xs = try decode(input.xBits)
  let ys = try decode(input.yBits)
  var result = Result(id: input.id, stage: "factor")
  do {
    let factor = try PivotedQR(rows: xs.map { [$0] })
    result.matrixScaleExponent = factor.matrixScaleExponent
    result.relativeRankToleranceBits = String(factor.relativeRankTolerance.bitPattern)
    result.permutation = factor.permutation
    result.reciprocalConditionBits = String(factor.reciprocalConditionEstimate.bitPattern)
    result.rBits = factor.scaledUpperTriangular.map { $0.map { String($0.bitPattern) } }
    result.qBits = factor.orthogonalColumns().map { $0.map { String($0.bitPattern) } }
    result.stage = "solve"
    let solution = try factor.solve(rhs: ys)
    result.coefficientBits = solution.coefficients.map { String($0.bitPattern) }
    result.scaledResidualNormBits = String(solution.scaledResidualNorm.bitPattern)
    result.rhsScaleExponent = solution.rhsScaleExponent
    result.stage = "returned"
  } catch let failure as PivotedQR.Failure {
    result.failure = failure.rawValue
  }
  results.append(result)
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(results).write(to: URL(fileURLWithPath: arguments[2]))
