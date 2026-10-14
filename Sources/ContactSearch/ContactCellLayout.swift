// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.

public enum ContactSearchError: Error, Equatable, Sendable {
  case invalidCellSize
  case invalidOrigin
  case invalidPeriod
  case tooManyEntries
  case invalidReach
  case invalidSeparation
  case invalidMargin
  case countMismatch
  case nonfinitePoint(index: Int)
  case tooManyPoints
  case invalidStamp
  case invalidCandidateLimit
}

/// Cubic cells of side `cellSize` over all of space, offset by `origin`, folded into a table
/// that wraps periodically with `period` cells along each axis (powers of two). Neighbouring
/// cells are neighbouring entries; only cells a whole period apart share an entry.
///
/// A point's cell is `floor((p - origin) / cellSize)`, evaluated in Float, so the cell of a
/// point within a rounding error of a cell face may differ between the CPU and a GPU.
public struct ContactCellLayout: Sendable, Equatable {
  /// Points each table entry keeps: the lowest-numbered that fall in it.
  public static let slotCount = 8
  /// The value of an empty slot.
  public static let emptySlot = UInt32.max

  public let origin: SIMD3<Float>
  public let cellSize: Float
  public let period: SIMD3<UInt32>

  public init(origin: SIMD3<Float>, cellSize: Float, period: SIMD3<UInt32>) throws {
    guard cellSize.isFinite, cellSize > 0 else { throw ContactSearchError.invalidCellSize }
    guard origin.x.isFinite, origin.y.isFinite, origin.z.isFinite else {
      throw ContactSearchError.invalidOrigin
    }
    for axis in 0..<3 {
      let n = period[axis]
      guard n > 0, n & (n - 1) == 0 else { throw ContactSearchError.invalidPeriod }
    }
    // Slot indices (entry · 8 + slot) must fit a 32-bit index on the GPU.
    let entries = UInt64(period.x) * UInt64(period.y) * UInt64(period.z)
    guard entries <= (1 << 28) else { throw ContactSearchError.tooManyEntries }
    self.origin = origin
    self.cellSize = cellSize
    self.period = period
  }

  public var entryCount: Int { Int(period.x) * Int(period.y) * Int(period.z) }

  /// The cell holding `point`.
  public func cell(of point: SIMD3<Float>) -> SIMD3<Int32> {
    let scaled = (point - origin) / cellSize
    return SIMD3(Int32(scaled.x.rounded(.down)), Int32(scaled.y.rounded(.down)), Int32(scaled.z.rounded(.down)))
  }

  /// Throws unless `point` is finite and its cell index fits 32 bits.
  public func check(_ point: SIMD3<Float>, index: Int) throws {
    let scaled = (point - origin) / cellSize
    for axis in 0..<3 {
      guard scaled[axis].isFinite, abs(scaled[axis]) < 2_000_000_000 else {
        throw ContactSearchError.nonfinitePoint(index: index)
      }
    }
  }

  /// The table entry of `cell`.
  public func entry(of cell: SIMD3<Int32>) -> Int {
    let wrapped = SIMD3<UInt32>(truncatingIfNeeded: cell) & (period &- 1)
    return Int(wrapped.x) + Int(period.x) * (Int(wrapped.y) + Int(period.y) * Int(wrapped.z))
  }

  /// The largest displacement from its reference position a point may have and still count as
  /// still, for points whose reference positions are at least `minimumSeparation` apart and
  /// touch within `reach`: two still points are then more than `reach` apart, so a search that
  /// skips pairs of still points (`ContactTable.candidates(of:…skippingStill:)`) misses only
  /// pairs that are out of reach. `margin` (below 1) keeps the bound clear of round-off.
  public static func stillThreshold(minimumSeparation: Float, reach: Float, margin: Float) throws -> Float {
    guard reach.isFinite, reach > 0 else { throw ContactSearchError.invalidReach }
    guard minimumSeparation.isFinite, minimumSeparation > reach else {
      throw ContactSearchError.invalidSeparation
    }
    guard margin.isFinite, margin > 0, margin < 1 else { throw ContactSearchError.invalidMargin }
    return margin * (minimumSeparation - reach) / 2
  }
}
