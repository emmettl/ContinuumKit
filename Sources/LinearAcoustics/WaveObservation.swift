// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.

public enum WaveObservationError: Error, Equatable, Sendable {
  case invalidStencil(receiver: Int)
  case invalidPressureCell(receiver: Int, entry: Int)
  case nonfiniteWeight(receiver: Int, entry: Int)
  case invalidVelocityProbe(receiver: Int)
  case nonfiniteAxis(receiver: Int)
  case gridMismatch
  case batchTooLarge
  case nonfiniteResult(receiver: Int)
  case invalidFrame
  case inconsistentFrames
  case nonconsecutiveFrames
  case finished
}

/// Ordered eight-slot pressure stencil and optional cell-centred native velocity projection.
/// The caller supplies geometry/weights/axis; no normalization or position clamping occurs.
public struct WaveReceiverStencil: Sendable {
  public let pressureCells: [Int]
  public let pressureWeights: [Float]
  public let velocityCell: Int?
  public let velocityAxis: SIMD3<Double>?
  public init(
    pressureCells: [Int], pressureWeights: [Float], velocityCell: Int? = nil,
    velocityAxis: SIMD3<Double>? = nil
  ) {
    self.pressureCells = pressureCells
    self.pressureWeights = pressureWeights
    self.velocityCell = velocityCell
    self.velocityAxis = velocityAxis
  }
}

final class WaveObservationIdentity: Sendable {
  let receiverCount: Int
  init(_ count: Int) { receiverCount = count }
}

public struct PreparedWaveObservation: Sendable {
  let identity: WaveObservationIdentity
  public let receivers: [WaveReceiverStencil]
  private let gridIdentity: WaveGridIdentity
  /// Observation advances retain at most this many complete frames in one call.
  public static let maximumBatchSteps = 128
  public init(grid: PreparedWaveGrid, receivers: [WaveReceiverStencil]) throws {
    guard receivers.count <= Int(UInt32.max) / 8 else { throw WaveObservationError.batchTooLarge }
    for (receiver, stencil) in receivers.enumerated() {
      guard stencil.pressureCells.count == 8, stencil.pressureWeights.count == 8 else {
        throw WaveObservationError.invalidStencil(receiver: receiver)
      }
      for entry in 0..<8 {
        let cell = stencil.pressureCells[entry]
        guard cell >= 0, cell < grid.cellCount else {
          throw WaveObservationError.invalidPressureCell(receiver: receiver, entry: entry)
        }
        guard stencil.pressureWeights[entry].isFinite else {
          throw WaveObservationError.nonfiniteWeight(receiver: receiver, entry: entry)
        }
      }
      switch (stencil.velocityCell, stencil.velocityAxis) {
      case (nil, nil): break
      case (.some(let cell), .some(let axis)):
        guard cell >= 0, cell < grid.cellCount,
          cell % grid.dimensions.x > 0,
          cell / grid.dimensions.x % grid.dimensions.y > 0,
          cell / (grid.dimensions.x * grid.dimensions.y) > 0
        else { throw WaveObservationError.invalidVelocityProbe(receiver: receiver) }
        guard (0..<3).allSatisfy({ axis[$0].isFinite }) else {
          throw WaveObservationError.nonfiniteAxis(receiver: receiver)
        }
      default: throw WaveObservationError.invalidVelocityProbe(receiver: receiver)
      }
    }
    identity = WaveObservationIdentity(receivers.count)
    self.receivers = receivers
    gridIdentity = grid.identity
  }
  public func validate(for grid: PreparedWaveGrid) throws {
    guard gridIdentity === grid.identity else { throw WaveObservationError.gridMismatch }
  }
}

/// Owned readout: psi at integer pressure time, projected velocity at the preceding half time.
/// Value construction does not certify fields; alignment validates all caller-supplied frames.
public struct WaveObservationFrame: Sendable {
  public let pressureStepIndex: Int
  public let timeStep: Double
  public let pressureOverDensity: [Double]
  public let projectedVelocity: [Double?]
  let identity: WaveObservationIdentity?
  public init(
    pressureStepIndex: Int, timeStep: Double, pressureOverDensity: [Double],
    projectedVelocity: [Double?], observation: PreparedWaveObservation? = nil
  ) {
    self.pressureStepIndex = pressureStepIndex
    self.timeStep = timeStep
    self.pressureOverDensity = pressureOverDensity
    self.projectedVelocity = projectedVelocity
    identity = observation?.identity
  }
  public var pressureTime: Double { Double(pressureStepIndex) * timeStep }
  public var velocityTime: Double { (Double(pressureStepIndex) - 0.5) * timeStep }
  func validate() throws {
    guard pressureStepIndex >= 0, timeStep.isFinite, timeStep > 0,
      pressureTime.isFinite, velocityTime.isFinite,
      pressureOverDensity.count == projectedVelocity.count,
      identity.map({ $0.receiverCount == pressureOverDensity.count }) ?? true,
      pressureOverDensity.allSatisfy(\.isFinite),
      projectedVelocity.allSatisfy({ $0?.isFinite ?? true })
    else { throw WaveObservationError.invalidFrame }
  }
}

/// Pressure with temporally aligned velocity; the explicit terminal fallback retains its half clock.
public struct AlignedWaveObservationFrame: Sendable {
  public let pressureStepIndex: Int
  public let timeStep: Double
  public let pressureOverDensity: [Double]
  public let projectedVelocity: [Double?]
  public let usesTerminalHalfStep: Bool
  public var pressureTime: Double { Double(pressureStepIndex) * timeStep }
  public var velocityTime: Double {
    (Double(pressureStepIndex) - (usesTerminalHalfStep ? 0.5 : 0)) * timeStep
  }
}

/// One-frame lookahead across arbitrary chunks. Microphone mixing and sound-speed scaling stay caller-owned.
/// Rejected batches preserve pending state. Finish explicitly selects the original final-half-step policy.
public struct WaveObservationAligner: Sendable {
  private var pending: WaveObservationFrame?
  private var sealed = false
  public init() {}
  public mutating func append(_ frames: [WaveObservationFrame]) throws
    -> [AlignedWaveObservationFrame]
  {
    guard !sealed else { throw WaveObservationError.finished }
    var next = pending
    var result: [AlignedWaveObservationFrame] = []
    for frame in frames {
      try frame.validate()
      if let previous = next {
        guard previous.identity === frame.identity, previous.timeStep == frame.timeStep,
          previous.pressureOverDensity.count == frame.pressureOverDensity.count,
          zip(previous.projectedVelocity, frame.projectedVelocity).allSatisfy({
            ($0 == nil) == ($1 == nil)
          })
        else { throw WaveObservationError.inconsistentFrames }
        let (index, overflow) = previous.pressureStepIndex.addingReportingOverflow(1)
        guard !overflow, frame.pressureStepIndex == index else {
          throw WaveObservationError.nonconsecutiveFrames
        }
        var velocity: [Double?] = []
        for receiver in previous.projectedVelocity.indices {
          if let before = previous.projectedVelocity[receiver],
            let after = frame.projectedVelocity[receiver]
          {
            let value = (before + after) / 2
            guard value.isFinite else {
              throw WaveObservationError.nonfiniteResult(receiver: receiver)
            }
            velocity.append(value)
          } else {
            velocity.append(nil)
          }
        }
        result.append(
          AlignedWaveObservationFrame(
            pressureStepIndex: previous.pressureStepIndex,
            timeStep: previous.timeStep, pressureOverDensity: previous.pressureOverDensity,
            projectedVelocity: velocity, usesTerminalHalfStep: false))
      }
      next = frame
    }
    pending = next
    return result
  }
  public mutating func finishUsingFinalHalfStep() throws -> [AlignedWaveObservationFrame] {
    guard !sealed else { throw WaveObservationError.finished }
    sealed = true
    guard let frame = pending else { return [] }
    pending = nil
    return [
      AlignedWaveObservationFrame(
        pressureStepIndex: frame.pressureStepIndex,
        timeStep: frame.timeStep, pressureOverDensity: frame.pressureOverDensity,
        projectedVelocity: frame.projectedVelocity, usesTerminalHalfStep: true)
    ]
  }
}
