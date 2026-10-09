import Foundation
import LinearAcoustics
import Metal
import Testing

@testable import LinearAcousticsMetal

enum DeviceTestError: Error { case unavailable }
func waveDevice() throws -> any MTLDevice {
  guard let device = MTLCreateSystemDefaultDevice() else { throw DeviceTestError.unavailable }
  return device
}
// Independently prepared integer adjacency; no application geometry or production helper.
func waveFaces(_ d: SIMD3<Int>, _ mask: [UInt8], loss: Float = 0) -> [Float] {
  let n = mask.count
  let strides = [1, d.x, d.x * d.y]
  guard n == d.x * d.y * d.z else { return [] }
  var faces = [Float](repeating: -1, count: 6 * n)
  for at in 0..<n where mask[at] == 1 {
    let xyz = [at % d.x, at / d.x % d.y, at / (d.x * d.y)]
    for side in 0..<6 {
      let axis = side / 2
      let plus = side % 2 == 1
      let within = plus ? xyz[axis] + 1 < d[axis] : xyz[axis] > 0
      let neighbour = at + (plus ? strides[axis] : -strides[axis])
      faces[side * n + at] = within && mask[neighbour] == 1 ? -1 : loss
    }
  }
  return faces
}
func waveGrid(
  _ d: SIMD3<Int> = [2, 2, 2], mask: [UInt8]? = nil, dt: Double = 0.125,
  spacing: SIMD3<Double> = [1, 1, 1], speed: Double = 1, density: Double = 1,
  faces: [Float]? = nil
) throws -> PreparedWaveGrid {
  let inside = mask ?? [UInt8](repeating: 1, count: d.x * d.y * d.z)
  return try PreparedWaveGrid(
    dimensions: d, spacing: spacing, soundSpeed: speed,
    density: density, timeStep: dt, activeCells: inside,
    boundaryTerms: faces ?? waveFaces(d, inside))
}
func waveFields(_ p: [Float], _ velocities: [[Float]]? = nil) -> WaveInitialFields {
  let u = velocities ?? Array(repeating: [Float](repeating: 0, count: p.count), count: 3)
  return WaveInitialFields(
    pressureOverDensity: p, velocityX: u[0], velocityY: u[1], velocityZ: u[2])
}
func arrays(_ s: WaveSnapshot) -> [[Float]] {
  [s.pressureOverDensity, s.velocityX, s.velocityY, s.velocityZ]
}
