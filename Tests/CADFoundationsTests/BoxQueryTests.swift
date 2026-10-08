import SceneModel
import Testing
import simd

@Suite("Closed box spatial queries")
struct BoxQueryTests {
  let box = Box(min: SIMD3(1, 2, 3), max: SIMD3(5, 8, 10))

  @Test("Axis rays return analytically known entries and exits in both directions")
  func axes() {
    for axis in 0..<3 {
      let centre = (box.min + box.max) / 2
      var origin = centre
      origin[axis] = box.min[axis] - 2
      var direction = SIMD3<Float>.zero
      direction[axis] = 2
      let length = box.max[axis] - box.min[axis]
      #expect(box.intersection(origin: origin, direction: direction) == 1...(1 + length / 2))
      origin[axis] = box.max[axis] + 2
      direction[axis] = -2
      #expect(box.intersection(origin: origin, direction: direction) == 1...(1 + length / 2))
    }
  }

  @Test("Segment fractions, clipping, interior starts and intersections behind the ray")
  func clipping() {
    #expect(
      box.intersection(origin: [0, 4, 5], direction: [10, 0, 0], parameters: 0...1) == 0.1...0.5)
    #expect(
      box.intersection(origin: [0, 4, 5], direction: [10, 0, 0], parameters: 0.2...0.3) == 0.2...0.3
    )
    #expect(
      box.intersection(origin: [0, 4, 5], direction: [10, 0, 0], parameters: 0...0.09) == nil)
    #expect(box.intersection(origin: [3, 4, 5], direction: [1, 0, 0]) == 0...2)
    #expect(box.intersection(origin: [6, 4, 5], direction: [1, 0, 0]) == nil)
    #expect(
      box.intersection(origin: [6, 4, 5], direction: [1, 0, 0], parameters: -10...10) == -5 ... -1)
  }

  @Test("Closed faces and a single corner touch count, parallel outside rays miss")
  func boundaries() {
    #expect(box.intersection(origin: [0, 8, 10], direction: [1, 0, 0]) == 1...5)
    #expect(box.intersection(origin: [0, 9, 10], direction: [1, 0, 0]) == nil)
    let unit = Box(min: .zero, max: [1, 1, 1])
    #expect(unit.intersection(origin: [-1, 1, 0.5], direction: [1, -1, 0]) == 1...1)
    #expect(unit.intersection(origin: [1, 0.5, 0.5], direction: [1, 0, 0]) == 0...0)
  }

  @Test("Tolerance classifies direction components without inflating bounds")
  func tolerance() {
    let thin = Box(min: [1, 0, 0], max: [2, 1, 1])
    #expect(thin.intersection(origin: [0, -1e-6, 0.5], direction: [1, 1e-6, 0]) != nil)
    #expect(
      thin.intersection(origin: [0, -1e-6, 0.5], direction: [1, 1e-6, 0], parallelTolerance: 1e-6)
        == nil)
    #expect(
      thin.intersection(origin: [0, -1e-6, 0.5], direction: [1, 0, 0], parallelTolerance: 1e-3)
        == nil)
  }

  @Test("Invalid and unrepresentable queries fail without creating nonfinite entries")
  func invalid() {
    #expect(box.intersection(origin: [0, 4, 5], direction: .zero) == nil)
    #expect(box.intersection(origin: [.nan, 4, 5], direction: [1, 0, 0]) == nil)
    #expect(box.intersection(origin: [0, 4, 5], direction: [.infinity, 0, 0]) == nil)
    #expect(
      box.intersection(origin: [0, 4, 5], direction: [1, 0, 0], parallelTolerance: -1) == nil)
    #expect(
      box.intersection(origin: [0, 4, 5], direction: [1, 0, 0], parallelTolerance: .nan) == nil)
    #expect(
      box.intersection(origin: [0, 4, 5], direction: [1, 0, 0], parameters: -.infinity...1) == nil)
    #expect(box.intersection(origin: [0, 4, 5], direction: [.leastNonzeroMagnitude, 0, 0]) == nil)
    for bad in [
      Box(min: [1, 2, 3], max: [1, 8, 10]), Box(min: [5, 2, 3], max: [1, 8, 10]),
      Box(min: [1, 2, 3], max: [.infinity, 8, 10]),
    ] {
      #expect(bad.intersection(origin: [0, 4, 5], direction: [1, 0, 0]) == nil)
    }
  }

  @Test("Translation and direction scaling preserve the geometric intersection")
  func transforms() throws {
    let origin = SIMD3<Float>(-3, 0, 1)
    let direction = SIMD3<Float>(2, 2, 2)
    let hit = try #require(box.intersection(origin: origin, direction: direction))
    #expect(hit == 2...4)
    let offset = SIMD3<Float>(128, -32, 16)
    let shifted = Box(min: box.min + offset, max: box.max + offset)
    #expect(shifted.intersection(origin: origin + offset, direction: direction) == hit)
    let scaled = (hit.lowerBound / 4)...(hit.upperBound / 4)
    #expect(box.intersection(origin: origin, direction: direction * 4) == scaled)
  }

  @Test("Oblique segments agree with an independent face-plane oracle")
  func faceOracle() {
    // Independently intersect the six planes, retaining only points on the face.
    // Power-of-two positions/directions keep these cases exactly representable.
    func reference(_ origin: SIMD3<Float>, _ direction: SIMD3<Float>) -> ClosedRange<Float>? {
      var candidates: [Float] = []
      for endpoint: Float in [0, 1] {
        let point = origin + endpoint * direction
        if all(point .>= box.min) && all(point .<= box.max) { candidates.append(endpoint) }
      }
      for axis in 0..<3 where direction[axis] != 0 {
        for plane in [box.min[axis], box.max[axis]] {
          let t = (plane - origin[axis]) / direction[axis]
          guard t >= 0 && t <= 1 else { continue }
          let point = origin + t * direction
          if (0..<3).filter({ $0 != axis }).allSatisfy({
            point[$0] >= box.min[$0] && point[$0] <= box.max[$0]
          }) {
            candidates.append(t)
          }
        }
      }
      guard let first = candidates.min(), let last = candidates.max() else { return nil }
      return first...last
    }
    for x: Float in [-4, 0, 4, 8] {
      for y: Float in [-4, 0, 4, 8, 12] {
        for z: Float in [-4, 0, 4, 8, 12] {
          let origin = SIMD3(x, y, z)
          for direction: SIMD3<Float> in [[8, 4, 8], [-8, 8, 4], [4, -8, 8], [8, 0, -4]] {
            #expect(
              box.intersection(origin: origin, direction: direction, parameters: 0...1)
                == reference(origin, direction))
          }
        }
      }
    }
  }
}
