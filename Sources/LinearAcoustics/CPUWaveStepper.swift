// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
// Masked update ported from the pinned RoomCAD blocks; see docs/extraction/LINEAR_WAVE_CPU.md.
import Dispatch

public struct WaveInitialFields: Sendable {
  public let pressureOverDensity, velocityX, velocityY, velocityZ: [Float]
  public init(
    pressureOverDensity: [Float], velocityX: [Float], velocityY: [Float], velocityZ: [Float]
  ) {
    self.pressureOverDensity = pressureOverDensity
    self.velocityX = velocityX
    self.velocityY = velocityY
    self.velocityZ = velocityZ
  }

  /// Validate finite native fields and zero closed/unused velocities before backend allocation.
  public func validate(for grid: PreparedWaveGrid) throws {
    let fields = [pressureOverDensity, velocityX, velocityY, velocityZ]
    for (field, values) in fields.enumerated() {
      try PreparedWaveGrid.requireCount(values.count, grid.cellCount, "field\(field)")
      guard values.allSatisfy(\.isFinite) else { throw WaveError.invalidInitialFields }
      if field > 0 {
        // Positive face is open exactly when its prepared coefficient is -1 on an active cell.
        for at in values.indices
        where grid.activeCells[at] == 0
          || grid.boundaryTerms[(2 * field - 1) * grid.cellCount + at] != -1
        {
          guard values[at] == 0 else { throw WaveError.closedFaceVelocity(field: field, cell: at) }
        }
      }
    }
  }
}

/// All fields have the native N-slot layout. Relative clocks preserve staggering.
public struct WaveSnapshot: Sendable {
  public let pressureStepIndex: Int
  public let timeStep: Double
  public let pressureOverDensity, velocityX, velocityY, velocityZ: [Float]
  /// Value constructor for backend results. Steppers validate fields and clocks before returning them.
  public init(
    pressureStepIndex: Int, timeStep: Double, pressureOverDensity: [Float],
    velocityX: [Float], velocityY: [Float], velocityZ: [Float]
  ) {
    self.pressureStepIndex = pressureStepIndex
    self.timeStep = timeStep
    self.pressureOverDensity = pressureOverDensity
    self.velocityX = velocityX
    self.velocityY = velocityY
    self.velocityZ = velocityZ
  }
  public var pressureTime: Double { Double(pressureStepIndex) * timeStep }
  public var velocityTime: Double { (Double(pressureStepIndex) - 0.5) * timeStep }
}

/// Explicit traversal policy. Parallel slabs partition z planes and complete synchronously.
/// The caller chooses the count; the model does not infer hardware or application scheduling.
public enum CPUWaveExecution: Equatable, Sendable {
  case serial
  case parallel(slabs: Int)
}

/// Private synchronous phase borrow. Only disjoint cell/flag addresses are written by workers;
/// Dispatch completes every worker before pressure, source, observation or teardown proceeds.
private struct CPUPhaseStorage: @unchecked Sendable {
  let p, ux, uy, uz: UnsafeMutablePointer<Float>
  let finite: UnsafeMutablePointer<UInt8>
}

/// Synchronous single-owner stepper; not concurrently callable or Sendable.
/// Input arrays are copied once into four independent resident CPU buffers.
/// Snapshot copies explicitly; advance allocates no field buffers.
public final class CPUWaveStepper {
  public let grid: PreparedWaveGrid
  public let execution: CPUWaveExecution
  public let slabCount: Int
  public private(set) var pressureStepIndex = 0
  private let p, ux, uy, uz: UnsafeMutablePointer<Float>
  private let finite: UnsafeMutablePointer<UInt8>
  private var invalidated = false

  public init(
    grid: PreparedWaveGrid, initialFields: WaveInitialFields,
    execution: CPUWaveExecution = .serial
  ) throws {
    let slabs: Int
    switch execution {
    case .serial: slabs = 1
    case .parallel(let count):
      guard count >= 1, count <= grid.dimensions.z else { throw WaveError.invalidSlabCount }
      slabs = count
    }
    let fields = [
      initialFields.pressureOverDensity, initialFields.velocityX, initialFields.velocityY,
      initialFields.velocityZ,
    ]
    try initialFields.validate(for: grid)
    func copy(_ values: [Float]) -> UnsafeMutablePointer<Float> {
      let buffer = UnsafeMutablePointer<Float>.allocate(capacity: values.count)
      values.withUnsafeBufferPointer {
        buffer.initialize(from: $0.baseAddress!, count: values.count)
      }
      return buffer
    }
    self.grid = grid
    self.execution = execution
    slabCount = slabs
    finite = UnsafeMutablePointer<UInt8>.allocate(capacity: 2 * slabs)
    finite.initialize(repeating: 1, count: 2 * slabs)
    p = copy(fields[0])
    ux = copy(fields[1])
    uy = copy(fields[2])
    uz = copy(fields[3])
  }

  deinit {
    finite.deinitialize(count: 2 * slabCount)
    finite.deallocate()
    for field in [p, ux, uy, uz] {
      field.deinitialize(count: grid.cellCount)
      field.deallocate()
    }
  }

  public func advance(steps: Int = 1) throws {
    _ = try advance(steps: steps, source: nil, amplitudes: [], observing: nil)
  }

  /// One already evaluated midpoint amplitude per complete update. The entire batch
  /// is checked before mutation; each acknowledged step includes source injection.
  public func advance(source: PreparedPressureSource, amplitudes: [Float]) throws {
    guard !invalidated else { throw WaveError.invalidatedState }
    try source.validate(for: grid)
    for (step, value) in amplitudes.enumerated() where !value.isFinite {
      throw PressureSourceError.nonfiniteAmplitude(step: step)
    }
    _ = try advance(steps: amplitudes.count, source: source, amplitudes: amplitudes, observing: nil)
  }

  /// Read only the prepared receiver slots directly from resident fields; no full-field copy.
  public func observe(_ observation: PreparedWaveObservation) throws -> WaveObservationFrame {
    guard !invalidated else { throw WaveError.invalidatedState }
    try observation.validate(for: grid)
    var pressure: [Double] = []
    var velocity: [Double?] = []
    for (receiver, stencil) in observation.receivers.enumerated() {
      var value = 0.0
      for entry in 0..<8 {
        value += Double(p[stencil.pressureCells[entry]]) * Double(stencil.pressureWeights[entry])
      }
      guard value.isFinite else { throw WaveObservationError.nonfiniteResult(receiver: receiver) }
      pressure.append(value)
      if let at = stencil.velocityCell, let axis = stencil.velocityAxis {
        // Preserve original Float face-pair addition before Double conversion/averaging.
        let u = SIMD3<Double>(
          Double(ux[at - 1] + ux[at]) / 2,
          Double(uy[at - grid.dimensions.x] + uy[at]) / 2,
          Double(uz[at - grid.dimensions.x * grid.dimensions.y] + uz[at]) / 2)
        let projected = (u * axis).sum()
        guard projected.isFinite else {
          throw WaveObservationError.nonfiniteResult(receiver: receiver)
        }
        velocity.append(projected)
      } else {
        velocity.append(nil)
      }
    }
    return WaveObservationFrame(
      pressureStepIndex: pressureStepIndex, timeStep: grid.timeStep,
      pressureOverDensity: pressure, projectedVelocity: velocity, observation: observation,
      arithmetic: .cpuDouble)
  }

  public func advance(steps: Int, observing observation: PreparedWaveObservation) throws
    -> [WaveObservationFrame]
  {
    try advance(steps: steps, source: nil, amplitudes: [], observing: observation)
  }

  public func advance(
    source: PreparedPressureSource, amplitudes: [Float],
    observing observation: PreparedWaveObservation
  ) throws -> [WaveObservationFrame] {
    guard !invalidated else { throw WaveError.invalidatedState }
    try source.validate(for: grid)
    for (step, value) in amplitudes.enumerated() where !value.isFinite {
      throw PressureSourceError.nonfiniteAmplitude(step: step)
    }
    return try advance(
      steps: amplitudes.count, source: source, amplitudes: amplitudes, observing: observation)
  }

  private func advance(
    steps: Int, source: PreparedPressureSource?, amplitudes: [Float],
    observing observation: PreparedWaveObservation?
  ) throws -> [WaveObservationFrame] {

    guard !invalidated else { throw WaveError.invalidatedState }
    guard steps >= 0 else { throw WaveError.invalidStepCount }
    if let observation {
      try observation.validate(for: grid)
      guard steps <= PreparedWaveObservation.maximumBatchSteps else {
        throw WaveObservationError.batchTooLarge
      }
    }
    var observed: [WaveObservationFrame] = []
    let (finalIndex, overflow) = pressureStepIndex.addingReportingOverflow(steps)
    guard !overflow else { throw WaveError.stepIndexOverflow }
    guard (Double(finalIndex) * grid.timeStep).isFinite,
      ((Double(finalIndex) - 0.5) * grid.timeStep).isFinite
    else { throw WaveError.stepClockOverflow }
    let nx = grid.dimensions.x
    let ny = grid.dimensions.y
    let nz = grid.dimensions.z
    let count = grid.cellCount
    let plane = nx * ny
    let inside = grid.activeCells
    let faces = grid.boundaryTerms
    let kx = grid.velocityCoefficients.x
    let ky = grid.velocityCoefficients.y
    let kz = grid.velocityCoefficients.z
    let bx = grid.pressureCoefficients.x
    let by = grid.pressureCoefficients.y
    let bz = grid.pressureCoefficients.z
    let storage = CPUPhaseStorage(p: p, ux: ux, uy: uy, uz: uz, finite: finite)
    let slabs = slabCount
    func eachSlab(_ body: @Sendable (Int) -> Void) {
      if slabs == 1 {
        body(0)
      } else {
        DispatchQueue.concurrentPerform(iterations: slabs, execute: body)
      }
    }
    for step in 0..<steps {
      // Source cpu-masked-velocity: same cell statements, disjoint plane slabs.
      eachSlab { slab in
        let (p, ux, uy, uz) = (storage.p, storage.ux, storage.uy, storage.uz)
        var valid = true
        for k in (slab * nz / slabs)..<((slab + 1) * nz / slabs) {
          for j in 0..<ny {
            let row = nx * (j + ny * k)
            for i in 0..<nx where inside[row + i] == 1 {
              let at = row + i
              if i < nx - 1, inside[at + 1] == 1 { ux[at] -= kx * (p[at + 1] - p[at]) }
              if j < ny - 1, inside[at + nx] == 1 { uy[at] -= ky * (p[at + nx] - p[at]) }
              if k < nz - 1, inside[at + plane] == 1 { uz[at] -= kz * (p[at + plane] - p[at]) }
              if !ux[at].isFinite || !uy[at].isFinite || !uz[at].isFinite { valid = false }
            }
          }
        }
        storage.finite[slab] = valid ? 1 : 0
      }
      // Dispatch completion separates all velocity writes from pressure reads.
      // Source cpu-masked-pressure: six face blocks, unchanged Float accumulation order.
      eachSlab { slab in
        let (p, ux, uy, uz) = (storage.p, storage.ux, storage.uy, storage.uz)
        var valid = true
        for k in (slab * nz / slabs)..<((slab + 1) * nz / slabs) {
          for j in 0..<ny {
            let row = nx * (j + ny * k)
            for i in 0..<nx where inside[row + i] == 1 {
              let at = row + i
              var divergence: Float = 0
              var wall: Float = 0
              let west = faces[at]
              let east = faces[count + at]
              let south = faces[2 * count + at]
              let north = faces[3 * count + at]
              let floor = faces[4 * count + at]
              let ceiling = faces[5 * count + at]
              if west < 0 { divergence -= bx * ux[at - 1] } else { wall += west }
              if east < 0 { divergence += bx * ux[at] } else { wall += east }
              if south < 0 { divergence -= by * uy[at - nx] } else { wall += south }
              if north < 0 { divergence += by * uy[at] } else { wall += north }
              if floor < 0 { divergence -= bz * uz[at - plane] } else { wall += floor }
              if ceiling < 0 { divergence += bz * uz[at] } else { wall += ceiling }
              p[at] = ((1 - wall) * p[at] - divergence) / (1 + wall)
              if !p[at].isFinite { valid = false }
            }
          }
        }
        storage.finite[slabs + slab] = valid ? 1 : 0
      }
      var sourceFinite = true
      if let source {
        // Pinned RoomCAD injection order; source writes remain serial after pressure completion.
        for entry in source.cellIndices.indices {
          let at = source.cellIndices[entry]
          p[at] += amplitudes[step] * source.coefficients[entry]
          if !p[at].isFinite { sourceFinite = false }
        }
      }
      // Inductive field certificate: init validates every slot; phases check every active
      // field and source write. Inactive pressure and closed/unused velocities never change.
      // Nonfinite pressure cannot be repaired by adding a product of finite source inputs.
      // This retains complete-field rejection without a third full-field memory traversal.
      if !sourceFinite || (0..<(2 * slabs)).contains(where: { finite[$0] == 0 }) {
        invalidated = true
        throw WaveError.nonfiniteOutput
      }
      pressureStepIndex += 1
      if let observation { observed.append(try observe(observation)) }
    }
    return observed
  }

  public func snapshot() throws -> WaveSnapshot {
    guard !invalidated else { throw WaveError.invalidatedState }
    func copy(_ field: UnsafeMutablePointer<Float>) -> [Float] {
      Array(UnsafeBufferPointer(start: field, count: grid.cellCount))
    }
    return WaveSnapshot(
      pressureStepIndex: pressureStepIndex, timeStep: grid.timeStep,
      pressureOverDensity: copy(p), velocityX: copy(ux), velocityY: copy(uy), velocityZ: copy(uz))
  }
}
