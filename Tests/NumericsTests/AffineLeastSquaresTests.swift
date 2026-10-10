import Numerics
import Testing

@Suite struct AffineLeastSquaresTests {
  @Test func translatedExactLine() throws {
    for offset in [0.0, 1e6, 1e9, Double(1 << 40)] {
      let x = (0..<8).map { offset + Double($0) }
      let y = (0..<8).map { -10 - Double($0) / 16 }
      let fit = try AffineLeastSquares.fit(x: x, y: y)
      #expect(abs(fit.slope + 0.0625) < 2e-16)
      #expect(abs(fit.valueAtOrigin + 10) < 2e-14)
      for (a, b) in zip(x, y) { #expect(abs(try fit.value(at: a) - b) < 2e-14) }
      #expect(abs(try fit.coordinate(at: y[4]) - x[4]) <= x[4].ulp)
    }
  }
  @Test func noisyIndependentRationalCase() throws {
    // Independent normal equations: covariance 14, variance 10; means x=0, y=2.
    let fit = try AffineLeastSquares.fit(x: [-2, -1, 0, 1, 2], y: [0, 0, 1, 4, 5])
    #expect(abs(fit.slope - 1.4) < 1e-15)
    #expect(abs(try fit.intercept() - 2) < 1e-15)
    #expect(abs(try fit.value(at: 1) - 3.4) < 1e-15)
  }
  @Test func constantValuesAndRepeatedCoordinates() throws {
    let constant = try AffineLeastSquares.fit(x: [1, 2, 2, 4], y: [7, 7, 7, 7])
    #expect(constant.slope == 0 && constant.valueAtOrigin == 7)
    #expect(throws: AffineLeastSquares.Failure.constantFit) { try constant.coordinate(at: 7) }
    let duplicate = try AffineLeastSquares.fit(x: [0, 0, 1, 1], y: [1, 1, 3, 3])
    #expect(duplicate.slope == 2)
  }
  @Test func reversedInputsAndNegativeSlopes() throws {
    let x: [Double] = [2, 5, 7, 9]
    let y: [Double] = [3, -3, -7, -11]
    let a = try AffineLeastSquares.fit(x: x, y: y)
    let b = try AffineLeastSquares.fit(x: Array(x.reversed()), y: Array(y.reversed()))
    #expect(a.slope == -2 && b.slope == -2)
    for t in x { #expect(try a.value(at: t) == b.value(at: t)) }
  }
  @Test func subnormalAndHugeCoordinateScales() throws {
    let tiny = Double.leastNonzeroMagnitude
    let a = try AffineLeastSquares.fit(x: [0, tiny, 2 * tiny], y: [0, tiny, 2 * tiny])
    #expect(abs(a.slope - 1) < 1e-15)
    #expect(try a.value(at: tiny) == tiny)
    let h = Double.greatestFiniteMagnitude
    let b = try AffineLeastSquares.fit(x: [-h, 0, h], y: [-h / 2, 0, h / 2])
    #expect(abs(b.slope - 0.5) < 1e-15)
    #expect(abs(try b.value(at: h) / h - 0.5) < 1e-15)
  }
  @Test func zeroCovarianceWithOverflowingScaleRatio() throws {
    let fit = try AffineLeastSquares.fit(x: [0, 1e-100, 2e-100], y: [1e300, -1e300, 1e300])
    #expect(fit.slope == 0)
    #expect(fit.covarianceCancellationRatio == .infinity)
    #expect(fit.valueAtOrigin.isFinite)
  }

  @Test func vanishedNormalizationIsNotSilentlyAccepted() {
    #expect(throws: AffineLeastSquares.Failure.unrepresentableNormalization) {
      try AffineLeastSquares.fit(x: [0, 1e-300, 1e300], y: [0, 1, 2])
    }
    #expect(throws: AffineLeastSquares.Failure.unrepresentableNormalization) {
      try AffineLeastSquares.fit(x: [0, 1, 2, 3, 4], y: [1e-300, 1e300, -2e300, 1e300, 0])
    }
  }
  @Test func dimensionsNonFiniteAndNativeRankFailures() {
    #expect(throws: AffineLeastSquares.Failure.invalidDimensions) {
      try AffineLeastSquares.fit(x: [], y: [])
    }
    #expect(throws: AffineLeastSquares.Failure.invalidDimensions) {
      try AffineLeastSquares.fit(x: [1, 2], y: [1])
    }
    #expect(throws: AffineLeastSquares.Failure.nonFiniteInput) {
      try AffineLeastSquares.fit(x: [1, .nan], y: [1, 2])
    }
    #expect(throws: AffineLeastSquares.Failure.nonFiniteInput) {
      try AffineLeastSquares.fit(x: [1, 2], y: [1, .infinity])
    }
    #expect(throws: AffineLeastSquares.Failure.rankDeficient) {
      try AffineLeastSquares.fit(x: [2, 2], y: [1, 3])
    }
    #expect(throws: AffineLeastSquares.Failure.rankDeficient) {
      try AffineLeastSquares.fit(x: [Double(1 << 53), Double((1 << 53) + 1)], y: [1, 2])
    }
  }
  @Test func coefficientAndQueryRepresentability() throws {
    #expect(throws: AffineLeastSquares.Failure.unrepresentableCoefficient) {
      try AffineLeastSquares.fit(x: [0, .leastNonzeroMagnitude], y: [0, 1])
    }
    #expect(throws: AffineLeastSquares.Failure.unrepresentableCoefficient) {
      try AffineLeastSquares.fit(x: [0, .greatestFiniteMagnitude], y: [0, .leastNonzeroMagnitude])
    }
    let fit = try AffineLeastSquares.fit(x: [0, 1], y: [0, 2])
    #expect(throws: AffineLeastSquares.Failure.nonFiniteQuery) { try fit.value(at: .infinity) }
    #expect(throws: AffineLeastSquares.Failure.unrepresentablePrediction) {
      try fit.value(at: .greatestFiniteMagnitude)
    }
    let small = try AffineLeastSquares.fit(x: [0, 1], y: [0, 0.5])
    #expect(throws: AffineLeastSquares.Failure.unrepresentableCoordinate) {
      try small.coordinate(at: .greatestFiniteMagnitude)
    }
  }
  @Test func translatedPredictionAndCrossingAvoidOverflow() throws {
    let h = Double.greatestFiniteMagnitude
    let fit = try AffineLeastSquares.fit(x: [h, h / 2], y: [h / 2, h / 4])
    #expect(abs(try fit.value(at: -h) / h + 0.5) < 1e-15)
    #expect(abs(try fit.coordinate(at: -h / 2) / h + 1) < 1e-15)
  }
}
