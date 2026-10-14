import ContactSearch
import Testing

/// Seeded points away from cell faces (by `faceMargin` of a cell) and with no pair within
/// `reachMargin` of the reach, so that the Float and Double distance tests agree.
struct Cloud {
  var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> Double {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double(state >> 11) / Double(1 << 53)
  }
  mutating func points(
    _ count: Int, low: SIMD3<Double>, high: SIMD3<Double>, layout: ContactCellLayout, reach: Float
  ) -> [SIMD3<Float>] {
    var points: [SIMD3<Float>] = []
    while points.count < count {
      let p = SIMD3<Float>(
        Float(low.x + (high.x - low.x) * next()), Float(low.y + (high.y - low.y) * next()),
        Float(low.z + (high.z - low.z) * next()))
      if clear(p, of: points, layout: layout, reach: reach) { points.append(p) }
    }
    return points
  }
}

func clear(_ p: SIMD3<Float>, of points: [SIMD3<Float>], layout: ContactCellLayout, reach: Float) -> Bool {
  for axis in 0..<3 {
    let scaled = (Double(p[axis]) - Double(layout.origin[axis])) / Double(layout.cellSize)
    if abs(scaled - scaled.rounded()) < 1e-4 { return false }
  }
  return points.allSatisfy { abs(distance($0, p) - Double(reach)) > 1e-4 * Double(reach) }
}

func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Double {
  let d = SIMD3<Double>(a) - SIMD3<Double>(b)
  return (d * d).sum().squareRoot()
}

/// The candidates of every point, worked out without the table: the points each entry keeps are
/// the lowest-numbered active points whose cells map to it; a listed point's candidates are the
/// other listed points within reach, ordered by the offset of their cell (z, then y, then x) and
/// then by index.
func bruteForce(
  layout: ContactCellLayout, points: [SIMD3<Float>], flags: [ContactPointFlags], reach: Float
) -> [[UInt32]] {
  var byEntry: [Int: [Int]] = [:]
  for (i, p) in points.enumerated() where flags[i].contains(.active) {
    byEntry[layout.entry(of: layout.cell(of: p)), default: []].append(i)
  }
  var listed = Set<Int>()
  for members in byEntry.values { listed.formUnion(members.sorted().prefix(ContactCellLayout.slotCount)) }
  return points.indices.map { i in
    guard listed.contains(i) else { return [] }
    let cell = layout.cell(of: points[i])
    let near = listed.filter { $0 != i && distance(points[$0], points[i]) < Double(reach) }
    return near.sorted { a, b in
      let da = layout.cell(of: points[a]) &- cell
      let db = layout.cell(of: points[b]) &- cell
      let ka = (da.z, da.y, da.x, a)
      let kb = (db.z, db.y, db.x, b)
      return ka < kb
    }.map(UInt32.init)
  }
}

@Suite("Contact search: layout and CPU reference")
struct ContactSearchTests {
  let layout = try! ContactCellLayout(origin: SIMD3(-0.03, 0.01, 0.02), cellSize: 0.1, period: SIMD3(8, 4, 16))

  @Test("Cells and entries follow the stated formulas, negative cells wrapping")
  func cellsAndEntries() throws {
    #expect(layout.cell(of: SIMD3(-0.03, 0.01, 0.02)) == SIMD3(0, 0, 0))
    #expect(layout.cell(of: SIMD3(-0.031, 0.009, 0.019)) == SIMD3(-1, -1, -1))
    #expect(layout.cell(of: SIMD3(0.275, 0.62, -0.5)) == SIMD3(3, 6, -6))
    // (-1, -1, -1) wraps to (7, 3, 15); (3, 6, -6) to (3, 2, 10).
    #expect(layout.entry(of: SIMD3(-1, -1, -1)) == 7 + 8 * (3 + 4 * 15))
    #expect(layout.entry(of: SIMD3(3, 6, -6)) == 3 + 8 * (2 + 4 * 10))
    #expect(layout.entry(of: SIMD3(11, 2, 1)) == layout.entry(of: SIMD3(3, 2, 17)))
    #expect(layout.entryCount == 512)
  }

  @Test("Invalid layouts, points, stamps and reaches are rejected")
  func invalidInput() throws {
    #expect(throws: ContactSearchError.invalidCellSize) {
      try ContactCellLayout(origin: .zero, cellSize: 0, period: SIMD3(1, 1, 1))
    }
    #expect(throws: ContactSearchError.invalidPeriod) {
      try ContactCellLayout(origin: .zero, cellSize: 1, period: SIMD3(6, 1, 1))
    }
    #expect(throws: ContactSearchError.invalidPeriod) {
      try ContactCellLayout(origin: .zero, cellSize: 1, period: SIMD3(0, 1, 1))
    }
    #expect(throws: ContactSearchError.tooManyEntries) {
      try ContactCellLayout(origin: .zero, cellSize: 1, period: SIMD3(1 << 10, 1 << 10, 1 << 9))
    }
    #expect(throws: ContactSearchError.invalidOrigin) {
      try ContactCellLayout(origin: SIMD3(.nan, 0, 0), cellSize: 1, period: SIMD3(1, 1, 1))
    }
    let points: [SIMD3<Float>] = [.zero, SIMD3(.infinity, 0, 0)]
    #expect(throws: ContactSearchError.nonfinitePoint(index: 1)) {
      try ContactTable.build(layout: layout, points: points, flags: [.active, .active], stamp: 1)
    }
    #expect(throws: ContactSearchError.countMismatch) {
      try ContactTable.build(layout: layout, points: points, flags: [.active], stamp: 1)
    }
    #expect(throws: ContactSearchError.invalidStamp) {
      try ContactTable.build(layout: layout, points: [.zero], flags: [.active], stamp: 0)
    }
    let table = try ContactTable.build(layout: layout, points: [.zero], flags: [.active], stamp: 3)
    #expect(throws: ContactSearchError.invalidReach) {
      try table.candidates(of: 0, points: [.zero], flags: [.active], reach: 0.11, skippingStill: false)
    }
  }

  @Test("Every pair within reach, found in search order, against a brute-force search")
  func bruteForcePairs() throws {
    var cloud = Cloud(seed: 7)
    let reach: Float = 0.1
    // A sparse region, and a dense cluster that crowds entries past their eight slots.
    var points = cloud.points(
      600, low: SIMD3(-0.4, -0.3, -0.2), high: SIMD3(0.8, 0.5, 0.6), layout: layout, reach: reach)
    points += cloud.points(
      200, low: SIMD3(0.1, 0.1, 0.1), high: SIMD3(0.25, 0.25, 0.25), layout: layout, reach: reach)
    let flags = points.indices.map { $0 % 11 == 5 ? ContactPointFlags() : .active }
    let table = try ContactTable.build(layout: layout, points: points, flags: flags, stamp: 41)
    let expected = bruteForce(layout: layout, points: points, flags: flags, reach: reach)
    var pairs = 0
    var dropped = 0
    for i in points.indices {
      let found = try table.candidates(of: i, points: points, flags: flags, reach: reach, skippingStill: false)
      #expect(found == expected[i], "point \(i)")
      pairs += found.count
      if flags[i].contains(.active) && !table.isListed(i, at: points[i]) { dropped += 1 }
    }
    #expect(pairs > 2000 && dropped > 50, "\(pairs) pairs, \(dropped) dropped")
  }

  @Test("A crowded entry keeps its eight lowest; the rest see nothing and are seen by none")
  func crowding() throws {
    let points = (0..<12).map { k in SIMD3<Float>(0.0 + 0.004 * Float(k), 0.05, 0.06) }
    let flags = [ContactPointFlags](repeating: .active, count: 12)
    let table = try ContactTable.build(layout: layout, points: points, flags: flags, stamp: 9)
    let entry = layout.entry(of: layout.cell(of: points[0]))
    #expect(Array(table.slots[(entry * 8)..<(entry * 8 + 8)]) == (0..<8).map(UInt32.init))
    for i in 0..<12 {
      let found = try table.candidates(of: i, points: points, flags: flags, reach: 0.1, skippingStill: false)
      #expect(found == (i < 8 ? (0..<8).filter { $0 != i }.map(UInt32.init) : []))
    }
  }

  @Test("Cells a period apart share an entry without seeing each other")
  func aliasing() throws {
    let small = try ContactCellLayout(origin: .zero, cellSize: 1, period: SIMD3(2, 2, 2))
    // The same entry, eight cells apart; and two neighbours within reach.
    let points: [SIMD3<Float>] = [
      SIMD3(0.5, 0.5, 0.5), SIMD3(8.5, 0.5, 0.5), SIMD3(1.2, 0.5, 0.5), SIMD3(9.2, 0.5, 0.5),
    ]
    let flags = [ContactPointFlags](repeating: .active, count: 4)
    let table = try ContactTable.build(layout: small, points: points, flags: flags, stamp: 2)
    let found = try points.indices.map {
      try table.candidates(of: $0, points: points, flags: flags, reach: 1, skippingStill: false)
    }
    #expect(found == [[2], [3], [0], [1]])
  }

  @Test("Skipping still pairs finds the same candidates when the threshold's premise holds")
  func stillSkipIsExact() throws {
    // Reference positions on a lattice two cells apart, so no two are nearer than 2h.
    let h: Float = 0.1
    let still = try ContactCellLayout.stillThreshold(minimumSeparation: 2 * h, reach: h, margin: 0.9)
    #expect(abs(still - 0.045) < 1e-7)
    var random = Cloud(seed: 23)
    var points: [SIMD3<Float>] = []
    var flags: [ContactPointFlags] = []
    for k in 0..<10 {
      for j in 0..<10 {
        for i in 0..<10 {
          let reference = SIMD3<Float>(Float(i), Float(j), Float(k)) * 2 * h + SIMD3(0.013, 0.017, 0.019)
          let moves = random.next() < 0.5
          let size = Float(random.next()) * (moves ? 1.9 * h : 0.999 * still)
          var direction = SIMD3<Float>(Float(random.next()) - 0.5, Float(random.next()) - 0.5, Float(random.next()) - 0.5)
          direction /= max((direction * direction).sum().squareRoot(), 1e-6)
          let displacement = size * direction
          points.append(reference + displacement)
          let displaced = (displacement * displacement).sum().squareRoot() >= still
          flags.append(displaced ? [.active, .moved] : .active)
        }
      }
    }
    let layout = try ContactCellLayout(origin: .zero, cellSize: h, period: SIMD3(32, 32, 32))
    let table = try ContactTable.build(layout: layout, points: points, flags: flags, stamp: 5)
    var pairs = 0
    var seenByStill = 0
    for i in points.indices {
      let all = try table.candidates(of: i, points: points, flags: flags, reach: h, skippingStill: false)
      let skipping = try table.candidates(of: i, points: points, flags: flags, reach: h, skippingStill: true)
      #expect(all == skipping, "point \(i)")
      // No two still points are within reach at all.
      if !flags[i].contains(.moved) {
        #expect(all.allSatisfy { flags[Int($0)].contains(.moved) })
        seenByStill += all.count
      }
      pairs += all.count
    }
    // Both sides counted: 51 pairs, of which a still point sees some, where the skip matters.
    #expect(pairs > 60 && seenByStill > 10, "\(pairs) pairs, \(seenByStill) seen from a still point")
  }

  @Test("Without the premise the skip misses pairs: points marked still that moved further")
  func stillSkipNeedsItsPremise() throws {
    let h: Float = 0.1
    // Two points 2h apart in reference, each moved 0.6h towards the other, both marked still.
    let points: [SIMD3<Float>] = [SIMD3(0.105, 0.05, 0.05), SIMD3(0.195, 0.05, 0.05)]
    let flags: [ContactPointFlags] = [.active, .active]
    let layout = try ContactCellLayout(origin: .zero, cellSize: h, period: SIMD3(8, 8, 8))
    let table = try ContactTable.build(layout: layout, points: points, flags: flags, stamp: 1)
    #expect(try table.candidates(of: 0, points: points, flags: flags, reach: h, skippingStill: false) == [1])
    #expect(try table.candidates(of: 0, points: points, flags: flags, reach: h, skippingStill: true) == [])
  }

  @Test("Inactive points are not in the table and find nothing")
  func inactivePoints() throws {
    let points: [SIMD3<Float>] = [SIMD3(0.01, 0.02, 0.03), SIMD3(0.02, 0.03, 0.04)]
    let table = try ContactTable.build(layout: layout, points: points, flags: [.active, []], stamp: 4)
    #expect(try table.candidates(of: 0, points: points, flags: [.active, []], reach: 0.1, skippingStill: false) == [])
    #expect(try table.candidates(of: 1, points: points, flags: [.active, []], reach: 0.1, skippingStill: false) == [])
    #expect(!table.isListed(1, at: points[1]))
  }

  @Test("The still threshold rejects separations within reach and margins outside (0, 1)")
  func thresholdValidation() throws {
    #expect(throws: ContactSearchError.invalidSeparation) {
      try ContactCellLayout.stillThreshold(minimumSeparation: 1, reach: 1, margin: 0.5)
    }
    #expect(throws: ContactSearchError.invalidMargin) {
      try ContactCellLayout.stillThreshold(minimumSeparation: 2, reach: 1, margin: 1)
    }
    #expect(throws: ContactSearchError.invalidReach) {
      try ContactCellLayout.stillThreshold(minimumSeparation: 2, reach: 0, margin: 0.5)
    }
    #expect(try ContactCellLayout.stillThreshold(minimumSeparation: 1.5, reach: 1, margin: 0.8) == 0.2)
  }
}
