/// Deterministic column-pivoted Householder QR for small, tall binary64 matrices.
/// Units, row multipliers, basis construction and reconstruction policy are caller-owned.
public struct PivotedQR: Sendable {
  public enum Failure: String, Error, Equatable, Sendable {
    case invalidDimensions, allocationLimit, invalidRankTolerance, nonFiniteInput
    case unrepresentableNormalization, rankDeficient, unrepresentableSolution
  }

  public static let maximumColumns = 64
  public static let maximumElements = 1_048_576
  public static let defaultRelativeRankTolerance = 1e-10

  public let rowCount: Int
  public let columnCount: Int
  /// A * 2^(-matrixScaleExponent) * P = Q * scaledUpperTriangular.
  public let matrixScaleExponent: Int
  public let relativeRankTolerance: Double
  /// Original column index at each pivoted column position.
  public let permutation: [Int]
  /// Reciprocal 1-norm condition estimate of the scaled triangular factor.
  /// A floating diagnostic, not a certified condition bound or forward-error promise.
  public let reciprocalConditionEstimate: Double
  private let factors: [Double]
  private let reflectorScalars: [Double]

  public init(
    rows: [[Double]], relativeRankTolerance: Double = defaultRelativeRankTolerance
  ) throws {
    let m = rows.count
    let n = rows.first?.count ?? 0
    guard n > 0, m >= n, rows.allSatisfy({ $0.count == n }) else {
      throw Failure.invalidDimensions
    }
    guard n <= Self.maximumColumns, m <= Self.maximumElements / n else {
      throw Failure.allocationLimit
    }
    guard relativeRankTolerance.isFinite,
      relativeRankTolerance >= Double.ulpOfOne, relativeRankTolerance < 1
    else { throw Failure.invalidRankTolerance }
    guard rows.allSatisfy({ $0.allSatisfy(\.isFinite) }) else { throw Failure.nonFiniteInput }
    let native = rows.flatMap { $0 }
    let normalized = try Self.normalized(native)
    var a = normalized.values
    var pivots = Array(0..<n)
    var tau = [Double](repeating: 0, count: n)
    var initialNorm = 0.0
    for k in 0..<n {
      var pivot = k
      var norm = 0.0
      // Recompute each remaining norm rather than using a subtractive downdate.
      for j in k..<n {
        let candidate = Self.norm((k..<m).map { a[$0 * n + j] })
        if candidate > norm {
          norm = candidate
          pivot = j
        }
      }
      if k == 0 { initialNorm = norm }
      guard norm > 0, norm / initialNorm > relativeRankTolerance else {
        throw Failure.rankDeficient
      }
      if pivot != k {
        for i in 0..<m { a.swapAt(i * n + k, i * n + pivot) }
        pivots.swapAt(k, pivot)
      }
      let alpha = a[k * n + k]
      let tail = Self.norm(((k + 1)..<m).map { a[$0 * n + k] })
      if tail != 0 {
        let beta = alpha >= 0 ? -norm : norm
        let denominator = alpha - beta
        tau[k] = 1 - alpha / beta
        for i in (k + 1)..<m { a[i * n + k] /= denominator }
        a[k * n + k] = beta
        for j in (k + 1)..<n {
          var dot = Sum()
          dot.add(a[k * n + j])
          for i in (k + 1)..<m { dot.addProduct(a[i * n + k], a[i * n + j]) }
          let projection = tau[k] * dot.value
          a[k * n + j] -= projection
          for i in (k + 1)..<m {
            a[i * n + j] = a[i * n + j].addingProduct(-projection, a[i * n + k])
          }
        }
      }
    }
    self.rowCount = m
    self.columnCount = n
    self.matrixScaleExponent = normalized.exponent
    self.relativeRankTolerance = relativeRankTolerance
    self.permutation = pivots
    self.factors = a
    self.reflectorScalars = tau
    self.reciprocalConditionEstimate = Self.reciprocalCondition(a, n: n)
  }

  /// Full scaled R, in pivoted column order. Its sign convention is not prescribed.
  public var scaledUpperTriangular: [[Double]] {
    (0..<columnCount).map { i in
      (0..<columnCount).map { j in j < i ? 0 : factors[i * columnCount + j] }
    }
  }

  /// Complete thin Q as `columnCount` columns, each with `rowCount` values.
  public func orthogonalColumns() -> [[Double]] {
    (0..<columnCount).map { j in
      var column = [Double](repeating: 0, count: rowCount)
      column[j] = 1
      for k in (0..<columnCount).reversed() { applyReflector(k, to: &column) }
      return column
    }
  }

  public struct Solution: Equatable, Sendable {
    public let coefficients: [Double]
    /// Norm of the trailing Q-transformed RHS after exact power-of-two scaling.
    /// The physical residual norm is this value times 2^rhsScaleExponent and
    /// can be unrepresentable. This is a computed diagnostic, not a certified bound.
    public let scaledResidualNorm: Double
    public let rhsScaleExponent: Int

    fileprivate init(coefficients: [Double], scaledResidualNorm: Double, rhsScaleExponent: Int) {
      self.coefficients = coefficients
      self.scaledResidualNorm = scaledResidualNorm
      self.rhsScaleExponent = rhsScaleExponent
    }
  }

  /// Reuses immutable reflectors for another complete RHS. Returns original column order.
  public func solve(rhs: [Double]) throws -> Solution {
    guard rhs.count == rowCount else { throw Failure.invalidDimensions }
    guard rhs.allSatisfy(\.isFinite) else { throw Failure.nonFiniteInput }
    let normalized = try Self.normalized(rhs)
    var transformed = normalized.values
    for k in 0..<columnCount { applyReflector(k, to: &transformed) }
    var x = [Double](repeating: 0, count: columnCount)
    for i in (0..<columnCount).reversed() {
      var dot = Sum()
      for j in (i + 1)..<columnCount { dot.addProduct(factors[i * columnCount + j], x[j]) }
      x[i] = (transformed[i] - dot.value) / factors[i * columnCount + i]
      guard x[i].isFinite else { throw Failure.unrepresentableSolution }
    }
    var coefficients = [Double](repeating: 0, count: columnCount)
    for j in 0..<columnCount {
      let value = Self.scaled(x[j], by: normalized.exponent - matrixScaleExponent)
      guard value.isFinite, x[j] == 0 || value != 0 else {
        throw Failure.unrepresentableSolution
      }
      coefficients[permutation[j]] = value
    }
    return Solution(
      coefficients: coefficients,
      scaledResidualNorm: Self.norm(Array(transformed.dropFirst(columnCount))),
      rhsScaleExponent: normalized.exponent)
  }

  private func applyReflector(_ k: Int, to vector: inout [Double]) {
    let tau = reflectorScalars[k]
    if tau == 0 { return }
    var dot = Sum()
    dot.add(vector[k])
    for i in (k + 1)..<rowCount { dot.addProduct(factors[i * columnCount + k], vector[i]) }
    let projection = tau * dot.value
    vector[k] -= projection
    for i in (k + 1)..<rowCount {
      vector[i] = vector[i].addingProduct(-projection, factors[i * columnCount + k])
    }
  }

  /// Global scaling is exact or rejects; never silently erase native nonzero inputs.
  private static func normalized(_ values: [Double]) throws -> (values: [Double], exponent: Int) {
    let largest = values.reduce(0) { max($0, abs($1)) }
    let exponent = largest == 0 ? 0 : largest.exponent
    let output = values.map { scaled($0, by: -exponent) }
    guard
      zip(values, output).allSatisfy({
        $0.1.isFinite && ($0.0 == 0 || $0.1 != 0) && scaled($0.1, by: exponent) == $0.0
      })
    else { throw Failure.unrepresentableNormalization }
    return (output, exponent)
  }

  private static func scaled(_ value: Double, by exponent: Int) -> Double {
    if value == 0 { return value }
    return Double(
      sign: value.sign, exponent: value.exponent + exponent, significand: abs(value.significand))
  }

  private static func norm(_ values: [Double]) -> Double {
    let largest = values.reduce(0) { max($0, abs($1)) }
    if largest == 0 { return 0 }
    var sum = Sum()
    for value in values {
      let ratio = value / largest
      sum.addProduct(ratio, ratio)
    }
    return largest * sum.value.squareRoot()
  }

  private static func reciprocalCondition(_ a: [Double], n: Int) -> Double {
    var norm = 0.0
    var inverseNorm = 0.0
    for j in 0..<n {
      var column = Sum()
      for i in 0...j { column.add(abs(a[i * n + j])) }
      norm = max(norm, column.value)
      var x = [Double](repeating: 0, count: n)
      for i in (0..<n).reversed() {
        var dot = Sum()
        for k in (i + 1)..<n { dot.addProduct(a[i * n + k], x[k]) }
        x[i] = ((i == j ? 1 : 0) - dot.value) / a[i * n + i]
        if !x[i].isFinite { return 0 }
      }
      var total = Sum()
      for value in x { total.add(abs(value)) }
      inverseNorm = max(inverseNorm, total.value)
    }
    let reciprocal = (1 / norm) / inverseNorm
    return reciprocal.isFinite ? min(1, max(0, reciprocal)) : 0
  }

  private struct Sum {
    private var total = 0.0
    private var correction = 0.0
    mutating func add(_ value: Double) {
      let next = total + value
      correction += abs(total) >= abs(value) ? (total - next) + value : (value - next) + total
      total = next
    }
    mutating func addProduct(_ a: Double, _ b: Double) {
      let product = a * b
      add(product)
      add((-product).addingProduct(a, b))
    }
    var value: Double { total + correction }
  }
}
