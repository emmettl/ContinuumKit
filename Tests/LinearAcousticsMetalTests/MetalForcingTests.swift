import Foundation
import LinearAcoustics
import Metal
import Testing

@testable import LinearAcousticsMetal

@Suite("Resident Metal pressure forcing") struct MetalForcingTests {
  @Test("Actual injection ABI and phase order agree with a binary two-cell reference")
  func golden() throws {
    let g = try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
    let source = try PreparedPressureSource(grid: g, cellIndices: [1], coefficients: [0.5])
    let gpu = try MetalWaveStepper(
      device: waveDevice(), grid: g,
      initialFields: waveFields([1, 0, 100, 100, 100, 100, 100, 100]))
    let prepared = try gpu.prepareSource(source)
    try gpu.advance(source: prepared, amplitudes: [2, -1])
    let h = try gpu.snapshot()
    #expect(h.pressureOverDensity == [0.96923828125, 0.53076171875, 100, 100, 100, 100, 100, 100])
    #expect(h.velocityX == [0.12109375, 0, 0, 0, 0, 0, 0, 0])
    #expect(h.velocityY.allSatisfy { $0 == 0 } && h.velocityZ.allSatisfy { $0 == 0 })
    #expect(h.pressureStepIndex == 2 && h.pressureTime == 0.25 && h.velocityTime == 0.1875)
  }

  @Test("Resident source/field/staging ownership survives 257 steps, chunking and plan switching")
  func residency() throws {
    let d: SIMD3<Int> = [4, 3, 2]
    let mask: [UInt8] = (0..<24).map { $0 == 7 ? 0 : 1 }
    let g = try waveGrid(
      d, mask: mask, dt: 0.03125, spacing: [1, 0.8, 1.3], speed: 1.7,
      faces: waveFaces(d, mask, loss: 0.003))
    var cells = Array((0..<24).filter { mask[$0] == 1 }.prefix(17))
    var weights: [Float] = cells.map { Float(0.015 * cos(Double($0) * 0.3)) }
    let source = try PreparedPressureSource(grid: g, cellIndices: cells, coefficients: weights)
    let device = try waveDevice()
    let initial = waveFields((0..<24).map { mask[$0] == 0 ? 100 : Float(sin(Double($0))) })
    let gpu = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let split = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let cpu = try CPUWaveStepper(grid: g, initialFields: initial)
    let prepared = try gpu.prepareSource(source)
    let fields = gpu.fieldBufferIdentities
    let sourceBuffers = prepared.bufferIdentities
    #expect(Set(fields + sourceBuffers).count == 6 && gpu.sourceStagingBufferIdentity == nil)
    cells[0] = 23
    weights[0] = 99
    let saved = try gpu.snapshot()
    try gpu.advance(source: prepared, amplitudes: [])
    #expect(arrays(try gpu.snapshot()) == arrays(saved) && gpu.sourceStagingBufferIdentity == nil)
    let amplitudes: [Float] = (0..<257).map { Float(0.37 * sin(Double($0) * 0.31)) }
    try gpu.advance(source: prepared, amplitudes: amplitudes)
    try split.advance(source: prepared, amplitudes: Array(amplitudes.prefix(127)))
    try split.advance(source: prepared, amplitudes: Array(amplitudes.dropFirst(127)))
    try cpu.advance(source: source, amplitudes: amplitudes)
    let a = try gpu.snapshot()
    let b = try split.snapshot()
    let c = try cpu.snapshot()
    #expect(
      a.pressureStepIndex == 257 && a.velocityTime == c.velocityTime
        && a.pressureTime == c.pressureTime)
    #expect(arrays(a).map { $0.map(\.bitPattern) } == arrays(b).map { $0.map(\.bitPattern) })
    for field in 0..<4 {
      for at in 0..<24 {
        #expect(abs(Double(arrays(a)[field][at]) - Double(arrays(c)[field][at])) < 1e-4)
        if mask[at] == 0 { #expect(arrays(a)[field][at] == (field == 0 ? 100 : 0)) }
      }
    }
    let staging = try #require(gpu.sourceStagingBufferIdentity)
    let alternate = try gpu.prepareSource(
      PreparedPressureSource(grid: g, cellIndices: [23], coefficients: [-0.125]))
    try gpu.advance(source: alternate, amplitudes: [-0.5, 1])
    try gpu.advance(source: prepared, amplitudes: [0.25])
    #expect(
      gpu.fieldBufferIdentities == fields && prepared.bufferIdentities == sourceBuffers
        && gpu.sourceStagingBufferIdentity == staging)
    #expect(
      saved.pressureStepIndex == 0 && saved.pressureOverDensity == initial.pressureOverDensity)
  }

  @Test("Whole-batch finite inputs, grid binding and clocks reject without GPU mutation")
  func rejectedInputs() throws {
    let g = try waveGrid()
    let device = try waveDevice()
    let gpu = try MetalWaveStepper(
      device: device, grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let source = try PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [1])
    let prepared = try gpu.prepareSource(source)
    for bad in [Float.nan, .infinity, -.infinity] {
      #expect(throws: PressureSourceError.nonfiniteAmplitude(step: 1)) {
        try gpu.advance(source: prepared, amplitudes: [1, bad])
      }
      let h = try gpu.snapshot()
      #expect(
        h.pressureStepIndex == 0 && h.pressureOverDensity.allSatisfy { $0 == 0 }
          && gpu.sourceStagingBufferIdentity == nil)
    }
    let other = try MetalWaveStepper(
      device: device, grid: waveGrid(), initialFields: waveFields(Array(repeating: 0, count: 8)))
    #expect(throws: PressureSourceError.gridMismatch) { try other.prepareSource(source) }
    #expect(throws: PressureSourceError.gridMismatch) {
      try other.advance(source: prepared, amplitudes: [])
    }
    let huge = try waveGrid(dt: 1e308, spacing: [1e308, 1e308, 1e308], speed: 1e-20)
    let clock = try MetalWaveStepper(
      device: device, grid: huge, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let empty = try clock.prepareSource(
      PreparedPressureSource(grid: huge, cellIndices: [], coefficients: []))
    #expect(throws: WaveError.stepClockOverflow) {
      try clock.advance(source: empty, amplitudes: [0, 0])
    }
    #expect(clock.pressureStepIndex == 0 && clock.sourceStagingBufferIdentity == nil)
  }

  @Test("An empty resident plan preserves source-free fields without source allocations")
  func emptyPlan() throws {
    let g = try waveGrid()
    let device = try waveDevice()
    let initial = waveFields([1, -0.25, 0.5, 0, 0, 0, 0, 0])
    let a = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let b = try MetalWaveStepper(device: device, grid: g, initialFields: initial)
    let empty = try b.prepareSource(
      PreparedPressureSource(grid: g, cellIndices: [], coefficients: []))
    #expect(empty.bufferIdentities.isEmpty)
    try a.advance(steps: 13)
    try b.advance(source: empty, amplitudes: Array(repeating: -3, count: 13))
    #expect(
      arrays(try a.snapshot()).map { $0.map(\.bitPattern) }
        == arrays(try b.snapshot()).map { $0.map(\.bitPattern) })
    #expect(b.sourceStagingBufferIdentity == nil)
  }

  @Test(
    "Source overflow is checked on snapshot; completed commands retain their acknowledged clock")
  func nonfinite() throws {
    let g = try waveGrid(mask: [1, 0, 0, 0, 0, 0, 0, 0])
    let gpu = try MetalWaveStepper(
      device: waveDevice(), grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)))
    let source = try gpu.prepareSource(
      PreparedPressureSource(
        grid: g, cellIndices: [0], coefficients: [Float.greatestFiniteMagnitude]))
    try gpu.advance(source: source, amplitudes: [0, 2])
    #expect(gpu.pressureStepIndex == 2)
    #expect(throws: WaveError.nonfiniteOutput) { try gpu.snapshot() }
    #expect(throws: WaveError.invalidatedState) { try gpu.advance(source: source, amplitudes: []) }
    #expect(throws: WaveError.invalidatedState) { try gpu.prepareSource(source.source) }
  }

  @Test(
    "Injected completion failure after actual forced GPU batches preserves only acknowledged steps")
  func completionFailure() throws {
    let g = try waveGrid()
    let device = try waveDevice()
    var completions = 0
    let gpu = try MetalWaveStepper(
      device: device, grid: g, initialFields: waveFields(Array(repeating: 0, count: 8)),
      completion: { commands in
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else {
          throw MetalWaveError.commandFailed("actual failure")
        }
        completions += 1
        if completions == 2 {
          throw MetalWaveError.commandFailed("injected forced completion failure")
        }
      })
    let source = try gpu.prepareSource(
      PreparedPressureSource(grid: g, cellIndices: [0], coefficients: [0.125]))
    #expect(throws: MetalWaveError.commandFailed("injected forced completion failure")) {
      try gpu.advance(source: source, amplitudes: Array(repeating: 0.5, count: 257))
    }
    #expect(completions == 2 && gpu.pressureStepIndex == 128)
    #expect(throws: WaveError.invalidatedState) { try gpu.snapshot() }
    #expect(throws: WaveError.invalidatedState) { try gpu.advance(source: source, amplitudes: [0]) }
  }
}
