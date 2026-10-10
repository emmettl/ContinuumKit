import LinearAcoustics

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
let stepper = try CPUWaveStepper(grid: grid, initialFields: fields)
let saved = try stepper.snapshot()
try stepper.advance()
let first = try stepper.snapshot()
try require(first.pressureOverDensity == [0.984375, 0.015625, 100, 100, 100, 100, 100, 100])
try require(first.velocityX == [0.125, 0, 0, 0, 0, 0, 0, 0])
try require(first.pressureTime == 0.125 && first.velocityTime == 0.0625)
try stepper.advance(steps: 15)
try require(saved.pressureOverDensity[0] == 1 && saved.pressureStepIndex == 0)
let split = try CPUWaveStepper(grid: grid, initialFields: fields)
try split.advance(steps: 7)
try split.advance(steps: 9)
let a = try stepper.snapshot()
let b = try split.snapshot()
try require(a.pressureOverDensity == b.pressureOverDensity && a.velocityX == b.velocityX)
try require(a.velocityY == zero && a.velocityZ == zero && a.pressureStepIndex == 16)
print(
  "PASS LinearAcoustics fetched CPU-only product: all native fields, clocks, ownership and composition"
)

let forced = try CPUWaveStepper(grid: grid, initialFields: fields)
let source = try PreparedPressureSource(grid: grid, cellIndices: [1], coefficients: [0.5])
try forced.advance(source: source, amplitudes: [2, -1])
let forcedFields = try forced.snapshot()
try require(
  forcedFields.pressureOverDensity == [0.96923828125, 0.53076171875, 100, 100, 100, 100, 100, 100])
try require(forcedFields.velocityX == [0.12109375, 0, 0, 0, 0, 0, 0, 0])
try require(
  forcedFields.velocityY == zero && forcedFields.velocityZ == zero
    && forcedFields.pressureStepIndex == 2)
print("PASS fetched CPU pressure forcing: signed sparse increments, complete fields and clocks")
