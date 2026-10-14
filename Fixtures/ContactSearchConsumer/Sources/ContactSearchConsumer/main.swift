import ContactSearch

// Two points in reach, one crowded entry, and the skip's premise, through the public API alone.
let layout = try ContactCellLayout(origin: .zero, cellSize: 0.1, period: SIMD3(8, 8, 8))
let points: [SIMD3<Float>] = (0..<10).map { SIMD3(0.001 + 0.005 * Float($0), 0.05, 0.05) } + [SIMD3(0.35, 0.05, 0.05)]
var flags = [ContactPointFlags](repeating: .active, count: points.count)
flags[0].insert(.moved)
let table = try ContactTable.build(layout: layout, points: points, flags: flags, stamp: 1)
let first = try table.candidates(of: 0, points: points, flags: flags, reach: 0.1, skippingStill: true)
guard first == (1..<8).map(UInt32.init) else { fatalError("crowded entry: \(first)") }
guard try table.candidates(of: 9, points: points, flags: flags, reach: 0.1, skippingStill: false).isEmpty else {
  fatalError("a dropped point found candidates")
}
guard abs(try ContactCellLayout.stillThreshold(minimumSeparation: 0.2, reach: 0.1, margin: 0.9) - 0.045) < 1e-7 else {
  fatalError("threshold")
}
print("PASS ContactSearch CPU consumer")
