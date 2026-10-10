/// Deterministic unweighted affine least squares over explicit binary64 inputs.
/// Units, sample selection and interpretation belong to the caller.
public enum AffineLeastSquares {
  public enum Failure: String, Error, Equatable, Sendable {
    case invalidDimensions, nonFiniteInput, rankDeficient, unrepresentableNormalization,
      unrepresentableCoefficient
    case nonFiniteQuery, unrepresentablePrediction, constantFit, unrepresentableCoordinate
  }

  /// An origin-based line. Construction is checked and owned by `fit`.
  /// Use `value(at:)` instead of a large intercept when evaluating near the data.
  public struct Result: Equatable, Sendable {
    public let count: Int
    public let origin: Double
    public let valueAtOrigin: Double
    public let slope: Double
    /// Variance sum in the normalized coordinate system, before division by count.
    public let normalizedVariance: Double
    /// Sum of absolute centered covariance terms divided by absolute covariance.
    /// Infinity marks zero covariance with varying values; this is a conditioning
    /// diagnostic, not a confidence interval or an accuracy certificate.
    public let covarianceCancellationRatio: Double

    fileprivate init(
      count: Int, origin: Double, valueAtOrigin: Double, slope: Double, normalizedVariance: Double,
      covarianceCancellationRatio: Double
    ) {
      self.count = count
      self.origin = origin
      self.valueAtOrigin = valueAtOrigin
      self.slope = slope
      self.normalizedVariance = normalizedVariance
      self.covarianceCancellationRatio = covarianceCancellationRatio
    }

    /// Checked ordinate at coordinate zero; extrapolation can be unrepresentable.
    public func intercept() throws -> Double { try value(at: 0) }

    public func value(at coordinate: Double) throws -> Double {
      guard coordinate.isFinite else { throw Failure.nonFiniteQuery }
      let delta = coordinate - origin
      let value: Double
      if delta.isFinite {
        value = valueAtOrigin.addingProduct(slope, delta)
      } else {
        // Opposite large coordinates can overflow their difference although the
        // final value is finite. Halve before subtracting; keep a fused final sum.
        let halfDelta = coordinate / 2 - origin / 2
        value = valueAtOrigin.addingProduct(2 * slope, halfDelta)
      }
      guard value.isFinite else { throw Failure.unrepresentablePrediction }
      return value
    }

    /// Algebraic crossing of the fitted line, with no application window policy.
    public func coordinate(at value: Double) throws -> Double {
      guard value.isFinite else { throw Failure.nonFiniteQuery }
      guard slope != 0 else { throw Failure.constantFit }
      let delta = value - valueAtOrigin
      let result: Double
      if delta.isFinite {
        let shift = delta / slope
        if shift.isFinite {
          result = origin + shift
        } else {
          result = (origin / 2 + (delta / 2) / slope) * 2
        }
      } else {
        result = (origin / 2 + (value / 2 - valueAtOrigin / 2) / slope) * 2
      }
      guard result.isFinite else { throw Failure.unrepresentableCoordinate }
      return result
    }
  }

  public static func fit(x: [Double], y: [Double]) throws -> Result {
    guard x.count == y.count, x.count >= 2 else { throw Failure.invalidDimensions }
    guard x.allSatisfy(\.isFinite), y.allSatisfy(\.isFinite) else {
      throw Failure.nonFiniteInput
    }
    let xs = try normalized(x)
    guard xs.scale > 0 else { throw Failure.rankDeficient }
    let ys = try normalized(y)
    var sumX = Sum()
    var sumY = Sum()
    for (a, b) in zip(xs.values, ys.values) {
      sumX.add(a)
      sumY.add(b)
    }
    let meanX = sumX.value / Double(x.count)
    let meanY = sumY.value / Double(x.count)
    var variance = Sum()
    var covariance = Sum()
    var absoluteCovariance = Sum()
    for (a, b) in zip(xs.values, ys.values) {
      let dx = a - meanX
      let dy = b - meanY
      variance.add(dx * dx)
      covariance.add(dx * dy)
      absoluteCovariance.add(abs(dx * dy))
    }
    guard variance.value.isFinite, variance.value > 0 else { throw Failure.rankDeficient }
    let normalizedSlope = covariance.value / variance.value
    let slope = product(normalizedSlope, ys.scale, dividedBy: xs.scale)
    let ordinate = ys.origin.addingProduct(
      ys.scale, meanY.addingProduct(-normalizedSlope, meanX))
    guard slope.isFinite, ordinate.isFinite,
      normalizedSlope == 0 || slope != 0
    else { throw Failure.unrepresentableCoefficient }
    let cancellation =
      absoluteCovariance.value == 0
      ? 1
      : covariance.value == 0 ? Double.infinity : absoluteCovariance.value / abs(covariance.value)
    return Result(
      count: x.count, origin: xs.origin, valueAtOrigin: ordinate, slope: slope,
      normalizedVariance: variance.value, covarianceCancellationRatio: cancellation)
  }

  /// Shift first to preserve narrow translated windows (Sterbenz subtraction).
  /// If opposite finite extremes overflow, normalize globally about zero instead.
  private static func normalized(_ values: [Double]) throws -> (
    origin: Double, scale: Double, values: [Double]
  ) {
    let origin = values[0]
    let delta = values.map { $0 - origin }
    if delta.allSatisfy(\.isFinite) {
      let scale = delta.reduce(0) { max($0, abs($1)) }
      let scaled = scale == 0 ? delta : delta.map { $0 / scale }
      guard zip(delta, scaled).allSatisfy({ $0.0 == 0 || $0.1 != 0 }) else {
        throw Failure.unrepresentableNormalization
      }
      return (origin, scale, scaled)
    }
    let scale = values.reduce(0) { max($0, abs($1)) }
    let scaled = values.map { $0 / scale }
    guard zip(values, scaled).allSatisfy({ $0.0 == 0 || $0.1 != 0 }) else {
      throw Failure.unrepresentableNormalization
    }
    return (0, scale, scaled)
  }

  /// Multiply/divide with exponent decomposition: the scale ratio alone may
  /// overflow/underflow while the complete slope is representable.
  private static func product(_ a: Double, _ b: Double, dividedBy c: Double) -> Double {
    if a == 0 { return a }
    let exponent = a.exponent + b.exponent - c.exponent
    let significand = a.significand * b.significand / c.significand
    return Double(sign: a.sign, exponent: exponent, significand: abs(significand))
  }

  private struct Sum {
    private var total = 0.0
    private var correction = 0.0
    mutating func add(_ value: Double) {
      let next = total + value
      correction += abs(total) >= abs(value) ? (total - next) + value : (value - next) + total
      total = next
    }
    var value: Double { total + correction }
  }
}
