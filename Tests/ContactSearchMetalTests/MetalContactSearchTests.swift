import ContactSearch
import ContactSearchMetal
import Metal
import Testing

/// Seeded points away from cell faces and with no pair near the reach (see ContactSearchTests).
private struct Cloud {
  var state: UInt64
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
      var clear = true
      for axis in 0..<3 {
        let scaled = (Double(p[axis]) - Double(layout.origin[axis])) / Double(layout.cellSize)
        if abs(scaled - scaled.rounded()) < 1e-4 { clear = false }
      }
      for q in points where clear {
        let d = SIMD3<Double>(p) - SIMD3<Double>(q)
        if abs((d * d).sum().squareRoot() - Double(reach)) < 1e-4 * Double(reach) { clear = false }
      }
      if clear { points.append(p) }
    }
    return points
  }
}

@Suite("Contact search on the GPU", .serialized)
struct MetalContactSearchTests {
  let layout = try! ContactCellLayout(origin: SIMD3(-0.03, 0.01, 0.02), cellSize: 0.1, period: SIMD3(8, 8, 8))

  private func cloud(seed: UInt64) -> (points: [SIMD3<Float>], flags: [ContactPointFlags]) {
    var cloud = Cloud(state: seed)
    var points = cloud.points(
      500, low: SIMD3(-0.4, -0.3, -0.2), high: SIMD3(0.8, 0.5, 0.6), layout: layout, reach: 0.1)
    points += cloud.points(
      150, low: SIMD3(0.1, 0.1, 0.1), high: SIMD3(0.24, 0.24, 0.24), layout: layout, reach: 0.1)
    let flags: [ContactPointFlags] = points.indices.map {
      $0 % 13 == 4 ? [] : ($0 % 3 == 0 ? [.active, .moved] : .active)
    }
    return (points, flags)
  }

  @Test("The table and each point's candidates are the CPU reference's, bit for bit")
  func matchesReference() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "a Metal device is required")
    let search = try MetalContactSearch(device: device, layout: layout, capacity: 1000)
    let (points, flags) = cloud(seed: 3)
    for skip in [false, true] {
      let result = try search.search(points: points, flags: flags, reach: 0.1, skipStill: skip, maxCandidates: 64)
      let table = try ContactTable.build(layout: layout, points: points, flags: flags, stamp: result.table.stamp)
      #expect(result.table == table)
      var pairs = 0
      for i in points.indices {
        let expected = try table.candidates(of: i, points: points, flags: flags, reach: 0.1, skippingStill: skip)
        #expect(result.candidates[i] == expected && result.counts[i] == expected.count, "point \(i)")
        pairs += expected.count
      }
      #expect(pairs > 1000)
    }
  }

  @Test("Repeated builds, other thread groupings and a new instance give the same bits")
  func deterministic() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "a Metal device is required")
    let (points, flags) = cloud(seed: 11)
    let first = try MetalContactSearch(device: device, layout: layout, capacity: 1000)
      .search(points: points, flags: flags, reach: 0.1, skipStill: false, maxCandidates: 64)
    let search = try MetalContactSearch(device: device, layout: layout, capacity: 1000)
    for width in [1, 7, 32, 64, 256, 64] {
      let again = try search.search(
        points: points, flags: flags, reach: 0.1, skipStill: false, maxCandidates: 64, threadgroupWidth: width)
      #expect(again.candidates == first.candidates && again.counts == first.counts)
      #expect(again.table.slots == first.table.slots && again.table.heads.map { $0 != UInt32.max }
        == first.table.heads.map { $0 != UInt32.max })
    }
  }

  @Test("Entries left from an earlier build hold nothing in the next")
  func staleEntries() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "a Metal device is required")
    let search = try MetalContactSearch(device: device, layout: layout, capacity: 1000)
    let (points, flags) = cloud(seed: 5)
    _ = try search.search(points: points, flags: flags, reach: 0.1, skipStill: false, maxCandidates: 64)
    let fewer = Array(points.prefix(40))
    let fewerFlags = [ContactPointFlags](repeating: .active, count: 40)
    let result = try search.search(points: fewer, flags: fewerFlags, reach: 0.1, skipStill: true, maxCandidates: 64)
    let table = try ContactTable.build(layout: layout, points: fewer, flags: fewerFlags, stamp: result.table.stamp)
    #expect(result.table == table)
    // Nothing moved, so a search skipping still pairs finds none.
    #expect(result.candidates.allSatisfy { $0.isEmpty })
  }

  @Test("On the device too, skipping still pairs misses nothing when the premise holds")
  func stillSkip() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "a Metal device is required")
    let h: Float = 0.1
    let still = try ContactCellLayout.stillThreshold(minimumSeparation: 2 * h, reach: h, margin: 0.9)
    var random = Cloud(state: 29)
    var points: [SIMD3<Float>] = []
    var flags: [ContactPointFlags] = []
    for k in 0..<8 {
      for j in 0..<8 {
        for i in 0..<8 {
          let reference = SIMD3<Float>(Float(i), Float(j), Float(k)) * 2 * h + SIMD3(0.013, 0.017, 0.019)
          let moves = random.next() < 0.5
          let size = Float(random.next()) * (moves ? 1.9 * h : 0.999 * still)
          var direction = SIMD3<Float>(Float(random.next()) - 0.5, Float(random.next()) - 0.5, Float(random.next()) - 0.5)
          direction /= max((direction * direction).sum().squareRoot(), 1e-6)
          points.append(reference + size * direction)
          flags.append(size >= still ? [.active, .moved] : .active)
        }
      }
    }
    let layout = try ContactCellLayout(origin: .zero, cellSize: h, period: SIMD3(16, 16, 16))
    let search = try MetalContactSearch(device: device, layout: layout, capacity: points.count)
    let all = try search.search(points: points, flags: flags, reach: h, skipStill: false, maxCandidates: 32)
    let skipping = try search.search(points: points, flags: flags, reach: h, skipStill: true, maxCandidates: 32)
    #expect(all.candidates == skipping.candidates && all.counts == skipping.counts)
    let stillSide = all.counts.indices.filter { !flags[$0].contains(.moved) }.map { all.counts[$0] }.reduce(0, +)
    #expect(all.counts.reduce(0, +) > 30 && stillSide > 5, "\(all.counts.reduce(0, +)) pairs, \(stillSide) still")
    // Marked still after moving 0.6h towards each other, a pair is missed: the premise matters.
    let pair: [SIMD3<Float>] = [SIMD3(0.105, 0.05, 0.05), SIMD3(0.195, 0.05, 0.05)]
    let lying = try search.search(points: pair, flags: [.active, .active], reach: h, skipStill: true, maxCandidates: 4)
    let honest = try search.search(points: pair, flags: [.active, .active], reach: h, skipStill: false, maxCandidates: 4)
    #expect(lying.candidates == [[], []] && honest.candidates == [[1], [0]])
  }

  @Test("An application kernel compiled with the shared functions computes the same entries")
  func sharedFunctions() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "a Metal device is required")
    let source = try MetalContactSearch.functionSource() + """

      kernel void appEntries(const device float4 *points [[buffer(0)]], device uint *entries [[buffer(1)]],
                             uint i [[thread_position_in_grid]]) {
          entries[i] = cksEntry(cksCell(points[i].xyz, float3(-0.03, 0.01, 0.02), 0.1), uint3(8, 8, 8));
      }
      """
    let library = try device.makeLibrary(source: source, options: nil)
    let pipeline = try device.makeComputePipelineState(function: try #require(library.makeFunction(name: "appEntries")))
    var cloud = Cloud(state: 17)
    let points = cloud.points(
      2000, low: SIMD3(-3, -2, -1), high: SIMD3(2, 3, 4), layout: layout, reach: 0.1)
    let input = try #require(device.makeBuffer(length: points.count * 16, options: .storageModeShared))
    let output = try #require(device.makeBuffer(length: points.count * 4, options: .storageModeShared))
    let p = input.contents().bindMemory(to: SIMD4<Float>.self, capacity: points.count)
    for (i, point) in points.enumerated() { p[i] = SIMD4(point, 0) }
    let queue = try #require(device.makeCommandQueue())
    let commands = try #require(queue.makeCommandBuffer())
    let encoder = try #require(commands.makeComputeCommandEncoder())
    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(input, offset: 0, index: 0)
    encoder.setBuffer(output, offset: 0, index: 1)
    encoder.dispatchThreads(
      MTLSize(width: points.count, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1))
    encoder.endEncoding()
    commands.commit()
    commands.waitUntilCompleted()
    let entries = output.contents().bindMemory(to: UInt32.self, capacity: points.count)
    for (i, point) in points.enumerated() {
      #expect(Int(entries[i]) == layout.entry(of: layout.cell(of: point)), "point \(i)")
    }
  }

  @Test("Too many points, an invalid reach and too few candidate slots are reported")
  func invalidInput() throws {
    let device = try #require(MTLCreateSystemDefaultDevice(), "a Metal device is required")
    let search = try MetalContactSearch(device: device, layout: layout, capacity: 2)
    let points: [SIMD3<Float>] = [.zero, SIMD3(0.01, 0, 0), SIMD3(0.02, 0, 0)]
    #expect(throws: MetalContactSearchError.capacityExceeded) {
      try search.search(points: points, flags: [.active, .active, .active], reach: 0.1, skipStill: false, maxCandidates: 4)
    }
    #expect(throws: ContactSearchError.invalidReach) {
      try search.search(points: [.zero], flags: [.active], reach: 0.2, skipStill: false, maxCandidates: 4)
    }
    // More candidates than slots: the count says so, and the first ones are written.
    let crowded = try MetalContactSearch(device: device, layout: layout, capacity: 8)
    let near = (0..<6).map { SIMD3<Float>(0.001 * Float($0), 0.05, 0.06) }
    let result = try crowded.search(
      points: near, flags: [ContactPointFlags](repeating: .active, count: 6), reach: 0.1, skipStill: false,
      maxCandidates: 2)
    #expect(result.counts == [5, 5, 5, 5, 5, 5] && result.candidates[0] == [1, 2] && result.candidates[5] == [0, 1])
  }
}
