// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.

/// What a point takes part in: the table at all, and whether it has moved far enough from its
/// reference position that a search skipping still pairs must still look at it.
public struct ContactPointFlags: OptionSet, Sendable, Hashable {
  public let rawValue: UInt32
  public init(rawValue: UInt32) { self.rawValue = rawValue }
  public static let active = ContactPointFlags(rawValue: 1)
  public static let moved = ContactPointFlags(rawValue: 2)
}

/// One substep's contact table, as the GPU builds it (`MetalContactSearch`) and as this CPU
/// reference does.
///
/// Every active point is dropped into its cell's entry. An entry keeps the `slotCount`
/// lowest-numbered points that fall in it, in ascending order, whatever order they arrive in.
/// Entries are tagged with `stamp`; an entry not tagged with it holds nothing this substep. An
/// entry holding a point flagged `moved` is marked moved, with the same stamp.
///
/// A point its crowded entry dropped is not listed: it sees no other point and no other sees
/// it, so every pair is seen from both sides or from neither.
public struct ContactTable: Sendable, Equatable {
  public let layout: ContactCellLayout
  public let stamp: UInt32
  /// Per entry: `stamp` if it holds a point, else `emptySlot`.
  public internal(set) var heads: [UInt32]
  /// Per entry, `slotCount` point indices in ascending order, then `emptySlot`s.
  public internal(set) var slots: [UInt32]
  /// Per entry: `stamp` if it holds a moved point, else `emptySlot`.
  public internal(set) var moved: [UInt32]

  /// A table from its parts, as a GPU snapshot gives them.
  public init(layout: ContactCellLayout, stamp: UInt32, heads: [UInt32], slots: [UInt32], moved: [UInt32]) {
    self.layout = layout
    self.stamp = stamp
    self.heads = heads
    self.slots = slots
    self.moved = moved
  }

  /// Builds the table of `points` for substep `stamp` (nonzero, below `emptySlot`).
  public static func build(
    layout: ContactCellLayout, points: [SIMD3<Float>], flags: [ContactPointFlags], stamp: UInt32
  ) throws -> ContactTable {
    guard points.count == flags.count else { throw ContactSearchError.countMismatch }
    guard points.count < Int(ContactCellLayout.emptySlot) else { throw ContactSearchError.tooManyPoints }
    guard stamp != 0, stamp != ContactCellLayout.emptySlot else { throw ContactSearchError.invalidStamp }
    let entries = layout.entryCount
    let slotCount = ContactCellLayout.slotCount
    var table = ContactTable(
      layout: layout, stamp: stamp, heads: Array(repeating: ContactCellLayout.emptySlot, count: entries),
      slots: Array(repeating: ContactCellLayout.emptySlot, count: entries * slotCount),
      moved: Array(repeating: ContactCellLayout.emptySlot, count: entries))
    var members = [[UInt32]](repeating: [], count: entries)
    for (index, point) in points.enumerated() where flags[index].contains(.active) {
      try layout.check(point, index: index)
      let entry = layout.entry(of: layout.cell(of: point))
      table.heads[entry] = stamp
      members[entry].append(UInt32(index))
      if flags[index].contains(.moved) { table.moved[entry] = stamp }
    }
    for entry in members.indices where !members[entry].isEmpty {
      for (slot, index) in members[entry].sorted().prefix(slotCount).enumerated() {
        table.slots[entry * slotCount + slot] = index
      }
    }
    return table
  }

  /// Whether `index` is among the points its own entry keeps.
  public func isListed(_ index: Int, at point: SIMD3<Float>) -> Bool {
    let entry = layout.entry(of: layout.cell(of: point))
    guard heads[entry] == stamp else { return false }
    let base = entry * ContactCellLayout.slotCount
    return slots[base..<(base + ContactCellLayout.slotCount)].contains(UInt32(index))
  }

  /// The points within `reach` (at most the cell size) of active point `index`, in the order
  /// the search finds them: the 27 cells around its own, z outermost, then each entry's points
  /// in ascending order. A point counts only when its own cell is the one being visited, as
  /// cells a period apart share an entry. Empty for a point that is inactive or not listed.
  ///
  /// With `skippingStill`, a point not flagged moved looks only in entries marked moved: see
  /// `ContactCellLayout.stillThreshold` for when that misses nothing.
  public func candidates(
    of index: Int, points: [SIMD3<Float>], flags: [ContactPointFlags], reach: Float, skippingStill: Bool
  ) throws -> [UInt32] {
    guard points.count == flags.count, points.indices.contains(index) else {
      throw ContactSearchError.countMismatch
    }
    guard reach.isFinite, reach > 0, reach <= layout.cellSize else { throw ContactSearchError.invalidReach }
    let position = points[index]
    guard flags[index].contains(.active), isListed(index, at: position) else { return [] }
    let still = skippingStill && !flags[index].contains(.moved)
    let cell = layout.cell(of: position)
    var found: [UInt32] = []
    for dz in Int32(-1)...1 {
      for dy in Int32(-1)...1 {
        for dx in Int32(-1)...1 {
          let visited = cell &+ SIMD3(dx, dy, dz)
          let entry = layout.entry(of: visited)
          guard heads[entry] == stamp, !still || moved[entry] == stamp else { continue }
          for slot in 0..<ContactCellLayout.slotCount {
            let other = slots[entry * ContactCellLayout.slotCount + slot]
            if other == ContactCellLayout.emptySlot { break }
            if Int(other) == index { continue }
            let otherPosition = points[Int(other)]
            guard layout.cell(of: otherPosition) == visited else { continue }
            let offset = position - otherPosition
            let distance = (offset * offset).sum().squareRoot()
            if distance < reach { found.append(other) }
          }
        }
      }
    }
    return found
  }
}
