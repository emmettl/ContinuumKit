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
let stepper = try MetalWaveStepper(device: device, grid: grid, initialFields: fields)
let saved = try stepper.snapshot()
try stepper.advance()
let first = try stepper.snapshot()
try require(first.pressureOverDensity == [0.984375, 0.015625, 100, 100, 100, 100, 100, 100])
try require(first.velocityX == [0.125, 0, 0, 0, 0, 0, 0, 0])
try require(first.pressureTime == 0.125 && first.velocityTime == 0.0625)
try stepper.advance(steps: 15)
try require(saved.pressureOverDensity[0] == 1 && saved.pressureStepIndex == 0)
let split = try MetalWaveStepper(device: device, grid: grid, initialFields: fields)
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
let gpu = try MetalWaveStepper(device: device, grid: grid, initialFields: fields)
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

let forced = try MetalWaveStepper(device: device, grid: grid, initialFields: fields)
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
let longGPU = try MetalWaveStepper(device: device, grid: grid, initialFields: fields)
let longPlan = try longGPU.prepareSource(source.source)
let chunkGPU = try MetalWaveStepper(device: device, grid: grid, initialFields: fields)
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
