// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.
import Metal

/// Immutable compiled wave pipelines for one explicitly supplied physical device.
/// Share this context across independent runs; mutable queues, fields, staging, output
/// and complete-step clocks remain owned by each single-owner MetalWaveStepper.
/// The context does not select a device, cache globally or submit GPU work.
public final class MetalWaveContext: Sendable {
  public let deviceName: String
  public let deviceRegistryID: UInt64
  let device: any MTLDevice
  let velocity, pressure, injection, sampling, pressureSampling,
    mixedSampling: any MTLComputePipelineState

  public init(device: any MTLDevice) throws {
    let library: any MTLLibrary
    do {
      library = try device.makeLibrary(source: MetalWaveStepper.shaderSource(), options: nil)
    } catch let
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
    self.device = device
    deviceName = device.name
    deviceRegistryID = device.registryID
    velocity = try pipeline("waveVelocity")
    pressure = try pipeline("wavePressure")
    injection = try pipeline("waveInject")
    sampling = try pipeline("waveSample")
    pressureSampling = try pipeline("waveSamplePressure")
    mixedSampling = try pipeline("waveSampleMixed")
  }

  var pipelineIdentities: [ObjectIdentifier] {
    [velocity, pressure, injection, sampling, pressureSampling, mixedSampling].map(
      ObjectIdentifier.init)
  }
}
