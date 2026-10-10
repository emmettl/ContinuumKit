// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
import LinearAcoustics
import Metal

/// Opaque immutable mapping. Pressure-only receivers need no invented velocity address.
/// Reused output storage belongs to each stepper, and returned frames are owned copies.
public final class PreparedMetalWaveObservation {
  public let observation: PreparedWaveObservation
  public let deviceName: String
  let deviceRegistryID: UInt64
  let full, pressureOnly, mixed: MetalObservationGroup?
  var bufferIdentities: [ObjectIdentifier] {
    (full?.bufferIdentities ?? []) + (pressureOnly?.bufferIdentities ?? [])
      + (mixed?.bufferIdentities ?? [])
  }
  init(device: any MTLDevice, observation: PreparedWaveObservation) throws {
    self.observation = observation
    deviceName = device.name
    deviceRegistryID = device.registryID
    guard observation.receivers.count <= Int(UInt32.max) / 129 else {
      throw WaveObservationError.batchTooLarge
    }
    let fullIndices = observation.receivers.indices.filter {
      observation.receivers[$0].velocityCell != nil
    }
    let onlyIndices = observation.receivers.indices.filter {
      observation.receivers[$0].velocityCell == nil
    }
    // Validate every converted axis before uploading any resources.
    for index in fullIndices {
      let axis = observation.receivers[index].velocityAxis!
      guard (0..<3).allSatisfy({ Float(axis[$0]).isFinite }) else {
        throw MetalWaveError.unrepresentableObservationAxis(receiver: index)
      }
    }
    if !fullIndices.isEmpty && !onlyIndices.isEmpty {
      // A reserved absent-probe marker is checked before any velocity address/read.
      mixed = try MetalObservationGroup(
        device: device, observation: observation,
        indices: Array(observation.receivers.indices), velocity: true)
      full = nil
      pressureOnly = nil
    } else {
      mixed = nil
      full =
        fullIndices.isEmpty
        ? nil
        : try MetalObservationGroup(
          device: device, observation: observation, indices: fullIndices, velocity: true)
      pressureOnly =
        onlyIndices.isEmpty
        ? nil
        : try MetalObservationGroup(
          device: device, observation: observation, indices: onlyIndices, velocity: false)
    }
  }
}

final class MetalObservationGroup {
  let indices: [Int]
  let cells, weights: any MTLBuffer
  let velocityCells, axes: (any MTLBuffer)?
  var bufferIdentities: [ObjectIdentifier] {
    [ObjectIdentifier(cells), ObjectIdentifier(weights)]
      + [velocityCells, axes].compactMap { $0.map(ObjectIdentifier.init) }
  }
  init(device: any MTLDevice, observation: PreparedWaveObservation, indices: [Int], velocity: Bool)
    throws
  {
    self.indices = indices
    cells = try MetalWaveStepper.makeBuffer(
      device: device,
      values: indices.flatMap { observation.receivers[$0].pressureCells.map(UInt32.init) })
    weights = try MetalWaveStepper.makeBuffer(
      device: device, values: indices.flatMap { observation.receivers[$0].pressureWeights })
    if velocity {
      velocityCells = try MetalWaveStepper.makeBuffer(
        device: device,
        values: indices.map {
          observation.receivers[$0].velocityCell.map(UInt32.init) ?? UInt32.max
        })
      axes = try MetalWaveStepper.makeBuffer(
        device: device,
        values: indices.flatMap { index -> [Float] in
          let a = observation.receivers[index].velocityAxis ?? .zero
          return [Float(a.x), Float(a.y), Float(a.z)]
        })
    } else {
      velocityCells = nil
      axes = nil
    }
  }
}

final class MetalObservationStorage {
  let owner: PreparedMetalWaveObservation
  let fullPressure, fullVelocity, onlyPressure, mixedPressure, mixedVelocity: (any MTLBuffer)?
  var bufferIdentities: [ObjectIdentifier] {
    [fullPressure, fullVelocity, onlyPressure, mixedPressure, mixedVelocity].compactMap {
      $0.map(ObjectIdentifier.init)
    }
  }
  init(device: any MTLDevice, owner: PreparedMetalWaveObservation) throws {
    self.owner = owner
    func buffer(_ count: Int) throws -> any MTLBuffer {
      let (bytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
      guard !overflow, bytes <= device.maxBufferLength else {
        throw MetalWaveError.deviceResourceLimit(bytes: overflow ? Int.max : bytes)
      }
      guard
        let b = device.makeBuffer(
          length: bytes, options: [.storageModeShared, .hazardTrackingModeTracked])
      else { throw MetalWaveError.allocationFailed }
      return b
    }
    fullPressure = try owner.full.map { try buffer($0.indices.count * 128) }
    fullVelocity = try owner.full.map { try buffer($0.indices.count * 129) }
    onlyPressure = try owner.pressureOnly.map { try buffer($0.indices.count * 128) }
    mixedPressure = try owner.mixed.map { try buffer($0.indices.count * 128) }
    mixedVelocity = try owner.mixed.map { try buffer($0.indices.count * 129) }
  }
}
