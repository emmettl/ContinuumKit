import Foundation

/// Uniform, sealed, calorically perfect reservoir with constant heat-capacity ratio.
/// SI units: volume m³, internal energy J and pressure Pa. Work is positive out of the reservoir.
/// This potential supplies no gas transport, geometry, heat, venting or mechanics integration.
public struct AdiabaticReservoir: Sendable {
  public enum Failure: Error { case invalidReference, invalidVolume, unrepresentableState }
  public struct State: Equatable, Sendable {
    public let volume: Double
    public let energy: Double
    public let pressure: Double
  }
  public let referenceVolume: Double
  public let referenceEnergy: Double
  public let heatCapacityRatio: Double

  public init(referenceVolume: Double, referenceEnergy: Double, heatCapacityRatio: Double = 1.4)
    throws
  {
    guard referenceVolume.isFinite, referenceVolume > 0, referenceEnergy.isFinite,
      referenceEnergy >= 0, heatCapacityRatio.isFinite, heatCapacityRatio > 1
    else { throw Failure.invalidReference }
    self.referenceVolume = referenceVolume
    self.referenceEnergy = referenceEnergy
    self.heatCapacityRatio = heatCapacityRatio
    _ = try state(atVolume: referenceVolume)
  }

  public func state(atVolume volume: Double) throws -> State {
    guard volume.isFinite, volume > 0 else { throw Failure.invalidVolume }
    if referenceEnergy == 0 { return State(volume: volume, energy: 0, pressure: 0) }
    // The energy and pressure expressions retain Edgerton's original evaluation order.
    let energy = referenceEnergy * pow(referenceVolume / volume, heatCapacityRatio - 1)
    let pressure = (heatCapacityRatio - 1) * energy / volume
    guard energy.isFinite, pressure.isFinite, energy > 0, pressure > 0 else {
      throw Failure.unrepresentableState
    }
    return State(volume: volume, energy: energy, pressure: pressure)
  }

  /// Signed boundary work for a reversible volume change; compression returns work to the reservoir.
  public func work(fromVolume from: Double, toVolume to: Double) throws -> Double {
    let initial = try state(atVolume: from)
    _ = try state(atVolume: to)
    if initial.energy == 0 || from == to { return 0 }
    let change = (to - from) / from
    let logarithm = change.isFinite && change > -1 ? log1p(change) : log(to) - log(from)
    // Avoid subtracting nearly equal energies for a small change in volume.
    let work = -initial.energy * expm1(-(heatCapacityRatio - 1) * logarithm)
    guard work.isFinite else { throw Failure.unrepresentableState }
    return work
  }
}
