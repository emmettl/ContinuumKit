import Numerics
import Testing

@Suite("Exact through-origin projection")
struct OriginLeastSquaresTests {
  @Test("Cancellation retains the exact-native nonzero projection in either order")
  func cancellation() throws {
    for y in [[0x1p53, 1, -0x1p53], [0x1p53, -0x1p53, 1]] {
      let result = try OriginLeastSquares.fit(x: [1, 1, 1], y: y)
      #expect(result.coefficient.bitPattern == (1.0 / 3).bitPattern)
      #expect(result.count == 3)
    }
  }

  @Test("Products spanning the full binary64 exponent range are retained exactly")
  func range() throws {
    for x in [Double.leastNonzeroMagnitude, 1e-200, 1e200, Double.greatestFiniteMagnitude] {
      #expect(try OriginLeastSquares.fit(x: [x, -x], y: [x, -x]).coefficient == 1)
    }
    let result = try OriginLeastSquares.fit(
      x: [Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude],
      y: [Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude])
    #expect(result.coefficient == 1)
  }

  @Test("Subnormal ties and normal carries use nearest-even rounding")
  func rounding() throws {
    let tiny = Double.leastNonzeroMagnitude
    #expect(throws: OriginLeastSquares.Failure.unrepresentableCoefficient) {
      try OriginLeastSquares.fit(x: [2], y: [tiny])
    }
    #expect(try OriginLeastSquares.fit(x: [2], y: [3 * tiny]).coefficient.bitPattern == 2)
    #expect(try OriginLeastSquares.fit(x: [2], y: [5 * tiny]).coefficient.bitPattern == 2)
    #expect(try OriginLeastSquares.fit(x: [1, 1], y: [1, 1.nextUp]).coefficient == 1)
    #expect(
      try OriginLeastSquares.fit(x: [1, 1], y: [1.nextUp, 1.nextUp.nextUp]).coefficient
        == 1.nextUp.nextUp)
  }

  @Test("Count, sign and exact zero are mathematical rather than material policy")
  func policy() throws {
    #expect(try OriginLeastSquares.fit(x: [2], y: [-6]).coefficient == -3)
    #expect(try OriginLeastSquares.fit(x: [1, 1], y: [2, -2]).coefficient == 0)
    #expect(throws: OriginLeastSquares.Failure.rankDeficient) {
      try OriginLeastSquares.fit(x: [0, -0], y: [1, 2])
    }
    #expect(throws: OriginLeastSquares.Failure.invalidDimensions) {
      try OriginLeastSquares.fit(x: [], y: [])
    }
    #expect(throws: OriginLeastSquares.Failure.nonFiniteInput) {
      try OriginLeastSquares.fit(x: [1], y: [.infinity])
    }
    #expect(throws: OriginLeastSquares.Failure.unrepresentableCoefficient) {
      try OriginLeastSquares.fit(x: [Double.leastNonzeroMagnitude], y: [1])
    }
  }

  @Test("Predictions check the returned line's output representation")
  func prediction() throws {
    let result = try OriginLeastSquares.fit(x: [1], y: [2])
    #expect(try result.value(at: 3) == 6)
    #expect(throws: OriginLeastSquares.Failure.nonFiniteQuery) { try result.value(at: .nan) }
    #expect(throws: OriginLeastSquares.Failure.unrepresentablePrediction) {
      try result.value(at: Double.greatestFiniteMagnitude)
    }
  }
}
