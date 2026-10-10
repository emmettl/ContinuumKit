import Foundation
import simd

func scalar(_ x: Double) -> [String: String] {
  ["value": String(x), "bits": String(x.bitPattern, radix: 16)]
}
func vector(_ x: [Double]) -> [[String: String]] { x.map(scalar) }
func matrix(_ x: [[Double]]) -> [[[String: String]]] { x.map(vector) }
func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
func record(_ id: String, _ rows: [[Double]], _ rhs: [Double], _ parameters: [String: Any])
  -> [String: Any]
{
  var result: [String: Any] = [
    "id": id, "rows": matrix(rows), "rhs": vector(rhs), "parameters": parameters,
  ]
  if let qr = FiniteVolumePressureFit.QR(rows: rows) {
    result["factorAccepted"] = true
    result["upper"] = matrix(qr.upper)
    result["vectors"] = matrix(qr.vectors)
    result["permutation"] = qr.permutation
    if let x = qr.solve(rhs: rhs) {
      result["solveAccepted"] = true
      result["coefficients"] = vector(x)
      result["predictions"] = vector(rows.map { dot($0, x) })
    } else {
      result["solveAccepted"] = false
    }
  } else {
    result["factorAccepted"] = false
  }
  return result
}
var records: [[String: Any]] = []
for width in [3, 9] {
  let base = (0..<(width + 3)).map { i in
    (0..<width).map { j -> Double in
      if i < width { return i == j ? 1 : 0 }
      return Double(((i - width + 1) * (j + 2)) % 7 - 3) / 8
    }
  }
  let nominal = (0..<width).map { Double(($0 % 2 == 0 ? 1 : -1) * ($0 + 1)) / 8 }
  for family in ["common", "column", "near", "rank", "short"] {
    let labels: [String]
    switch family {
    case "common": labels = [-1000, -600, -500, -100, 0, 100, 500, 600, 1000].map(String.init)
    case "column":
      labels = [-1000, -600, -100, -40, -20, 0, 20, 40, 100, 600, 1000].map(String.init)
    case "near": labels = ["zero", "-55", "-45", "-40", "-35", "-34", "-33", "-32", "-20", "-10"]
    case "rank": labels = ["duplicate", "zero"]
    default: labels = ["short"]
    }
    for label in labels {
      var rows = base
      if family == "common" {
        let scale = pow(2, Double(label)!)
        rows = rows.map { $0.map { $0 * scale } }
      }
      if family == "column" {
        let scale = pow(2, Double(label)!)
        for i in rows.indices { rows[i][width - 1] *= scale }
      }
      if family == "near" {
        let delta = label == "zero" ? 0 : pow(2, Double(label)!)
        for i in rows.indices { rows[i][width - 1] = rows[i][0] + delta * base[i][width - 1] }
      }
      if family == "rank" {
        for i in rows.indices {
          if label == "duplicate" {
            rows[i][width - 1] = rows[i][0]
          } else {
            rows[i] = [Double](repeating: 0, count: width)
          }
        }
      }
      if family == "short" { rows = Array(rows.prefix(width - 1)) }
      for reversed in [false, true] {
        for noisy in [false, true] {
          var rhs = rows.enumerated().map { i, row in
            dot(row, nominal)
              + (noisy
                ? Double((i * 11) % 7 - 3) / 256 * (family == "common" ? pow(2, Double(label)!) : 1)
                : 0)
          }
          let ordered = reversed ? Array(rows.reversed()) : rows
          if reversed { rhs.reverse() }
          records.append(
            record(
              "direct/\(width)/\(family)/\(label)/\(reversed)/\(noisy)", ordered, rhs,
              [
                "width": width, "family": family, "label": label, "reversed": reversed,
                "noisy": noisy,
              ]))
        }
      }
    }
  }
  for kind in ["short-rhs", "long-rhs", "nan-rhs", "inf-rhs"] {
    var rhs = base.map { dot($0, nominal) }
    if kind == "short-rhs" { rhs.removeLast() }
    if kind == "long-rhs" { rhs.append(99) }
    if kind == "nan-rhs" { rhs[0] = .nan }
    if kind == "inf-rhs" { rhs[0] = .infinity }
    records.append(
      record("dimensions/\(width)/\(kind)", base, rhs, ["width": width, "kind": kind]))
  }
}
func polynomial(_ p: SIMD3<Double>, _ covariance: simd_double3x3, _ affine: Bool) -> Double {
  if affine { return 2 + 3 * p.x - 0.7 * p.y + 1.1 * p.z }
  return 1.2 + 2 * p.x - 3 * p.y + 0.7 * p.z + 0.9 * (p.x * p.x + covariance[0][0]) - 0.4
    * (p.y * p.y + covariance[1][1]) + 0.3 * (p.z * p.z + covariance[2][2]) + 1.1
    * (p.x * p.y + covariance[0][1]) - 0.6 * (p.x * p.z + covariance[0][2]) + 0.4
    * (p.y * p.z + covariance[1][2])
}
func sample(_ point: SIMD3<Double>, _ index: Int, _ affine: Bool) -> FiniteVolumePressureFit.Sample
{
  let diagonal = SIMD3<Double>(
    0.0064 + 0.0001 * Double(index), 0.0169, 0.0036 + 0.00002 * Double(index))
  let covariance = simd_double3x3(diagonal: diagonal)
  return .init(
    centre: point, covariance: covariance, average: polynomial(point, covariance, affine))
}
func sampleRecord(_ s: FiniteVolumePressureFit.Sample) -> [String: Any] {
  [
    "centre": vector([s.centre.x, s.centre.y, s.centre.z]),
    "covariance": matrix((0..<3).map { c in (0..<3).map { r in s.covariance[c][r] } }),
    "average": scalar(s.average),
  ]
}
var geometries: [[String: Any]] = []
func geometry(
  _ id: String, _ cell: FiniteVolumePressureFit.Sample,
  _ neighbours: [FiniteVolumePressureFit.Sample], _ scale: Double, _ quadratic: Bool, _ aware: Bool,
  _ parameters: [String: Any]
) {
  let fit = FiniteVolumePressureFit.fit(
    cell: cell, neighbours: neighbours, scale: scale, quadratic: quadratic, volumeAware: aware)
  let rows = QRAuditHook.rows
  let rhs = QRAuditHook.rhs
  var record: [String: Any] = [
    "id": id, "parameters": parameters, "cell": sampleRecord(cell),
    "neighbours": neighbours.map(sampleRecord), "scale": scalar(scale), "quadratic": quadratic,
    "volumeAware": aware, "weights": vector(QRAuditHook.weights), "rows": matrix(rows),
    "rhs": vector(rhs), "degree": fit.degree, "coefficients": vector(fit.coefficients),
  ]
  record["quadraticFactor"] = selfRecord(rows, rhs)
  record["linearFactor"] = selfRecord(rows.map { Array($0.prefix(3)) }, rhs)
  let points = [
    cell.centre, cell.centre + SIMD3<Double>(0.13, -0.27, 0.08),
    cell.centre + SIMD3<Double>(-0.3, 0.4, -0.2),
  ]
  record["queries"] = points.map {
    ["point": vector([$0.x, $0.y, $0.z]), "value": scalar(fit.value(at: $0))]
  }
  geometries.append(record)
}
func selfRecord(_ rows: [[Double]], _ rhs: [Double]) -> [String: Any] {
  record("geometry-factor", rows, rhs, [:])
}
for origin in [0, 1] {
  let translation = origin == 0 ? SIMD3<Double>.zero : SIMD3<Double>(17, -8, 31)
  for affine in [false, true] {
    var samples: [FiniteVolumePressureFit.Sample] = []
    for z in [-1.1, 0, 0.9] {
      for y in [-0.7, 0, 1.3] {
        for x in [-1.3, 0, 0.8] {
          samples.append(sample(translation + SIMD3(x, y, z), samples.count, affine))
        }
      }
    }
    let cell = samples[13]
    let neighbours = samples.enumerated().filter { $0.offset != 13 }.map(\.element)
    for scale in [0.1, 0.4, 2, 1e-100, 1e100] {
      for reversed in [false, true] {
        for quadratic in [false, true] {
          for aware in [false, true] {
            geometry(
              "geometry/\(origin)/\(affine)/\(scale)/\(reversed)/\(quadratic)/\(aware)", cell,
              reversed ? Array(neighbours.reversed()) : neighbours, scale, quadratic, aware,
              [
                "origin": origin, "affine": affine, "scale": String(scale), "reversed": reversed,
                "quadratic": quadratic, "aware": aware,
              ])
          }
        }
      }
    }
  }
}
let axes = [
  SIMD3<Double>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(-1, 0, 0), SIMD3(0, -1, 0),
  SIMD3(0, 0, -1),
]
for family in ["axes", "planar", "single", "empty"] {
  for quadratic in [false, true] {
    for aware in [false, true] {
      let points =
        family == "axes"
        ? axes
        : family == "planar"
          ? axes.filter { $0.z == 0 } : family == "single" ? Array(axes.prefix(1)) : []
      geometry(
        "fallback/\(family)/\(quadratic)/\(aware)", sample(.zero, 0, true),
        points.enumerated().map { sample($0.element, $0.offset + 1, true) }, 1, quadratic, aware,
        ["family": family, "quadratic": quadratic, "aware": aware])
    }
  }
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try JSONSerialization.data(
  withJSONObject: ["schemaVersion": 1, "direct": records, "geometry": geometries],
  options: [.prettyPrinted, .sortedKeys]
).write(to: output)
print(
  "Retained \(records.count) complete native direct QR cases and \(geometries.count) actual weighted stencil cases"
)
