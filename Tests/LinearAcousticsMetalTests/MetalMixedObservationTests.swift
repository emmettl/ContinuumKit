import LinearAcoustics
import Metal
import Testing

@testable import LinearAcousticsMetal

@Suite("Single-dispatch mixed Metal observations") struct MetalMixedObservationTests {
  @Test("Affine pressure and face velocity preserve arbitrary mixed receiver order")
  func affine() throws {
    let g = try waveGrid([4, 4, 4])
    var p = [Float](repeating: 0, count: 64)
    var u = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    for at in 0..<64 {
      let x = at % 4
      let y = at / 4 % 4
      let z = at / 16
      p[at] = Float(2 + 3 * x - 2 * y) + Float(z) / 2
      if x < 3 { u[0][at] = Float(x + 1) * 1.5 }
      if y < 3 { u[1][at] = Float(y + 1) / 2 }
      if z < 3 { u[2][at] = -Float(z + 1) }
    }
    let gpu = try MetalWaveStepper(device: waveDevice(), grid: g, initialFields: waveFields(p, u))
    let stencil = WaveReceiverStencil(
      pressureCells: [21, 22, 25, 26, 37, 38, 41, 42],
      pressureWeights: Array(repeating: 0.125, count: 8), velocityCell: 21,
      velocityAxis: [0.5, -0.25, 0.75])
    let plan = try gpu.prepareObservation(
      PreparedWaveObservation(
        grid: g,
        receivers: [
          metalReceiver(0), stencil, metalReceiver(63),
          metalReceiver(21, velocityCell: 21, axis: [0, 1, 0]),
        ]))
    let before = try gpu.snapshot()
    let result = try gpu.observe(plan)
    #expect(result.pressureOverDensity == [2, 4.25, 6.5, 3.5])
    #expect(result.projectedVelocity == [nil, -0.1875, nil, 0.75])
    #expect(
      result.pressureStepIndex == 0 && result.velocityTime == -g.timeStep / 2
        && result.arithmetic == .metalFloat)
    #expect(arrays(try gpu.snapshot()) == arrays(before))
  }

  @Test(
    "Absent mixed probes never read overflowing face pairs; errors retain original receiver index")
  func absentProbe() throws {
    let g = try waveGrid([4, 4, 4])
    let maximum = Float.greatestFiniteMagnitude
    var u = Array(repeating: [Float](repeating: 0, count: 64), count: 3)
    u[0][20] = maximum
    u[0][21] = maximum
    let gpu = try MetalWaveStepper(
      device: waveDevice(), grid: g, initialFields: waveFields(Array(repeating: 7, count: 64), u))
    let valid = try gpu.prepareObservation(
      PreparedWaveObservation(
        grid: g,
        receivers: [
          metalReceiver(0), metalReceiver(42, velocityCell: 42, axis: [1, 0, 0]), metalReceiver(21),
        ]))
    let result = try gpu.observe(valid)
    #expect(result.pressureOverDensity == [7, 7, 7] && result.projectedVelocity == [nil, 0, nil])
    let overflow = try gpu.prepareObservation(
      PreparedWaveObservation(
        grid: g,
        receivers: [
          metalReceiver(0), metalReceiver(21, velocityCell: 21, axis: [1, 0, 0]), metalReceiver(21),
        ]))
    #expect(throws: WaveObservationError.nonfiniteResult(receiver: 1)) { try gpu.observe(overflow) }
    let after = try gpu.snapshot()
    #expect(gpu.pressureStepIndex == 0 && after.velocityX[20] == maximum)
    let again = try gpu.observe(valid)
    #expect(
      again.pressureOverDensity == result.pressureOverDensity
        && again.projectedVelocity == result.projectedVelocity)
  }
}
