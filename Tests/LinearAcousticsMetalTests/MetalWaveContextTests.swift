import LinearAcoustics
import Metal
import Testing

@testable import LinearAcousticsMetal

@Suite("Reusable immutable Metal wave context") struct MetalWaveContextTests {
  private func twoCells() throws -> PreparedWaveGrid {
    try waveGrid(mask: [1, 1, 0, 0, 0, 0, 0, 0])
  }

  @Test("Shared pipelines keep queues, fields, staging and output independently owned")
  func ownership() throws {
    let device = try waveDevice()
    let context = try MetalWaveContext(device: device)
    #expect(context.deviceName == device.name && context.deviceRegistryID == device.registryID)
    let g = try twoCells()
    let initial = waveFields([1, 0, 100, 100, 100, 100, 100, 100])
    let a = try MetalWaveStepper(context: context, grid: g, initialFields: initial)
    let b = try MetalWaveStepper(context: context, grid: g, initialFields: initial)
    #expect(a.pipelineIdentities == b.pipelineIdentities && a.pipelineIdentities.count == 6)
    #expect(a.queueIdentity != b.queueIdentity)
    #expect(Set(a.fieldBufferIdentities).isDisjoint(with: b.fieldBufferIdentities))
    let source = try a.prepareSource(
      PreparedPressureSource(grid: g, cellIndices: [1], coefficients: [0.5]))
    let plan = try a.prepareObservation(
      PreparedWaveObservation(grid: g, receivers: [metalReceiver(1)]))
    let saved = try b.snapshot()
    let frames = try a.advance(source: source, amplitudes: [2, -1], observing: plan)
    // Independent two-cell recurrence: u1=1/8; psi1=(63/64,65/64).
    // u2=31/256; psi2=(1985/2048,1087/2048).
    #expect(frames.map(\.pressureOverDensity) == [[1.015625], [0.53076171875]])
    #expect(
      arrays(try a.snapshot()) == [
        [0.96923828125, 0.53076171875, 100, 100, 100, 100, 100, 100],
        [0.12109375, 0, 0, 0, 0, 0, 0, 0],
        Array(repeating: 0, count: 8), Array(repeating: 0, count: 8),
      ])
    #expect(arrays(try b.snapshot()) == arrays(saved) && b.pressureStepIndex == 0)
    let other = try b.advance(source: source, amplitudes: [2, -1], observing: plan)
    #expect(other.map(\.pressureOverDensity) == frames.map(\.pressureOverDensity))
    #expect(a.sourceStagingBufferIdentity != b.sourceStagingBufferIdentity)
    #expect(Set(a.observationBufferIdentities).isDisjoint(with: b.observationBufferIdentities))
  }

  @Test("A failed completed command invalidates only its run, keeping a reusable context")
  func failureIsolation() throws {
    let context = try MetalWaveContext(device: waveDevice())
    let g = try twoCells()
    let initial = waveFields([1, 0, 100, 100, 100, 100, 100, 100])
    var completions = 0
    let failed = try MetalWaveStepper(
      context: context, grid: g, initialFields: initial,
      completion: { command in
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { throw MetalWaveError.commandFailed("device") }
        completions += 1
        if completions == 2 { throw MetalWaveError.commandFailed("injected") }
      })
    let sibling = try MetalWaveStepper(context: context, grid: g, initialFields: initial)
    #expect(throws: MetalWaveError.commandFailed("injected")) { try failed.advance(steps: 257) }
    #expect(failed.pressureStepIndex == 128 && completions == 2)
    #expect(throws: WaveError.invalidatedState) { try failed.advance() }
    try sibling.advance()
    #expect(sibling.pressureStepIndex == 1)
    #expect(
      try sibling.snapshot().pressureOverDensity == [
        0.984375, 0.015625, 100, 100, 100, 100, 100, 100,
      ])
    let fresh = try MetalWaveStepper(context: context, grid: g, initialFields: initial)
    #expect(fresh.pressureStepIndex == 0 && fresh.pipelineIdentities == sibling.pipelineIdentities)
    #expect(
      arrays(try fresh.snapshot())
        == arrays(
          try MetalWaveStepper(
            device: waveDevice(), grid: g, initialFields: initial
          ).snapshot()))
  }

  @Test(
    "Concurrent independent runs preserve every field and receiver bit against device initialization"
  )
  func concurrent() async throws {
    let context = try MetalWaveContext(device: waveDevice())
    let g = try waveGrid([5, 4, 3], dt: 0.03125, spacing: [1, 0.8, 1.3], speed: 1.7)
    let source = try PreparedPressureSource(
      grid: g, cellIndices: [7, 31], coefficients: [0.25, -0.125])
    let plan = try PreparedWaveObservation(
      grid: g,
      receivers: [
        metalReceiver(7), metalReceiver(26, velocityCell: 26, axis: [0.5, -0.25, 0.75]),
        metalReceiver(7),
      ])
    func initial(_ run: Int) -> WaveInitialFields {
      waveFields((0..<g.cellCount).map { Float(($0 * 3 + run) % 11 - 5) / 64 })
    }
    func amplitudes(_ run: Int) -> [Float] { (0..<257).map { Float(($0 + run) % 7 - 3) / 128 } }
    func execute(_ stepper: MetalWaveStepper, _ run: Int) throws -> [[UInt64]] {
      let s = try stepper.prepareSource(source)
      let o = try stepper.prepareObservation(plan)
      let q = amplitudes(run)
      var frames: [WaveObservationFrame] = []
      for range in [0..<7, 7..<127, 127..<255, 255..<257] {
        frames += try stepper.advance(source: s, amplitudes: Array(q[range]), observing: o)
      }
      #expect(frames.count == 257 && stepper.pressureStepIndex == 257)
      #expect(frames.map(\.pressureStepIndex) == Array(1...257))
      let fieldBits = arrays(try stepper.snapshot()).map { $0.map { UInt64($0.bitPattern) } }
      let frameBits = frames.map { f in
        f.pressureOverDensity.map(\.bitPattern)
          + f.projectedVelocity.map { $0?.bitPattern ?? UInt64.max }
      }
      return fieldBits + frameBits
    }
    var controls: [[[UInt64]]] = []
    for run in 0..<4 {
      controls.append(
        try execute(
          MetalWaveStepper(
            device: waveDevice(), grid: g, initialFields: initial(run)), run))
    }
    let actual = try await withThrowingTaskGroup(of: (Int, [[UInt64]]).self) { group in
      for run in 0..<4 {
        group.addTask {
          (
            run,
            try execute(
              MetalWaveStepper(context: context, grid: g, initialFields: initial(run)), run)
          )
        }
      }
      var results: [(Int, [[UInt64]])] = []
      for try await result in group { results.append(result) }
      return results.sorted { $0.0 < $1.0 }.map(\.1)
    }
    #expect(actual == controls && actual.count == 4)
  }
}
