import simd

/// Conservative packet transfer in caller-prescribed gas volumes (SI units).
/// Authored source: emmettl/bombcad, MIT; see docs/extraction/gas-packet-source.json.
/// Cell construction and algebraic accessors are unchecked. `advance` validates finite
/// extensive states and positive internal energy; pressure accessors require gamma > 1.
/// The operator neither enforces geometric volume consistency nor chooses physical loads.
/// CPU reference for extensive mass, momentum and total energy in prescribed gas volumes.
/// Face transfers are supplied by the caller; this does not construct a displacement field,
/// solve a Riemann problem, choose a timestep or change the app's air solver.
public enum PrescribedGasTransport {
  public enum Failure: Error, Equatable {
    case invalidState, invalidTransfer, excessiveOutflow, occupiedDryCell
  }
  public struct Cell: Equatable, Sendable {
    /// Volume (m³); zero denotes an empty cell.
    public let volume: Double
    /// Mass (kg), momentum xyz (kg m/s), total energy (J), then three reserved zero lanes.
    public let amount: SIMD8<Double>  // mass, momentum xyz, total energy; remaining lanes zero
    public init(
      volume: Double, density: Double, velocity: SIMD3<Double> = .zero, pressure: Double,
      gamma: Double = 1.4
    ) {
      self.volume = volume
      let mass = volume * density
      amount = SIMD8(
        mass, mass * velocity.x, mass * velocity.y, mass * velocity.z,
        volume * pressure / (gamma - 1) + 0.5 * mass * simd_length_squared(velocity), 0, 0, 0)
    }
    public init(volume: Double, amount: SIMD8<Double>) {
      self.volume = volume
      self.amount = amount
    }
    public var velocity: SIMD3<Double> {
      amount[0] > 0 ? SIMD3(amount[1], amount[2], amount[3]) / amount[0] : .zero
    }
    public func pressure(gamma: Double = 1.4) -> Double {
      volume > 0
        ? (gamma - 1) * (amount[4] - 0.5 * amount[0] * simd_length_squared(velocity)) / volume : 0
    }
  }
  public struct Transfer: Equatable, Sendable {
    public let from: Int
    public let to: Int
    public let volume: Double
    public init(from: Int, to: Int, volume: Double) {
      self.from = from
      self.to = to
      self.volume = volume
    }
  }
  public struct WallExchange: Equatable, Sendable {
    public let cell: Int
    public let impulse: SIMD3<Double>
    public let gasWork: Double
    public init(cell: Int, impulse: SIMD3<Double>, gasWork: Double) {
      self.cell = cell
      self.impulse = impulse
      self.gasWork = gasWork
    }
  }

  /// Frozen donor states prevent inflow from being reused in the same update. Total
  /// outflow is bounded by each donor's old volume; wall work may still make a state invalid.
  /// Impulse and gasWork act ON the gas. A dry result discards residuals bounded per
  /// physical lane by 64 * epsilon * max(abs(old amount), 1e-300), then writes +0.
  /// This cleanup has a rounding budget; it is not exact arithmetic conservation.
  public static func advance(
    _ old: [Cell], newVolumes: [Double], transfers: [Transfer], walls: [WallExchange] = []
  ) throws -> [Cell] {
    guard old.count == newVolumes.count else { throw Failure.invalidState }
    for n in old.indices {
      guard valid(old[n]), newVolumes[n].isFinite && newVolumes[n] >= 0 else {
        throw Failure.invalidState
      }
    }
    var outgoing = Array(repeating: 0.0, count: old.count)
    for transfer in transfers {
      guard old.indices.contains(transfer.from), old.indices.contains(transfer.to),
        transfer.from != transfer.to,
        transfer.volume.isFinite && transfer.volume >= 0,
        transfer.volume == 0 || old[transfer.from].volume > 0
      else { throw Failure.invalidTransfer }
      outgoing[transfer.from] += transfer.volume
    }
    for n in old.indices {
      guard outgoing[n] <= old[n].volume else { throw Failure.excessiveOutflow }
    }
    var amounts = old.map(\.amount)
    for transfer in transfers where transfer.volume > 0 {
      let carried = old[transfer.from].amount * (transfer.volume / old[transfer.from].volume)
      amounts[transfer.from] -= carried
      amounts[transfer.to] += carried
    }
    for wall in walls {
      guard old.indices.contains(wall.cell), wall.gasWork.isFinite,
        (0..<3).allSatisfy({ wall.impulse[$0].isFinite })
      else { throw Failure.invalidState }
      amounts[wall.cell] += SIMD8(
        0, wall.impulse.x, wall.impulse.y, wall.impulse.z, wall.gasWork, 0, 0, 0)
    }
    var result: [Cell] = []
    for n in old.indices {
      if newVolumes[n] == 0 {
        for axis in 0..<5 {
          let scale = max(abs(old[n].amount[axis]), 1e-300)
          guard abs(amounts[n][axis]) <= 64 * Double.ulpOfOne * scale else {
            throw Failure.occupiedDryCell
          }
        }
        amounts[n] = .zero
      }
      let cell = Cell(volume: newVolumes[n], amount: amounts[n])
      guard valid(cell) else { throw Failure.invalidState }
      result.append(cell)
    }
    return result
  }
  private static func valid(_ cell: Cell) -> Bool {
    guard cell.volume.isFinite && cell.volume >= 0,
      (0..<8).allSatisfy({ cell.amount[$0].isFinite }),
      (5..<8).allSatisfy({ cell.amount[$0] == 0 })
    else { return false }
    if cell.volume == 0 { return cell.amount == .zero }
    return cell.amount[0] > 0 && cell.pressure().isFinite && cell.pressure() > 0
  }
}
