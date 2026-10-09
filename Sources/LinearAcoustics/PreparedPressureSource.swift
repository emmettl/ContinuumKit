// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.

public enum PressureSourceError: Error, Equatable, Sendable {
  case invalidCell(entry: Int, cell: Int)
  case duplicateCell(Int)
  case nonfiniteCoefficient(entry: Int)
  case gridMismatch
  case nonfiniteAmplitude(step: Int)
}

/// Immutable sparse increments of pressure/density, applied after each pressure update.
/// deltaPsi = amplitude * coefficient, with Float multiplication then addition.
/// Caller prepares all physical scaling and midpoint amplitudes. Signed coefficients
/// are permitted; every destination is unique and active. Empty plans are permitted.
public struct PreparedPressureSource: Sendable {
  public let cellIndices: [Int]
  public let coefficients: [Float]
  private let identity: WaveGridIdentity

  public init(grid: PreparedWaveGrid, cellIndices: [Int], coefficients: [Float]) throws {
    try PreparedWaveGrid.requireCount(coefficients.count, cellIndices.count, "sourceCoefficients")
    var seen = Set<Int>()
    for (entry, cell) in cellIndices.enumerated() {
      guard cell >= 0, cell < grid.cellCount, grid.activeCells[cell] == 1 else {
        throw PressureSourceError.invalidCell(entry: entry, cell: cell)
      }
      guard seen.insert(cell).inserted else { throw PressureSourceError.duplicateCell(cell) }
      guard coefficients[entry].isFinite else {
        throw PressureSourceError.nonfiniteCoefficient(entry: entry)
      }
    }
    self.cellIndices = cellIndices
    self.coefficients = coefficients
    identity = grid.identity
  }

  /// A copied grid is compatible; a separately prepared grid requires a new source plan.
  public func validate(for grid: PreparedWaveGrid) throws {
    guard identity === grid.identity else { throw PressureSourceError.gridMismatch }
  }
}
