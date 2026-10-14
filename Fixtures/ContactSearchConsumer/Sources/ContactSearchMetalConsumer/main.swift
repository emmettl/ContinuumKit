import ContactSearch
import ContactSearchMetal
import Metal

// A cloud searched on the device against the CPU reference, with the shared functions compiled
// into a kernel of the consumer's own.
guard let device = MTLCreateSystemDefaultDevice() else { fatalError("no Metal device") }
let layout = try ContactCellLayout(origin: SIMD3(-0.03, 0.01, 0.02), cellSize: 0.1, period: SIMD3(16, 16, 16))
struct Random {
  var state: UInt64 = 99
  mutating func next() -> Float {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Float(Double(state >> 11) / Double(1 << 53))
  }
}
var random = Random()
var points: [SIMD3<Float>] = []
while points.count < 4000 {
  let p = SIMD3(random.next(), random.next(), random.next()) * 1.2
  let scaled = (p - layout.origin) / layout.cellSize
  let faces = (scaled - scaled.rounded(.down))
  if faces.min() < 1e-3 || faces.max() > 1 - 1e-3 { continue }
  points.append(p)
}
let flags: [ContactPointFlags] = points.indices.map { $0 % 4 == 0 ? [.active, .moved] : .active }
let search = try MetalContactSearch(device: device, layout: layout, capacity: points.count)
let result = try search.search(points: points, flags: flags, reach: 0.1, skipStill: false, maxCandidates: 128)
let table = try ContactTable.build(layout: layout, points: points, flags: flags, stamp: result.table.stamp)
guard result.table == table else { fatalError("table differs from the CPU reference") }
var near = 0
for i in points.indices {
  let expected = try table.candidates(of: i, points: points, flags: flags, reach: 0.1, skippingStill: false)
  // Pairs within a rounding error of the reach may differ between the CPU and the GPU.
  let tight = expected.filter { abs(((points[i] - points[Int($0)]) * (points[i] - points[Int($0)])).sum().squareRoot() - 0.1) > 1e-5 }
  guard Set(tight).isSubset(of: Set(result.candidates[i])) else { fatalError("point \(i) misses candidates") }
  near += result.counts[i]
}
guard near > 1000, try MetalContactSearch.functionSource().contains("cksInsert") else { fatalError("too few pairs") }
print("PASS ContactSearchMetal consumer: \(points.count) points, \(near) candidates on \(device.name)")
