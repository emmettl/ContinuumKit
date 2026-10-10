import Numerics
import Testing

@Suite struct PivotedQRTests {
  @Test func independentNoisySystemAndRepeatedSolves() throws {
    let rows: [[Double]] = [[1, -2], [1, -1], [1, 0], [1, 1], [1, 2]]
    let qr = try PivotedQR(rows: rows)
    let a = try qr.solve(rhs: [0, 0, 1, 4, 5])
    #expect(abs(a.coefficients[0] - 2) < 2e-15)
    #expect(abs(a.coefficients[1] - 1.4) < 2e-15)
    // Exact residual sum of squares is 12/5.
    let norm =
      a.scaledResidualNorm * Double(sign: .plus, exponent: a.rhsScaleExponent, significand: 1)
    #expect(abs(norm * norm - 2.4) < 1e-14)
    let before = qr.scaledUpperTriangular
    let b = try qr.solve(rhs: [9, 7, 5, 3, 1])
    #expect(abs(b.coefficients[0] - 5) < 2e-15 && abs(b.coefficients[1] + 2) < 2e-15)
    #expect(try qr.solve(rhs: [0, 0, 1, 4, 5]) == a)
    #expect(qr.scaledUpperTriangular == before)
  }

  @Test func finiteExtremeCommonScales() throws {
    for exponent in [-1074, -1000, -600, 0, 600, 1000, 1023] {
      let scale = Double(sign: .plus, exponent: exponent, significand: 1)
      let qr = try PivotedQR(rows: [[scale, 0], [0, scale], [scale, -scale]])
      let x = try qr.solve(rhs: [scale, -scale, scale])
      #expect(abs(x.coefficients[0] - 2.0 / 3) < 1e-15)
      #expect(abs(x.coefficients[1] + 2.0 / 3) < 1e-15)
      #expect(qr.reciprocalConditionEstimate > 0)
    }
  }

  @Test func orthogonalityAndPermutationWithNineColumns() throws {
    let rows: [[Double]] = (0..<12).map { i in
      (0..<9).map { j -> Double in
        if i < 9 { return i == j ? 1 : 0 }
        return Double((i * 7 + j * 3) % 11 - 5) / 8
      }
    }
    let qr = try PivotedQR(rows: rows)
    let q = qr.orthogonalColumns()
    for i in 0..<9 {
      for j in 0..<9 {
        let dot = zip(q[i], q[j]).reduce(0.0) { $0 + $1.0 * $1.1 }
        #expect(abs(dot - Double(i == j ? 1 : 0)) < 5e-15)
      }
    }
    #expect(qr.permutation.sorted() == Array(0..<9))
  }

  @Test func rankThresholdIsExplicit() throws {
    let rows = [[1.0, 0], [0, 1e-9]]
    #expect(throws: PivotedQR.Failure.rankDeficient) {
      try PivotedQR(rows: rows, relativeRankTolerance: 1e-8)
    }
    #expect(try PivotedQR(rows: rows, relativeRankTolerance: 1e-10).columnCount == 2)
    #expect(throws: PivotedQR.Failure.rankDeficient) { try PivotedQR(rows: [[1, 1], [2, 2]]) }
    #expect(throws: PivotedQR.Failure.rankDeficient) { try PivotedQR(rows: [[0]]) }
  }

  @Test func dimensionsFiniteInputsAndAllocationLimits() throws {
    for rows in [[[Double]](), [[]], [[1, 2]], [[1], [1, 2]]] {
      #expect(throws: PivotedQR.Failure.invalidDimensions) { try PivotedQR(rows: rows) }
    }
    #expect(throws: PivotedQR.Failure.nonFiniteInput) { try PivotedQR(rows: [[.nan]]) }
    #expect(throws: PivotedQR.Failure.nonFiniteInput) { try PivotedQR(rows: [[.infinity]]) }
    for tolerance in [0, -1, Double.nan, Double.infinity, 1, Double.ulpOfOne / 2] {
      #expect(throws: PivotedQR.Failure.invalidRankTolerance) {
        try PivotedQR(rows: [[1]], relativeRankTolerance: tolerance)
      }
    }
    #expect(throws: PivotedQR.Failure.allocationLimit) {
      try PivotedQR(rows: Array(repeating: Array(repeating: 1, count: 65), count: 65))
    }
    #expect(throws: PivotedQR.Failure.allocationLimit) {
      try PivotedQR(
        rows: Array(
          repeating: Array(repeating: 1, count: 64), count: PivotedQR.maximumElements / 64 + 1))
    }
    let qr = try PivotedQR(rows: [[1], [2]])
    for rhs in [[1.0], [1, 2, 3]] {
      #expect(throws: PivotedQR.Failure.invalidDimensions) { try qr.solve(rhs: rhs) }
    }
    #expect(throws: PivotedQR.Failure.nonFiniteInput) { try qr.solve(rhs: [1, .nan]) }
  }

  @Test func representabilityFailuresAreChecked() throws {
    #expect(throws: PivotedQR.Failure.unrepresentableNormalization) {
      try PivotedQR(rows: [[.leastNonzeroMagnitude], [.greatestFiniteMagnitude]])
    }
    let qr = try PivotedQR(rows: [[1], [1]])
    #expect(throws: PivotedQR.Failure.unrepresentableNormalization) {
      try qr.solve(rhs: [.leastNonzeroMagnitude, .greatestFiniteMagnitude])
    }
    let tiny = try PivotedQR(rows: [[.leastNonzeroMagnitude]])
    #expect(throws: PivotedQR.Failure.unrepresentableSolution) { try tiny.solve(rhs: [1]) }
    let huge = try PivotedQR(rows: [[.greatestFiniteMagnitude]])
    #expect(throws: PivotedQR.Failure.unrepresentableSolution) {
      try huge.solve(rhs: [.leastNonzeroMagnitude])
    }
    #expect(try tiny.solve(rhs: [.leastNonzeroMagnitude]).coefficients == [1])
    #expect(try huge.solve(rhs: [0]).coefficients == [0])
  }
}
