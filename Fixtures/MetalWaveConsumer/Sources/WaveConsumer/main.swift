import LinearAcoustics
import LinearAcousticsMetal
import Metal

enum ConsumerError: Error { case failed }
func require(_ value: Bool) throws { if !value { throw ConsumerError.failed } }
let mask: [UInt8] = [1, 1, 0, 0, 0, 0, 0, 0]
var faces = [Float](repeating: -1, count: 48)
for at in 0...1 { for side in 0..<6 { faces[side * 8 + at] = 0 } }
faces[8] = -1
faces[1] = -1
let grid = try PreparedWaveGrid(
  dimensions: [2, 2, 2], spacing: [1, 1, 1], soundSpeed: 1,
  density: 1, timeStep: 0.125, activeCells: mask, boundaryTerms: faces)
let zero = [Float](repeating: 0, count: 8)
let fields = WaveInitialFields(
  pressureOverDensity: [1, 0, 100, 100, 100, 100, 100, 100],
  velocityX: zero, velocityY: zero, velocityZ: zero)
guard let device = MTLCreateSystemDefaultDevice() else { throw ConsumerError.failed }
let context = try MetalWaveContext(device: device)
try require(context.deviceName == device.name && context.deviceRegistryID == device.registryID)
let stepper = try MetalWaveStepper(context: context, grid: grid, initialFields: fields)
let saved = try stepper.snapshot()
try stepper.advance()
let first = try stepper.snapshot()
try require(first.pressureOverDensity == [0.984375, 0.015625, 100, 100, 100, 100, 100, 100])
try require(first.velocityX == [0.125, 0, 0, 0, 0, 0, 0, 0])
try require(first.pressureTime == 0.125 && first.velocityTime == 0.0625)
try stepper.advance(steps: 15)
try require(saved.pressureOverDensity[0] == 1 && saved.pressureStepIndex == 0)
let split = try MetalWaveStepper(context: context, grid: grid, initialFields: fields)
try split.advance(steps: 7)
try split.advance(steps: 9)
let a = try stepper.snapshot()
let b = try split.snapshot()
try require(a.pressureOverDensity == b.pressureOverDensity && a.velocityX == b.velocityX)
try require(a.velocityY == zero && a.velocityZ == zero && a.pressureStepIndex == 16)
print(
  "PASS LinearAcousticsMetal fetched resident GPU product: all native fields, clocks, ownership and composition"
)

let cpu = try CPUWaveStepper(grid: grid, initialFields: fields)
try cpu.advance(steps: 257)
let gpu = try MetalWaveStepper(context: context, grid: grid, initialFields: fields)
try gpu.advance(steps: 257)
let cpuResult = try cpu.snapshot()
let gpuResult = try gpu.snapshot()
try require(gpuResult.pressureStepIndex == 257)
for pair in zip(
  [cpuResult.pressureOverDensity, cpuResult.velocityX, cpuResult.velocityY, cpuResult.velocityZ],
  [gpuResult.pressureOverDensity, gpuResult.velocityX, gpuResult.velocityY, gpuResult.velocityZ])
{
  try require(zip(pair.0, pair.1).allSatisfy { abs($0 - $1) < 1e-4 })
}
print(
  "PASS actual packaged wave Metal kernels, multiple command batches and CPU/native fields:",
  device.name)

let forced = try MetalWaveStepper(context: context, grid: grid, initialFields: fields)
let source = try forced.prepareSource(
  PreparedPressureSource(grid: grid, cellIndices: [1], coefficients: [0.5]))
try forced.advance(source: source, amplitudes: [2, -1])
let forcedFields = try forced.snapshot()
try require(
  forcedFields.pressureOverDensity == [0.96923828125, 0.53076171875, 100, 100, 100, 100, 100, 100])
try require(forcedFields.velocityX == [0.12109375, 0, 0, 0, 0, 0, 0, 0])
try require(
  forcedFields.pressureStepIndex == 2 && forcedFields.pressureTime == 0.25
    && forcedFields.velocityTime == 0.1875)
let longGPU = try MetalWaveStepper(context: context, grid: grid, initialFields: fields)
let longPlan = try longGPU.prepareSource(source.source)
let chunkGPU = try MetalWaveStepper(context: context, grid: grid, initialFields: fields)
let amplitudes = (0..<257).map { Float($0 % 7 - 3) / 128 }
try longGPU.advance(source: longPlan, amplitudes: amplitudes)
try chunkGPU.advance(source: longPlan, amplitudes: Array(amplitudes.prefix(127)))
try chunkGPU.advance(source: longPlan, amplitudes: Array(amplitudes.dropFirst(127)))
let longFields = try longGPU.snapshot()
let chunkFields = try chunkGPU.snapshot()
try require(longFields.pressureStepIndex == 257 && chunkFields.pressureStepIndex == 257)
try require(
  [
    longFields.pressureOverDensity, longFields.velocityX, longFields.velocityY,
    longFields.velocityZ,
  ] == [
    chunkFields.pressureOverDensity, chunkFields.velocityX, chunkFields.velocityY,
    chunkFields.velocityZ,
  ])
print(
  "PASS fetched resident Metal forcing: packaged injection, signed source phases and three command batches",
  device.name)

let observation = try PreparedWaveObservation(
  grid: grid,
  receivers: [
    WaveReceiverStencil(
      pressureCells: Array(repeating: 1, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0])
  ])
let observer = try forced.prepareObservation(observation)
let observed = try forced.observe(observer)
try require(
  observed.pressureOverDensity == [0.53076171875] && observed.projectedVelocity == [nil]
    && observed.arithmetic == .metalFloat)
let history = try forced.advance(source: source, amplitudes: [0.25, -0.5], observing: observer)
var alignment = WaveObservationAligner()
let aligned = try alignment.append(history) + alignment.finishUsingFinalHalfStep()
try require(
  aligned.count == 2 && aligned[0].pressureStepIndex == 3 && aligned[1].usesTerminalHalfStep)
print(
  "PASS fetched resident Metal observation: pressure-only kernel, owned history and lookahead clocks",
  device.name)

// The compatible convenience API compiles its own context. Its complete forced fields
// remain identical to the explicitly reused context, without shared mutable run state.
let independent = try MetalWaveStepper(device: device, grid: grid, initialFields: fields)
let independentSource = try independent.prepareSource(source.source)
try independent.advance(source: independentSource, amplitudes: amplitudes)
let independentFields = try independent.snapshot()
try require(
  [
    independentFields.pressureOverDensity, independentFields.velocityX,
    independentFields.velocityY, independentFields.velocityZ,
  ] == [
    longFields.pressureOverDensity, longFields.velocityX, longFields.velocityY,
    longFields.velocityZ,
  ])
try require(independentFields.pressureStepIndex == 257 && forced.pressureStepIndex == 4)
print(
  "PASS fetched explicit reusable Metal context: independent fields, source/receiver storage and native clocks",
  context.deviceName)

// Exercise the released public product above the field-group threshold, including
// uneven dimensions, internal walls, forcing and multiple completed command batches.
do {
  let d = SIMD3<Int>(17, 9, 29)
  let n = d.x * d.y * d.z
  let mask = (0..<n).map { UInt8($0 % 37 == 0 ? 0 : 1) }
  let strides = [1, d.x, d.x * d.y]
  var faces = [Float](repeating: -1, count: 6 * n)
  for at in 0..<n where mask[at] == 1 {
    let xyz = [at % d.x, at / d.x % d.y, at / (d.x * d.y)]
    for side in 0..<6 {
      let axis = side / 2
      let plus = side % 2 == 1
      let within = plus ? xyz[axis] + 1 < d[axis] : xyz[axis] > 0
      let neighbour = at + (plus ? strides[axis] : -strides[axis])
      faces[side * n + at] = within && mask[neighbour] == 1 ? -1 : 0.001
    }
  }
  let grid = try PreparedWaveGrid(
    dimensions: d, spacing: [1, 0.8, 1.3], soundSpeed: 1.7, density: 1,
    timeStep: 0.03125, activeCells: mask, boundaryTerms: faces)
  let p = (0..<n).map { Float($0 % 17 - 8) / 512 }
  let zero = [Float](repeating: 0, count: n)
  let fields = WaveInitialFields(
    pressureOverDensity: p, velocityX: zero, velocityY: zero, velocityZ: zero)
  let source = try PreparedPressureSource(
    grid: grid, cellIndices: [1, 2], coefficients: [0.25, -0.125])
  let q = (0..<257).map { Float($0 % 7 - 3) / 128 }
  let gpu = try MetalWaveStepper(context: context, grid: grid, initialFields: fields)
  let cpu = try CPUWaveStepper(grid: grid, initialFields: fields)
  try gpu.advance(source: gpu.prepareSource(source), amplitudes: q)
  try cpu.advance(source: source, amplitudes: q)
  let a = try gpu.snapshot()
  let b = try cpu.snapshot()
  try require(a.pressureStepIndex == 257 && b.pressureStepIndex == 257)
  for (actual, expected) in zip(
    [a.pressureOverDensity, a.velocityX, a.velocityY, a.velocityZ],
    [b.pressureOverDensity, b.velocityX, b.velocityY, b.velocityZ])
  {
    try require(actual.count == n && zip(actual, expected).allSatisfy { abs($0 - $1) <= 2e-5 })
  }
  print(
    "PASS fetched large uneven masked Metal field groups: independent CPU fields, forcing and clocks",
    device.name)
  let mixedPlan = try PreparedWaveObservation(
    grid: grid,
    receivers: [
      WaveReceiverStencil(
        pressureCells: Array(repeating: 1, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0]),
      WaveReceiverStencil(
        pressureCells: Array(repeating: 2, count: 8), pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0],
        velocityCell: 171, velocityAxis: [1, 0, 0]),
    ])
  let directionalPlan = try PreparedWaveObservation(grid: grid, receivers: [mixedPlan.receivers[1]])
  let mixed = try gpu.observe(gpu.prepareObservation(mixedPlan))
  let directional = try gpu.observe(gpu.prepareObservation(directionalPlan))
  try require(
    mixed.pressureOverDensity == [
      Double(a.pressureOverDensity[1]), Double(a.pressureOverDensity[2]),
    ])
  try require(
    mixed.projectedVelocity[0] == nil
      && mixed.projectedVelocity[1] == directional.projectedVelocity[0])
  try require(mixed.pressureStepIndex == 257 && mixed.arithmetic == .metalFloat)
  print(
    "PASS fetched mixed pressure/directional sampling: ordered native pressure, absent probes and original velocity bits",
    device.name)

}
