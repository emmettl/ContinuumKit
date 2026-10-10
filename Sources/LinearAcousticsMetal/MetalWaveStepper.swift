// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
import Foundation
import LinearAcoustics
import Metal

public enum MetalWaveError: Error, Equatable, Sendable {
  case shaderResourceUnavailable, invalidGridABI
  case shaderCompilation(String)
  case pipelineCreation(String)
  case deviceResourceLimit(bytes: Int)
  case observationDeviceMismatch
  case unrepresentableObservationAxis(receiver: Int)
  case sourceDeviceMismatch
  case allocationFailed
  case commandEncodingFailed
  case commandFailed(String)
}

/// Synchronous, single-owner backend with resident tracked shared buffers.
/// The logical clock advances only after command completion. Output finiteness is
/// checked on explicit snapshot; completion alone does not guarantee finite fields.
public final class MetalWaveStepper {
  public let grid: PreparedWaveGrid
  public let deviceName: String
  public private(set) var pressureStepIndex = 0
  private let context: MetalWaveContext
  private let device: any MTLDevice
  private let queue: any MTLCommandQueue
  private let velocity, pressure, injection, sampling, pressureSampling: any MTLComputePipelineState
  private var observationStorage: MetalObservationStorage?
  private var amplitudeBuffer: (any MTLBuffer)?
  private let p, ux, uy, uz, inside, faces: any MTLBuffer
  private let complete: (any MTLCommandBuffer) throws -> Void
  private var invalidated = false

  // Scalar ABI matches the pinned Metal Grid: 36-byte size/stride, alignment four.
  struct Grid {
    var nx, ny, nz: UInt32
    var kx, ky, kz: Float
    var bx, by, bz: Float
    init(_ grid: PreparedWaveGrid) {
      nx = UInt32(grid.dimensions.x)
      ny = UInt32(grid.dimensions.y)
      nz = UInt32(grid.dimensions.z)
      kx = grid.velocityCoefficients.x
      ky = grid.velocityCoefficients.y
      kz = grid.velocityCoefficients.z
      bx = grid.pressureCoefficients.x
      by = grid.pressureCoefficients.y
      bz = grid.pressureCoefficients.z
    }
  }

  static func shaderSource() throws -> String {
    guard
      let url = Bundle.module.url(
        forResource: "WaveUpdate", withExtension: "metal", subdirectory: "Shaders"),
      let source = try? String(contentsOf: url, encoding: .utf8)
    else {
      throw MetalWaveError.shaderResourceUnavailable
    }
    return source
  }

  public convenience init(
    device: any MTLDevice, grid: PreparedWaveGrid, initialFields: WaveInitialFields
  ) throws {
    try initialFields.validate(for: grid)
    try self.init(
      context: MetalWaveContext(device: device), grid: grid, initialFields: initialFields)
  }

  /// Reuse immutable device pipelines; each stepper allocates its own queue and run storage.
  public convenience init(
    context: MetalWaveContext, grid: PreparedWaveGrid, initialFields: WaveInitialFields
  ) throws {
    try self.init(
      context: context, grid: grid, initialFields: initialFields,
      completion: { commands in
        commands.commit()
        commands.waitUntilCompleted()
        guard commands.status == .completed else {
          throw MetalWaveError.commandFailed(
            commands.error?.localizedDescription ?? "GPU command did not complete")
        }
      })
  }

  // Internal submission seam permits deterministic failure-path tests without provoking GPU faults.
  convenience init(
    device: any MTLDevice, grid: PreparedWaveGrid, initialFields: WaveInitialFields,
    completion: @escaping (any MTLCommandBuffer) throws -> Void
  ) throws {
    try initialFields.validate(for: grid)
    try self.init(
      context: MetalWaveContext(device: device), grid: grid, initialFields: initialFields,
      completion: completion)
  }

  init(
    context: MetalWaveContext, grid: PreparedWaveGrid, initialFields: WaveInitialFields,
    completion: @escaping (any MTLCommandBuffer) throws -> Void
  ) throws {
    let device = context.device
    try initialFields.validate(for: grid)
    guard MemoryLayout<Grid>.size == 36, MemoryLayout<Grid>.stride == 36,
      MemoryLayout<Grid>.alignment == 4
    else { throw MetalWaveError.invalidGridABI }
    guard let queue = device.makeCommandQueue() else { throw MetalWaveError.commandEncodingFailed }
    func buffer<T>(_ values: [T]) throws -> any MTLBuffer {
      try Self.makeBuffer(device: device, values: values)
    }
    self.context = context
    self.device = device
    self.grid = grid
    deviceName = device.name
    self.queue = queue
    complete = completion
    velocity = context.velocity
    pressure = context.pressure
    injection = context.injection
    sampling = context.sampling
    pressureSampling = context.pressureSampling
    p = try buffer(initialFields.pressureOverDensity)
    ux = try buffer(initialFields.velocityX)
    uy = try buffer(initialFields.velocityY)
    uz = try buffer(initialFields.velocityZ)
    inside = try buffer(grid.activeCells)
    faces = try buffer(grid.boundaryTerms)
  }

  static func makeBuffer<T>(device: any MTLDevice, values: [T]) throws -> any MTLBuffer {
    let (bytes, overflow) = values.count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
    guard !overflow, bytes <= device.maxBufferLength else {
      throw MetalWaveError.deviceResourceLimit(bytes: overflow ? Int.max : bytes)
    }
    return try values.withUnsafeBytes { raw in
      guard let base = raw.baseAddress,
        let buffer = device.makeBuffer(
          bytes: base, length: bytes,
          options: [.storageModeShared, .hazardTrackingModeTracked])
      else { throw MetalWaveError.allocationFailed }
      return buffer
    }
  }

  /// Upload immutable source indices/coefficients once; fields remain owned by the stepper.
  public func prepareSource(_ source: PreparedPressureSource) throws -> PreparedMetalPressureSource
  {
    guard !invalidated else { throw WaveError.invalidatedState }
    try source.validate(for: grid)
    return try PreparedMetalPressureSource(device: device, source: source)
  }

  var sourceStagingBufferIdentity: ObjectIdentifier? { amplitudeBuffer.map(ObjectIdentifier.init) }

  var pipelineIdentities: [ObjectIdentifier] { context.pipelineIdentities }

  var queueIdentity: ObjectIdentifier { ObjectIdentifier(queue) }

  var fieldBufferIdentities: [ObjectIdentifier] { [p, ux, uy, uz].map(ObjectIdentifier.init) }

  // Small grids retain the original narrow shape. Larger grids use more rows/planes
  // per group without exceeding either field pipeline or any physical device axis.
  static func fieldThreadgroup(
    cellCount: Int, pipelineLimit: Int, deviceLimit: MTLSize
  ) throws -> MTLSize {
    guard cellCount > 0, pipelineLimit > 0,
      deviceLimit.width > 0, deviceLimit.height > 0, deviceLimit.depth > 0
    else { throw MetalWaveError.commandEncodingFailed }
    let width = min(32, min(pipelineLimit, deviceLimit.width))
    let height = cellCount < 4_096 ? 1 : min(4, min(pipelineLimit / width, deviceLimit.height))
    let depth =
      cellCount < 4_096 ? 1 : min(2, min(pipelineLimit / (width * height), deviceLimit.depth))
    return MTLSize(width: width, height: height, depth: depth)
  }

  public func advance(steps: Int = 1) throws {
    _ = try advance(steps: steps, source: nil, amplitudes: [], observing: nil)
  }

  /// One finite, caller-evaluated midpoint amplitude per complete step. Stages at most
  /// 128 values and waits before reusing that storage; no host field readback occurs.
  public func advance(source: PreparedMetalPressureSource, amplitudes: [Float]) throws {
    guard !invalidated else { throw WaveError.invalidatedState }
    try source.source.validate(for: grid)
    guard source.deviceRegistryID == device.registryID else {
      throw MetalWaveError.sourceDeviceMismatch
    }
    for (step, value) in amplitudes.enumerated() where !value.isFinite {
      throw PressureSourceError.nonfiniteAmplitude(step: step)
    }
    _ = try advance(steps: amplitudes.count, source: source, amplitudes: amplitudes, observing: nil)
  }

  public func prepareObservation(_ observation: PreparedWaveObservation) throws
    -> PreparedMetalWaveObservation
  {
    guard !invalidated else { throw WaveError.invalidatedState }
    try observation.validate(for: grid)
    return try PreparedMetalWaveObservation(device: device, observation: observation)
  }

  private func storage(for observation: PreparedMetalWaveObservation) throws
    -> MetalObservationStorage
  {
    try observation.observation.validate(for: grid)
    guard observation.deviceRegistryID == device.registryID else {
      throw MetalWaveError.observationDeviceMismatch
    }
    if let old = observationStorage, old.owner === observation { return old }
    let next = try MetalObservationStorage(device: device, owner: observation)
    observationStorage = next
    return next
  }

  var observationBufferIdentities: [ObjectIdentifier] { observationStorage?.bufferIdentities ?? [] }

  /// Sparse readout only; finite observed channels do not certify unsampled field slots.
  public func observe(_ observation: PreparedMetalWaveObservation) throws -> WaveObservationFrame {
    guard !invalidated else { throw WaveError.invalidatedState }
    let output = try storage(for: observation)
    if observation.observation.receivers.isEmpty {
      return WaveObservationFrame(
        pressureStepIndex: pressureStepIndex, timeStep: grid.timeStep,
        pressureOverDensity: [], projectedVelocity: [], observation: observation.observation,
        arithmetic: .metalFloat)
    }
    guard let commands = queue.makeCommandBuffer(),
      let encoder = commands.makeComputeCommandEncoder(dispatchType: .serial)
    else {
      invalidated = true
      throw MetalWaveError.commandEncodingFailed
    }
    encodeObservation(encoder, output: output, step: 0, steps: 1)
    encoder.endEncoding()
    do { try complete(commands) } catch {
      invalidated = true
      throw error
    }
    return try decodeObservation(output, steps: 1, firstIndex: pressureStepIndex)[0]
  }

  public func advance(steps: Int, observing observation: PreparedMetalWaveObservation) throws
    -> [WaveObservationFrame]
  {
    try advance(steps: steps, source: nil, amplitudes: [], observing: observation)
  }

  public func advance(
    source: PreparedMetalPressureSource, amplitudes: [Float],
    observing observation: PreparedMetalWaveObservation
  ) throws -> [WaveObservationFrame] {
    guard !invalidated else { throw WaveError.invalidatedState }
    try source.source.validate(for: grid)
    guard source.deviceRegistryID == device.registryID else {
      throw MetalWaveError.sourceDeviceMismatch
    }
    for (step, value) in amplitudes.enumerated() where !value.isFinite {
      throw PressureSourceError.nonfiniteAmplitude(step: step)
    }
    return try advance(
      steps: amplitudes.count, source: source, amplitudes: amplitudes, observing: observation)
  }

  private func encodeObservation(
    _ encoder: any MTLComputeCommandEncoder, output: MetalObservationStorage, step: Int, steps: Int
  ) {
    let plan = output.owner
    var localStep = UInt32(step)
    var totalSteps = UInt32(steps)
    var abi = Grid(grid)
    func encode(_ group: MetalObservationGroup, _ pressureOutput: any MTLBuffer, _ full: Bool) {
      var count = UInt32(group.indices.count)
      encoder.setComputePipelineState(full ? sampling : pressureSampling)
      encoder.setBuffer(p, offset: 0, index: 0)
      encoder.setBuffer(group.cells, offset: 0, index: 4)
      encoder.setBuffer(group.weights, offset: 0, index: 5)
      encoder.setBuffer(pressureOutput, offset: 0, index: 8)
      encoder.setBytes(&localStep, length: 4, index: 11)
      encoder.setBytes(&totalSteps, length: 4, index: 12)
      encoder.setBytes(&count, length: 4, index: 13)
      if full {
        encoder.setBuffer(ux, offset: 0, index: 1)
        encoder.setBuffer(uy, offset: 0, index: 2)
        encoder.setBuffer(uz, offset: 0, index: 3)
        encoder.setBuffer(group.velocityCells, offset: 0, index: 6)
        encoder.setBuffer(group.axes, offset: 0, index: 7)
        encoder.setBuffer(output.fullVelocity, offset: 0, index: 9)
        encoder.setBytes(&abi, length: MemoryLayout<Grid>.stride, index: 10)
      }
      let pipeline = full ? sampling : pressureSampling
      encoder.dispatchThreads(
        MTLSize(width: Int(count), height: 1, depth: 1),
        threadsPerThreadgroup: MTLSize(
          width: min(8, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
      encoder.memoryBarrier(scope: .buffers)
    }
    if let group = plan.full, let buffer = output.fullPressure { encode(group, buffer, true) }
    if let group = plan.pressureOnly, let buffer = output.onlyPressure {
      encode(group, buffer, false)
    }
  }

  private func decodeObservation(_ output: MetalObservationStorage, steps: Int, firstIndex: Int)
    throws -> [WaveObservationFrame]
  {
    var frames: [WaveObservationFrame] = []
    let plan = output.owner
    for step in 0..<steps {
      var pressure = [Double](repeating: 0, count: plan.observation.receivers.count)
      var velocity = [Double?](repeating: nil, count: pressure.count)
      if let group = plan.full, let pBuffer = output.fullPressure, let vBuffer = output.fullVelocity
      {
        let p = pBuffer.contents().assumingMemoryBound(to: Float.self)
        let v = vBuffer.contents().assumingMemoryBound(to: Float.self)
        for (r, index) in group.indices.enumerated() {
          pressure[index] = Double(p[r * steps + step])
          velocity[index] = Double(v[r * (steps + 1) + step + 1])
        }
      }
      if let group = plan.pressureOnly, let pBuffer = output.onlyPressure {
        let p = pBuffer.contents().assumingMemoryBound(to: Float.self)
        for (r, index) in group.indices.enumerated() {
          pressure[index] = Double(p[r * steps + step])
        }
      }
      for index in pressure.indices {
        guard pressure[index].isFinite, velocity[index]?.isFinite ?? true else {
          throw WaveObservationError.nonfiniteResult(receiver: index)
        }
      }
      frames.append(
        WaveObservationFrame(
          pressureStepIndex: firstIndex + step, timeStep: grid.timeStep,
          pressureOverDensity: pressure, projectedVelocity: velocity, observation: plan.observation,
          arithmetic: .metalFloat))
    }
    return frames
  }

  private func advance(
    steps: Int, source: PreparedMetalPressureSource?, amplitudes: [Float],
    observing observation: PreparedMetalWaveObservation?
  ) throws -> [WaveObservationFrame] {

    guard !invalidated else { throw WaveError.invalidatedState }
    guard steps >= 0 else { throw WaveError.invalidStepCount }
    let (finalIndex, overflow) = pressureStepIndex.addingReportingOverflow(steps)
    guard !overflow else { throw WaveError.stepIndexOverflow }
    guard (Double(finalIndex) * grid.timeStep).isFinite,
      ((Double(finalIndex) - 0.5) * grid.timeStep).isFinite
    else { throw WaveError.stepClockOverflow }
    var output: MetalObservationStorage?
    if let observation {
      guard steps <= PreparedWaveObservation.maximumBatchSteps else {
        throw WaveObservationError.batchTooLarge
      }
      // All output allocation precedes numerical field work.
      try observation.observation.validate(for: grid)
      guard observation.deviceRegistryID == device.registryID else {
        throw MetalWaveError.observationDeviceMismatch
      }
      if steps > 0 { output = try storage(for: observation) }
    }
    let firstIndex = steps > 0 ? pressureStepIndex + 1 : pressureStepIndex
    let hasSource = source?.cells != nil
    if steps > 0, hasSource, amplitudeBuffer == nil {
      amplitudeBuffer = try Self.makeBuffer(
        device: device, values: [Float](repeating: 0, count: 128))
    }
    var remaining = steps
    let threads = MTLSize(
      width: grid.dimensions.x, height: grid.dimensions.y, depth: grid.dimensions.z)
    let group = try Self.fieldThreadgroup(
      cellCount: grid.cellCount,
      pipelineLimit: min(
        velocity.maxTotalThreadsPerThreadgroup, pressure.maxTotalThreadsPerThreadgroup),
      deviceLimit: device.maxThreadsPerThreadgroup)
    var abi = Grid(grid)
    while remaining > 0 {
      let batch = min(remaining, 128)
      guard let commands = queue.makeCommandBuffer(),
        let encoder = commands.makeComputeCommandEncoder(dispatchType: .serial)
      else {
        invalidated = true
        throw MetalWaveError.commandEncodingFailed
      }
      if hasSource, let amplitudeBuffer {
        amplitudes.withUnsafeBufferPointer { values in
          amplitudeBuffer.contents().assumingMemoryBound(to: Float.self)
            .update(from: values.baseAddress!.advanced(by: steps - remaining), count: batch)
        }
      }
      for step in 0..<batch {
        encoder.setComputePipelineState(velocity)
        // Injection uses these slots differently; restore every velocity binding each step.
        encoder.setBuffer(p, offset: 0, index: 0)
        encoder.setBuffer(ux, offset: 0, index: 1)
        encoder.setBuffer(uy, offset: 0, index: 2)
        encoder.setBuffer(uz, offset: 0, index: 3)
        encoder.setBuffer(inside, offset: 0, index: 4)
        encoder.setBytes(&abi, length: MemoryLayout<Grid>.stride, index: 5)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.memoryBarrier(scope: .buffers)
        encoder.setComputePipelineState(pressure)
        encoder.setBuffer(faces, offset: 0, index: 5)
        encoder.setBytes(&abi, length: MemoryLayout<Grid>.stride, index: 6)
        encoder.dispatchThreads(threads, threadsPerThreadgroup: group)
        encoder.memoryBarrier(scope: .buffers)
        if let source, let cells = source.cells, let weights = source.weights, let amplitudeBuffer {
          var localStep = UInt32(step)
          var count = UInt32(source.source.cellIndices.count)
          encoder.setComputePipelineState(injection)
          encoder.setBuffer(p, offset: 0, index: 0)
          encoder.setBuffer(amplitudeBuffer, offset: 0, index: 1)
          encoder.setBuffer(cells, offset: 0, index: 2)
          encoder.setBuffer(weights, offset: 0, index: 3)
          encoder.setBytes(&localStep, length: 4, index: 4)
          encoder.setBytes(&count, length: 4, index: 5)
          encoder.dispatchThreads(
            MTLSize(width: Int(count), height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(
              width: min(8, injection.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
          encoder.memoryBarrier(scope: .buffers)
        }
        if let output { encodeObservation(encoder, output: output, step: step, steps: batch) }
      }
      encoder.endEncoding()
      do { try complete(commands) } catch {
        invalidated = true
        throw error
      }
      pressureStepIndex += batch
      remaining -= batch
    }
    if let output, steps > 0 {
      return try decodeObservation(output, steps: steps, firstIndex: firstIndex)
    }
    return []
  }

  /// Copies resident fields only when requested. Nonfinite output invalidates this backend;
  /// rebuild from a caller checkpoint. GPU clocks count completed commands, not finite-output certification.
  public func snapshot() throws -> WaveSnapshot {
    guard !invalidated else { throw WaveError.invalidatedState }
    func copy(_ buffer: any MTLBuffer) -> [Float] {
      Array(
        UnsafeBufferPointer(
          start: buffer.contents().assumingMemoryBound(to: Float.self), count: grid.cellCount))
    }
    let fields = WaveInitialFields(
      pressureOverDensity: copy(p), velocityX: copy(ux), velocityY: copy(uy), velocityZ: copy(uz))
    do { try fields.validate(for: grid) } catch {
      invalidated = true
      throw WaveError.nonfiniteOutput
    }
    return WaveSnapshot(
      pressureStepIndex: pressureStepIndex, timeStep: grid.timeStep,
      pressureOverDensity: fields.pressureOverDensity, velocityX: fields.velocityX,
      velocityY: fields.velocityY, velocityZ: fields.velocityZ)
  }
}

/// Immutable device-resident sparse source mapping, prepared by its grid's stepper.
/// Buffers are opaque, copied once and retained through synchronous command completion.
public final class PreparedMetalPressureSource {
  public let source: PreparedPressureSource
  public let deviceName: String
  let deviceRegistryID: UInt64
  let cells, weights: (any MTLBuffer)?
  var bufferIdentities: [ObjectIdentifier] {
    [cells, weights].compactMap { $0.map(ObjectIdentifier.init) }
  }

  init(device: any MTLDevice, source: PreparedPressureSource) throws {
    self.source = source
    deviceName = device.name
    deviceRegistryID = device.registryID
    if source.cellIndices.isEmpty {
      cells = nil
      weights = nil
    } else {
      cells = try MetalWaveStepper.makeBuffer(
        device: device, values: source.cellIndices.map(UInt32.init))
      weights = try MetalWaveStepper.makeBuffer(device: device, values: source.coefficients)
    }
  }
}
