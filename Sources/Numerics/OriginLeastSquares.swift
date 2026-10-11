/// Deterministic unweighted least squares through coordinate zero over binary64 inputs.
/// Products and their sums are exact dyadic integers; the coefficient is rounded once,
/// to nearest with ties to even. Units and material/sample policy belong to the caller.
public enum OriginLeastSquares {
  public enum Failure: String, Error, Equatable, Sendable {
    case invalidDimensions, allocationLimit, nonFiniteInput, rankDeficient
    case unrepresentableCoefficient, nonFiniteQuery, unrepresentablePrediction
  }

  public static let maximumSamples = 1_048_576

  public struct Result: Equatable, Sendable {
    public let count: Int
    public let coefficient: Double

    fileprivate init(count: Int, coefficient: Double) {
      self.count = count
      self.coefficient = coefficient
    }

    /// Evaluates the line represented by the returned rounded coefficient.
    /// A finite nonzero product rounding to zero is an explicit representation failure.
    public func value(at coordinate: Double) throws -> Double {
      guard coordinate.isFinite else { throw Failure.nonFiniteQuery }
      let value = coefficient * coordinate
      guard value.isFinite, coefficient == 0 || coordinate == 0 || value != 0 else {
        throw Failure.unrepresentablePrediction
      }
      return value
    }
  }

  public static func fit(x: [Double], y: [Double]) throws -> Result {
    guard x.count == y.count, !x.isEmpty else { throw Failure.invalidDimensions }
    guard x.count <= maximumSamples else { throw Failure.allocationLimit }
    guard x.allSatisfy(\.isFinite), y.allSatisfy(\.isFinite) else {
      throw Failure.nonFiniteInput
    }
    var denominator = Integer()
    var positive = Integer()
    var negative = Integer()
    for (a, b) in zip(x, y) {
      let u = parts(a)
      let v = parts(b)
      // Every finite binary64 product is an integer multiple of 2^-2148.
      denominator.addProduct(u.mantissa, u.mantissa, shifted: 2 * u.exponent + 2148)
      if u.negative == v.negative {
        positive.addProduct(u.mantissa, v.mantissa, shifted: u.exponent + v.exponent + 2148)
      } else {
        negative.addProduct(u.mantissa, v.mantissa, shifted: u.exponent + v.exponent + 2148)
      }
    }
    guard !denominator.isZero else { throw Failure.rankDeficient }
    let sign: FloatingPointSign = positive < negative ? .minus : .plus
    let numerator = sign == .minus ? negative.subtracting(positive) : positive.subtracting(negative)
    let coefficient = try quotient(numerator, denominator, sign: sign)
    return Result(count: x.count, coefficient: coefficient)
  }

  private static func parts(_ value: Double) -> (mantissa: UInt64, exponent: Int, negative: Bool) {
    let bits = value.bitPattern
    let exponent = Int((bits >> 52) & 0x7ff)
    let fraction = bits & 0x000f_ffff_ffff_ffff
    return (
      exponent == 0 ? fraction : fraction | (1 << 52),
      exponent == 0 ? -1074 : exponent - 1023 - 52,
      bits >> 63 != 0
    )
  }

  private static func quotient(
    _ numerator: Integer, _ denominator: Integer, sign: FloatingPointSign
  )
    throws -> Double
  {
    if numerator.isZero { return 0 }
    var exponent = numerator.width - denominator.width
    let below =
      exponent >= 0
      ? numerator < denominator.shifted(exponent)
      : numerator.shifted(-exponent) < denominator
    if below { exponent -= 1 }
    guard exponent <= 1023, exponent >= -1075 else {
      throw Failure.unrepresentableCoefficient
    }
    let subnormal = exponent < -1022
    let shift = subnormal ? 1074 : 52 - exponent
    let a = shift >= 0 ? numerator.shifted(shift) : numerator
    let b = shift >= 0 ? denominator : denominator.shifted(-shift)
    var (significand, remainder) = a.divided(by: b)
    let doubled = remainder.shifted(1)
    if b < doubled || (b == doubled && significand & 1 != 0) { significand += 1 }
    guard significand != 0 else { throw Failure.unrepresentableCoefficient }
    let signBits: UInt64 = sign == .minus ? 1 << 63 : 0
    if subnormal {
      // A rounded significand of 2^52 encodes the smallest normal directly.
      return Double(bitPattern: signBits | significand)
    }
    if significand == 1 << 53 {
      significand >>= 1
      exponent += 1
    }
    guard exponent <= 1023 else { throw Failure.unrepresentableCoefficient }
    let exponentBits = UInt64(exponent + 1023) << 52
    return Double(bitPattern: signBits | exponentBits | (significand - (1 << 52)))
  }

  /// Little-endian nonnegative integer. At the sample cap the accumulators need
  /// at most 4,216 bits; quotient alignment adds at most 54 bits. No input-sized
  /// multiprecision allocation or floating product/normalization is required.
  private struct Integer: Equatable, Comparable {
    var words: [UInt64] = []
    var isZero: Bool { words.isEmpty }
    var width: Int {
      words.isEmpty ? 0 : 64 * (words.count - 1) + 64 - words.last!.leadingZeroBitCount
    }

    static func < (a: Self, b: Self) -> Bool {
      if a.words.count != b.words.count { return a.words.count < b.words.count }
      for i in a.words.indices.reversed() {
        if a.words[i] != b.words[i] { return a.words[i] < b.words[i] }
      }
      return false
    }

    mutating func addWord(_ value: UInt64, at index: Int) {
      if value == 0 { return }
      if words.count <= index { words += Array(repeating: 0, count: index + 1 - words.count) }
      var position = index
      var carry = value
      while carry != 0 {
        if position == words.count { words.append(0) }
        let (sum, overflow) = words[position].addingReportingOverflow(carry)
        words[position] = sum
        carry = overflow ? 1 : 0
        position += 1
      }
    }

    mutating func addProduct(_ a: UInt64, _ b: UInt64, shifted shift: Int) {
      if a == 0 || b == 0 { return }
      let product = a.multipliedFullWidth(by: b)
      let position = shift / 64
      let offset = shift % 64
      if offset == 0 {
        addWord(product.low, at: position)
        addWord(product.high, at: position + 1)
      } else {
        addWord(product.low << offset, at: position)
        addWord((product.high << offset) | (product.low >> (64 - offset)), at: position + 1)
        addWord(product.high >> (64 - offset), at: position + 2)
      }
    }

    func shifted(_ shift: Int) -> Self {
      if isZero || shift == 0 { return self }
      var result = Self()
      let position = shift / 64
      let offset = shift % 64
      for (i, word) in words.enumerated() {
        result.addWord(word << offset, at: i + position)
        if offset != 0 { result.addWord(word >> (64 - offset), at: i + position + 1) }
      }
      return result
    }

    func subtracting(_ other: Self) -> Self {
      precondition(!(self < other))
      var result = self
      var borrow: UInt64 = 0
      for i in words.indices {
        let (a, first) = words[i].subtractingReportingOverflow(
          i < other.words.count ? other.words[i] : 0)
        let (b, second) = a.subtractingReportingOverflow(borrow)
        result.words[i] = b
        borrow = first || second ? 1 : 0
      }
      precondition(borrow == 0)
      while result.words.last == 0 { result.words.removeLast() }
      return result
    }

    func divided(by denominator: Self) -> (UInt64, Self) {
      if self < denominator { return (0, self) }
      let highest = width - denominator.width
      precondition(highest < 64)
      var remainder = self
      var quotient: UInt64 = 0
      for bit in (0...highest).reversed() {
        let term = denominator.shifted(bit)
        if !(remainder < term) {
          remainder = remainder.subtracting(term)
          quotient |= 1 << bit
        }
      }
      return (quotient, remainder)
    }
  }
}
