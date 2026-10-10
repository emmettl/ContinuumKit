import LinearAcoustics
import Metal
import Testing

@testable import LinearAcousticsMetal

@Suite("Capacity-bounded Metal field groups") struct MetalFieldGroupTests {
  @Test("Small-grid threshold, uneven capacities and physical axis limits remain legal")
  func limits() throws {
    let wide = MTLSize(width: 1024, height: 1024, depth: 64)
    for count in [8, 4095, 4096, 331800] {
      for cap in [1, 8, 16, 31, 32, 33, 64, 96, 128, 192, 255, 256, 512, 1024] {
        for axes in [
          wide, MTLSize(width: 16, height: 2, depth: 1), MTLSize(width: 8, height: 1, depth: 2),
        ] {
          let g = try MetalWaveStepper.fieldThreadgroup(
            cellCount: count, pipelineLimit: cap, deviceLimit: axes)
          #expect(g.width > 0 && g.height > 0 && g.depth > 0)
          #expect(g.width <= axes.width && g.height <= axes.height && g.depth <= axes.depth)
          #expect(g.width * g.height * g.depth <= cap)
          if count < 4096 { #expect(g.height == 1 && g.depth == 1) }
          if count >= 4096 && cap >= 256 && axes.width == 1024 {
            #expect(g.width == 32 && g.height == 4 && g.depth == 2)
          }
        }
      }
    }
    for (count, cap, axes) in [
      (0, 256, wide), (8, 0, wide), (8, 256, MTLSize(width: 0, height: 4, depth: 2)),
    ] {
      #expect(throws: MetalWaveError.commandEncodingFailed) {
        try MetalWaveStepper.fieldThreadgroup(
          cellCount: count, pipelineLimit: cap, deviceLimit: axes)
      }
    }
  }

  @Test("Larger uneven masked fields retain independent CPU and exact batching references")
  func uneven() throws {
    let d = SIMD3<Int>(17, 9, 29)
    let n = d.x * d.y * d.z
    var mask = [UInt8](repeating: 1, count: n)
    for at in 0..<n where at % 37 == 0 { mask[at] = 0 }
    let g = try waveGrid(
      d, mask: mask, dt: 0.03125, spacing: [1, 0.8, 1.3], speed: 1.7,
      faces: waveFaces(d, mask, loss: 0.001))
    let initial = waveFields((0..<n).map { Float($0 % 17 - 8) / 512 })
    let device = try waveDevice()
    let context = try MetalWaveContext(device: device)
    let a = try MetalWaveStepper(context: context, grid: g, initialFields: initial)
    let b = try MetalWaveStepper(context: context, grid: g, initialFields: initial)
    let cpu = try CPUWaveStepper(grid: g, initialFields: initial)
    try a.advance(steps: 257)
    try b.advance(steps: 7)
    try b.advance(steps: 120)
    try b.advance(steps: 130)
    try cpu.advance(steps: 257)
    let x = arrays(try a.snapshot())
    let y = arrays(try b.snapshot())
    let z = arrays(try cpu.snapshot())
    #expect(x.map { $0.map(\.bitPattern) } == y.map { $0.map(\.bitPattern) })
    #expect(a.pressureStepIndex == 257 && b.pressureStepIndex == 257)
    for (gpu, reference) in zip(x, z) {
      #expect(zip(gpu, reference).allSatisfy { abs($0 - $1) <= 2e-5 })
    }
  }
}
