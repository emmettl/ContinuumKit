import Foundation
import LinearAcoustics
import Metal
import Testing

@testable import LinearAcousticsMetal

@Suite("Resident source-free Metal wave backend") struct MetalWaveTests {
  @Test("Packaged shader uses the nine-scalar 36-byte Swift/Metal ABI")
  func abi() throws {
    typealias Grid = MetalWaveStepper.Grid
    #expect(
      MemoryLayout<Grid>.size == 36 && MemoryLayout<Grid>.stride == 36
        && MemoryLayout<Grid>.alignment == 4)
    let offsets = [
      MemoryLayout<Grid>.offset(of: \.nx), MemoryLayout<Grid>.offset(of: \.ny),
      MemoryLayout<Grid>.offset(of: \.nz),
      MemoryLayout<Grid>.offset(of: \.kx), MemoryLayout<Grid>.offset(of: \.ky),
      MemoryLayout<Grid>.offset(of: \.kz),
      MemoryLayout<Grid>.offset(of: \.bx), MemoryLayout<Grid>.offset(of: \.by),
      MemoryLayout<Grid>.offset(of: \.bz),
    ]
    #expect(offsets == [0, 4, 8, 12, 16, 20, 24, 28, 32])
    let grid = try waveGrid([5, 4, 3], dt: 0.03125, spacing: [1, 0.8, 1.3], speed: 1.7)
    var value = Grid(grid)
    let device = try waveDevice()
    let source =
      try MetalWaveStepper.shaderSource() + """
        kernel void probeABI(constant Grid& g [[buffer(0)]], device uint* output [[buffer(1)]], uint id [[thread_position_in_grid]]) {
          switch (id) {
            case 0: output[id]=g.nx; break; case 1: output[id]=g.ny; break; case 2: output[id]=g.nz; break;
            case 3: output[id]=as_type<uint>(g.kx); break; case 4: output[id]=as_type<uint>(g.ky); break; case 5: output[id]=as_type<uint>(g.kz); break;
            case 6: output[id]=as_type<uint>(g.bx); break; case 7: output[id]=as_type<uint>(g.by); break; case 8: output[id]=as_type<uint>(g.bz); break;
          }
        }
        """
    let library = try device.makeLibrary(source: source, options: nil)
    let function = try #require(library.makeFunction(name: "probeABI"))
    let pipeline = try device.makeComputePipelineState(function: function)
    let buffer = try #require(device.makeBuffer(length: 36, options: .storageModeShared))
    let queue = try #require(device.makeCommandQueue())
    let command = try #require(queue.makeCommandBuffer())
    let encoder = try #require(command.makeComputeCommandEncoder())
    encoder.setComputePipelineState(pipeline)
    encoder.setBytes(&value, length: 36, index: 0)
    encoder.setBuffer(buffer, offset: 0, index: 1)
    encoder.dispatchThreads(
      MTLSize(width: 9, height: 1, depth: 1),
      threadsPerThreadgroup: MTLSize(width: 9, height: 1, depth: 1))
    encoder.endEncoding()
    command.commit()
    command.waitUntilCompleted()
    #expect(command.status == .completed)
    let actual = Array(
      UnsafeBufferPointer(start: buffer.contents().assumingMemoryBound(to: UInt32.self), count: 9))
    #expect(
      actual == [
        5, 4, 3, value.kx.bitPattern, value.ky.bitPattern, value.kz.bitPattern, value.bx.bitPattern,
        value.by.bitPattern, value.bz.bitPattern,
      ])
  }
  @Test("Hand-derived first step and half clocks require actual GPU completion")
  func golden() throws {
    let grid = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    let gpu = try MetalWaveStepper(
      device: waveDevice(), grid: grid,
      initialFields: waveFields([1, 0, 100, 100, 100, 100, 100, 100]))
    #expect(try gpu.snapshot().velocityTime == -0.0625)
    try gpu.advance()
    let h = try gpu.snapshot()
    #expect(h.pressureOverDensity == [0.984375, 0.015625, 100, 100, 100, 100, 100, 100])
    #expect(h.velocityX == [0.125, 0, 0, 0, 0, 0, 0, 0])
    #expect(h.velocityY.allSatisfy { $0 == 0 } && h.velocityZ.allSatisfy { $0 == 0 })
    #expect(h.pressureStepIndex == 1 && h.pressureTime == 0.125 && h.velocityTime == 0.0625)
  }
  @Test(
    "Owned resident buffers, zero steps, snapshots and multiple command batches preserve whole fields"
  )
  func batching() throws {
    let d: SIMD3<Int> = [17, 13, 9]
    let n = d.x * d.y * d.z
    var mask: [UInt8] = (0..<n).map { $0 % 19 == 5 ? 0 : 1 }
    var p: [Float] = (0..<n).map { mask[$0] == 1 ? Float(cos(Double($0) * 0.43)) : 100 }
    let c = 1.7
    let g = try waveGrid(
      d, mask: mask, dt: 0.1, spacing: [1, 0.8, 1.3], speed: c,
      faces: waveFaces(d, mask, loss: 0.003))
    let initial = waveFields(p)
    let gpu = try MetalWaveStepper(device: waveDevice(), grid: g, initialFields: initial)
    let split = try MetalWaveStepper(device: waveDevice(), grid: g, initialFields: initial)
    let cpu = try CPUWaveStepper(grid: g, initialFields: initial)
    let identities = gpu.fieldBufferIdentities
    let saved = try gpu.snapshot()
    #expect(Set(identities).count == 4)
    p[0] = 99
    mask[0] = 0
    try gpu.advance(steps: 0)
    #expect(arrays(try gpu.snapshot()) == arrays(saved))
    try gpu.advance(steps: 257)
    try split.advance(steps: 127)
    try split.advance(steps: 130)
    try cpu.advance(steps: 257)
    let actual = try gpu.snapshot()
    let other = try split.snapshot()
    let reference = try cpu.snapshot()
    #expect(
      actual.pressureStepIndex == 257 && actual.pressureTime == reference.pressureTime
        && actual.velocityTime == reference.velocityTime)
    #expect(
      gpu.fieldBufferIdentities == identities && saved.pressureStepIndex == 0
        && saved.pressureOverDensity[0] == initial.pressureOverDensity[0])
    #expect(arrays(actual) == arrays(other))
    for f in 0..<4 {
      for at in 0..<n {
        let difference = abs(Double(arrays(actual)[f][at]) - Double(arrays(reference)[f][at]))
        #expect(difference < (f == 0 ? 1e-4 : 1e-4 / c))
        if g.activeCells[at] == 0 { #expect(arrays(actual)[f][at] == (f == 0 ? 100 : 0)) }
      }
    }
  }
  @Test("Both backends reject invalid initial fields and closed-slot contamination")
  func invalidInitial() throws {
    let device = try waveDevice()
    let g = try waveGrid(mask: [1, 0, 0, 0, 0, 0, 0, 0])
    #expect(throws: WaveError.self) {
      try MetalWaveStepper(device: device, grid: g, initialFields: waveFields([1]))
    }
    #expect(throws: WaveError.invalidInitialFields) {
      try MetalWaveStepper(
        device: device, grid: g, initialFields: waveFields([.nan, 0, 0, 0, 0, 0, 0, 0]))
    }
    var v = Array(repeating: [Float](repeating: 0, count: 8), count: 3)
    v[0][0] = 1
    #expect(throws: WaveError.closedFaceVelocity(field: 1, cell: 0)) {
      try MetalWaveStepper(
        device: device, grid: g, initialFields: waveFields(Array(repeating: 0, count: 8), v))
    }
  }
  @Test("Bad counts, index overflow and nonfinite derived clocks fail before GPU mutation")
  func invalidSteps() throws {
    let device = try waveDevice()
    let gpu = try MetalWaveStepper(
      device: device, grid: waveGrid(), initialFields: waveFields(Array(repeating: 1, count: 8)))
    try gpu.advance()
    let saved = try gpu.snapshot()
    #expect(throws: WaveError.invalidStepCount) { try gpu.advance(steps: -1) }
    #expect(throws: WaveError.stepIndexOverflow) { try gpu.advance(steps: Int.max) }
    #expect(arrays(try gpu.snapshot()) == arrays(saved) && gpu.pressureStepIndex == 1)
    let huge = try MetalWaveStepper(
      device: device, grid: waveGrid(dt: 1e308, spacing: [1e308, 1e308, 1e308], speed: 1e-20),
      initialFields: waveFields(Array(repeating: 1, count: 8)))
    try huge.advance()
    #expect(throws: WaveError.stepClockOverflow) { try huge.advance() }
    let hugeSnapshot = try huge.snapshot()
    #expect(huge.pressureStepIndex == 1 && hugeSnapshot.pressureTime.isFinite)
  }
  @Test(
    "Arithmetic overflow is rejected on snapshot; completed GPU clock is not a finite-state claim")
  func nonfinite() throws {
    let g = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    let a = Float.greatestFiniteMagnitude
    let gpu = try MetalWaveStepper(
      device: waveDevice(), grid: g, initialFields: waveFields([a, -a, 0, 0, 0, 0, 0, 0]))
    try gpu.advance()
    #expect(gpu.pressureStepIndex == 1)
    #expect(throws: WaveError.nonfiniteOutput) { try gpu.snapshot() }
    #expect(throws: WaveError.invalidatedState) { try gpu.snapshot() }
    #expect(throws: WaveError.invalidatedState) { try gpu.advance(steps: 0) }
  }
  @Test(
    "Injected submission failure after actual GPU work invalidates state and preserves acknowledged batch clock"
  )
  func submissionFailure() throws {
    var completions = 0
    let device = try waveDevice()
    let g = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    let gpu = try MetalWaveStepper(
      device: device, grid: g, initialFields: waveFields([1, 0, 100, 100, 100, 100, 100, 100]),
      completion: { commands in
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else {
          throw MetalWaveError.commandFailed("unexpected actual device failure")
        }
        completions += 1
        if completions == 2 { throw MetalWaveError.commandFailed("injected completion failure") }
      })
    #expect(throws: MetalWaveError.commandFailed("injected completion failure")) {
      try gpu.advance(steps: 257)
    }
    #expect(completions == 2 && gpu.pressureStepIndex == 128)
    #expect(throws: WaveError.invalidatedState) { try gpu.snapshot() }
    #expect(throws: WaveError.invalidatedState) { try gpu.advance() }
  }
}
