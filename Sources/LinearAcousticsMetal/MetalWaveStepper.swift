// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
import Foundation
import LinearAcoustics
import Metal

public enum MetalWaveError: Error, Equatable, Sendable {
  case shaderResourceUnavailable, invalidGridABI
  case shaderCompilation(String)
  case pipelineCreation(String)
  case deviceResourceLimit(bytes: Int)
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
  private let device: any MTLDevice
  private let queue: any MTLCommandQueue
  private let velocity, pressure, injection: any MTLComputePipelineState
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
    try self.init(
      device: device, grid: grid, initialFields: initialFields,
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
  init(
    device: any MTLDevice, grid: PreparedWaveGrid, initialFields: WaveInitialFields,
    completion: @escaping (any MTLCommandBuffer) throws -> Void
  ) throws {
    try initialFields.validate(for: grid)
    guard MemoryLayout<Grid>.size == 36, MemoryLayout<Grid>.stride == 36,
      MemoryLayout<Grid>.alignment == 4
    else { throw MetalWaveError.invalidGridABI }
    guard let queue = device.makeCommandQueue() else { throw MetalWaveError.commandEncodingFailed }
    let library: any MTLLibrary
    do { library = try device.makeLibrary(source: Self.shaderSource(), options: nil) } catch let
      error as MetalWaveError
    { throw error } catch { throw MetalWaveError.shaderCompilation(error.localizedDescription) }
    func pipeline(_ name: String) throws -> any MTLComputePipelineState {
      guard let function = library.makeFunction(name: name) else {
        throw MetalWaveError.pipelineCreation(name)
      }
      do { return try device.makeComputePipelineState(function: function) } catch {
        throw MetalWaveError.pipelineCreation(name + ": " + error.localizedDescription)
      }
    }
    func buffer<T>(_ values: [T]) throws -> any MTLBuffer {
      try Self.makeBuffer(device: device, values: values)
    }
    self.device = device
    self.grid = grid
    deviceName = device.name
    self.queue = queue
    complete = completion
    velocity = try pipeline("waveVelocity")
    pressure = try pipeline("wavePressure")
    injection = try pipeline("waveInject")
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

  var fieldBufferIdentities: [ObjectIdentifier] { [p, ux, uy, uz].map(ObjectIdentifier.init) }

  public func advance(steps: Int = 1) throws {
    try advance(steps: steps, source: nil, amplitudes: [])
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
    try advance(steps: amplitudes.count, source: source, amplitudes: amplitudes)
  }

  private func advance(steps: Int, source: PreparedMetalPressureSource?, amplitudes: [Float]) throws
  {
    guard !invalidated else { throw WaveError.invalidatedState }
    guard steps >= 0 else { throw WaveError.invalidStepCount }
    let (finalIndex, overflow) = pressureStepIndex.addingReportingOverflow(steps)
    guard !overflow else { throw WaveError.stepIndexOverflow }
    guard (Double(finalIndex) * grid.timeStep).isFinite,
      ((Double(finalIndex) - 0.5) * grid.timeStep).isFinite
    else { throw WaveError.stepClockOverflow }
    let hasSource = source?.cells != nil
    if steps > 0, hasSource, amplitudeBuffer == nil {
      amplitudeBuffer = try Self.makeBuffer(
        device: device, values: [Float](repeating: 0, count: 128))
    }
    var remaining = steps
    let threads = MTLSize(
      width: grid.dimensions.x, height: grid.dimensions.y, depth: grid.dimensions.z)
    let width = min(
      32, min(velocity.maxTotalThreadsPerThreadgroup, pressure.maxTotalThreadsPerThreadgroup))
    let group = MTLSize(width: width, height: 1, depth: 1)
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
      }
      encoder.endEncoding()
      do { try complete(commands) } catch {
        invalidated = true
        throw error
      }
      pressureStepIndex += batch
      remaining -= batch
    }
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
