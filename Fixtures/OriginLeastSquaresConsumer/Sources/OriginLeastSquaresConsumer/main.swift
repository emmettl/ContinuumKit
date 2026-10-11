import Foundation

#if !ORIGIN_SOURCE_CAPTURE
  import Numerics
#endif

struct Input: Codable {
  let id: String
  let xBits: [String]
  let yBits: [String]
  let count: Int?
  let queryBits: [String]
}
struct Prediction: Codable {
  let queryBits: String
  var valueBits: String?
  var failure: String?
}
struct Output: Codable {
  let id: String
  var coefficientBits: String?
  var count: Int?
  var failure: String?
  var predictions: [Prediction] = []
}
#if ORIGIN_SOURCE_CAPTURE
  enum OriginObservation {
    nonisolated(unsafe) static var events: [[String: Any]] = []
    static func record(_ event: [String: Any]) { events.append(event) }
  }
#endif
func decode(_ bits: [String], count: Int?) throws -> [Double] {
  let pattern = try bits.map { text in
    guard let word = UInt64(text) else { throw NSError(domain: "Invalid bits", code: 1) }
    return Double(bitPattern: word)
  }
  guard let count else { return pattern }
  guard !pattern.isEmpty, count >= 0 else { throw NSError(domain: "Invalid pattern", code: 1) }
  return (0..<count).map { pattern[$0 % pattern.count] }
}
let arguments = CommandLine.arguments
if arguments.count != 3 { fatalError("Usage: OriginLeastSquaresConsumer INPUT OUTPUT") }
let folder = URL(fileURLWithPath: arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let inputs = try JSONDecoder().decode(
  [Input].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
var outputs: [Output] = []
for (index, input) in inputs.enumerated() {
  let xs = try decode(input.xBits, count: input.count)
  let ys = try decode(input.yBits, count: input.count)
  var output = Output(id: input.id)
  #if ORIGIN_SOURCE_CAPTURE
    OriginObservation.events = []
    var raw = Data()
    for values in [xs, ys] {
      for value in values {
        var bits = value.bitPattern.littleEndian
        withUnsafeBytes(of: &bits) { raw.append(contentsOf: $0) }
      }
    }
    try raw.write(to: folder.appendingPathComponent("inputs-\(index).bin"))
  #endif
  do {
    let result = try OriginLeastSquares.fit(x: xs, y: ys)
    output.coefficientBits = String(result.coefficient.bitPattern)
    output.count = result.count
    for text in input.queryBits {
      let query = try decode([text], count: nil)[0]
      var prediction = Prediction(queryBits: text)
      do { prediction.valueBits = String(try result.value(at: query).bitPattern) } catch let failure
        as OriginLeastSquares.Failure
      { prediction.failure = failure.rawValue }
      output.predictions.append(prediction)
    }
  } catch let failure as OriginLeastSquares.Failure { output.failure = failure.rawValue }
  outputs.append(output)
  #if ORIGIN_SOURCE_CAPTURE
    let data = try JSONSerialization.data(
      withJSONObject: OriginObservation.events, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: folder.appendingPathComponent("trace-\(index).json"))
  #endif
}
try encoder.encode(outputs).write(to: folder.appendingPathComponent("results.json"))
