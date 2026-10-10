import CompressibleFlow
import Foundation
import Testing
import simd

@Suite("Prescribed gas packet conservation")
struct PrescribedGasTransportTests {
  typealias Gas = PrescribedGasTransport
  private func cell(_ volume: Double, _ mass: Double, _ momentum: SIMD3<Double>, _ energy: Double)
    -> Gas.Cell
  {
    Gas.Cell(
      volume: volume, amount: SIMD8(mass, momentum.x, momentum.y, momentum.z, energy, 0, 0, 0))
  }
  private var initial: [Gas.Cell] {
    [
      cell(1, 2, SIMD3(2, -4, 6), 64), cell(2, 8, SIMD3(-8, 0, 4), 128),
      cell(4, 1, SIMD3(0, 2, -1), 16),
    ]
  }
  private var transfers: [Gas.Transfer] {
    [.init(from: 0, to: 1, volume: 0.5), .init(from: 1, to: 2, volume: 1)]
  }
  @Test("SI conversion agrees with independent mass, kinetic and internal energy quantities")
  func conversion() {
    let c = Gas.Cell(volume: 2, density: 3, velocity: SIMD3(3, -4, 12), pressure: 7, gamma: 2)
    #expect(c.amount == SIMD8(6, 18, -24, 72, 521, 0, 0, 0))
    #expect(c.velocity == SIMD3(3, -4, 12))
    #expect(c.pressure(gamma: 2) == 7)
  }
  @Test("Three-cell simultaneous mixing matches analytically specified extensive packets")
  func analyticMixing() throws {
    let result = try Gas.advance(initial, newVolumes: [0.5, 1.5, 5], transfers: transfers)
    let expected = [
      cell(0.5, 1, SIMD3(1, -2, 3), 32), cell(1.5, 5, SIMD3(-3, -2, 5), 96),
      cell(5, 5, SIMD3(-4, 2, 1), 80),
    ]
    #expect(result == expected)
    #expect(
      try Gas.advance(initial, newVolumes: [0.5, 1.5, 5], transfers: transfers.reversed())
        == expected)
  }
  @Test("External gas impulse and work close the independent assembly ledger")
  func externalLedger() throws {
    let result = try Gas.advance(
      initial, newVolumes: [0.5, 1.5, 5], transfers: transfers,
      walls: [.init(cell: 1, impulse: SIMD3(2, -1, 3), gasWork: 5)])
    #expect(result[1] == cell(1.5, 5, SIMD3(-1, -3, 8), 101))
    let total = result.reduce(SIMD8<Double>.zero) { $0 + $1.amount }
    #expect(total == SIMD8(11, -4, -3, 12, 213, 0, 0, 0))
  }
  @Test("Conservation transforms covariantly under a Galilean velocity shift")
  func galileanLedger() throws {
    let boost = SIMD3<Double>(3, -2, 1)
    func shifted(_ c: Gas.Cell) -> Gas.Cell {
      let p = SIMD3(c.amount[1], c.amount[2], c.amount[3])
      let m = c.amount[0]
      return cell(
        c.volume, m, p + m * boost,
        c.amount[4] + simd_dot(boost, p) + 0.5 * m * simd_length_squared(boost))
    }
    let impulse = SIMD3<Double>(2, -1, 3)
    let a = try Gas.advance(
      initial, newVolumes: [0.5, 1.5, 5], transfers: transfers,
      walls: [.init(cell: 1, impulse: impulse, gasWork: 5)])
    let b = try Gas.advance(
      initial.map(shifted), newVolumes: [0.5, 1.5, 5], transfers: transfers,
      walls: [.init(cell: 1, impulse: impulse, gasWork: 5 + simd_dot(boost, impulse))])
    #expect(b == a.map(shifted))
  }
  @Test(
    "Uniform gas is preserved as prescribed cells close and open", arguments: [1.0, 1e-6, 1e-12])
  func uniformOpening(scale: Double) throws {
    let old = [scale, 4 * scale, 0].map {
      Gas.Cell(volume: $0, density: 2, velocity: SIMD3(1, 2, -3), pressure: 10)
    }
    let result = try Gas.advance(
      old, newVolumes: [0, 4 * scale, scale],
      transfers: [.init(from: 0, to: 1, volume: scale), .init(from: 1, to: 2, volume: scale)])
    #expect(result[0].amount == .zero)
    for c in result where c.volume > 0 {
      #expect(abs(c.amount[0] / c.volume - 2) < 1e-12)
      #expect(simd_length(c.velocity - SIMD3(1, 2, -3)) < 1e-12)
      #expect(abs(c.pressure() - 10) < 1e-12)
    }
  }
  @Test("Prescribed volume alone changes density and pressure without inventing a packet")
  func prescribedVolume() throws {
    let c = cell(1, 2, SIMD3(2, -4, 6), 64)
    let new = try Gas.advance([c], newVolumes: [0.25], transfers: [])[0]
    #expect(new.amount == c.amount)
    #expect(new.velocity == c.velocity)
    #expect(new.pressure() == 4 * c.pressure())
  }
  @Test("Supplied explicit pressure work refines toward the analytic adiabatic relation")
  func adiabaticWork() throws {
    let expected = 10 * pow(2, 1.4)
    var errors: [Double] = []
    for steps in [8, 32, 128, 512] {
      var c = Gas.Cell(volume: 1, density: 2, pressure: 10)
      let start = c.amount[4]
      var work = 0.0
      for n in 1...steps {
        let next = 1 - 0.5 * Double(n) / Double(steps)
        let increment = -c.pressure() * (next - c.volume)
        c = try Gas.advance(
          [c], newVolumes: [next], transfers: [],
          walls: [.init(cell: 0, impulse: .zero, gasWork: increment)])[0]
        work += increment
        #expect(c.amount[0] == 2)
        #expect(abs(c.amount[4] - start - work) < 1e-11)
      }
      errors.append(abs(c.pressure() / expected - 1))
    }
    #expect(zip(errors, errors.dropFirst()).allSatisfy { $1 < $0 })
    #expect(errors.last! < 1e-3)
  }
  @Test("Exact dry-cell cleanup boundary has an explicit discarded-work budget")
  func dryCleanupBoundary() throws {
    let old = [cell(1, 1, SIMD3(1, 0, 0), 64), cell(0, 0, .zero, 0)]
    let budget = Double(sign: .plus, exponent: -40, significand: 1)  // 64 eps times 64 J.
    let result = try Gas.advance(
      old, newVolumes: [0, 1], transfers: [.init(from: 0, to: 1, volume: 1)],
      walls: [.init(cell: 0, impulse: .zero, gasWork: budget)])
    #expect(result[0].amount == .zero)
    #expect(result[1].amount == old[0].amount)
    #expect(result[0].amount[4].bitPattern == 0)
    #expect(throws: Gas.Failure.occupiedDryCell) {
      try Gas.advance(
        old, newVolumes: [0, 1], transfers: [.init(from: 0, to: 1, volume: 1)],
        walls: [.init(cell: 0, impulse: .zero, gasWork: budget.nextUp)])
    }
  }
  @Test("Dry cells canonicalize storage zero while retaining supplied volume sign")
  func signedZero() throws {
    let old = cell(-0.0, -0.0, SIMD3(-0.0, 0, -0.0), -0.0)
    let result = try Gas.advance([old], newVolumes: [-0.0], transfers: [])[0]
    #expect(result.volume.bitPattern == (-0.0).bitPattern)
    #expect((0..<8).allSatisfy { result.amount[$0].bitPattern == 0 })
    #expect(try Gas.advance([], newVolumes: [], transfers: []).isEmpty)
  }
  @Test("Aggregate donor capacity cannot borrow incoming volume during an update")
  func frozenCapacity() {
    #expect(throws: Gas.Failure.excessiveOutflow) {
      try Gas.advance(
        initial, newVolumes: [0.5, 0.5, 6],
        transfers: [.init(from: 0, to: 1, volume: 0.5), .init(from: 1, to: 2, volume: 2.25)])
    }
    #expect(throws: Gas.Failure.excessiveOutflow) {
      try Gas.advance(
        initial, newVolumes: [0, 2, 5],
        transfers: [.init(from: 0, to: 1, volume: 0.75), .init(from: 0, to: 2, volume: 0.5)])
    }
  }
  @Test("Invalid graph endpoints, self transfers and invalid volumes reject explicitly")
  func badTransfers() {
    for t in [
      Gas.Transfer(from: -1, to: 1, volume: 0), .init(from: 0, to: 3, volume: 0),
      .init(from: 0, to: 0, volume: 0), .init(from: 0, to: 1, volume: -1),
      .init(from: 0, to: 1, volume: .nan), .init(from: 0, to: 1, volume: .infinity),
    ] {
      #expect(throws: Gas.Failure.invalidTransfer) {
        try Gas.advance(initial, newVolumes: [1, 2, 4], transfers: [t])
      }
    }
    #expect(throws: Gas.Failure.invalidTransfer) {
      try Gas.advance(
        [cell(0, 0, .zero, 0), initial[1]], newVolumes: [0, 2],
        transfers: [.init(from: 0, to: 1, volume: 0.1)])
    }
  }
  @Test("Non-finite, negative, reserved-lane and nonphysical extensive inputs reject")
  func badStates() {
    var reserved = initial[0].amount
    reserved[7] = 1
    for bad in [
      cell(-1, 2, .zero, 64), cell(.nan, 2, .zero, 64), cell(.infinity, 2, .zero, 64),
      cell(1, 0, .zero, 1), cell(1, -1, .zero, 1), cell(1, 1, SIMD3(1, 0, 0), 0.5),
      cell(1, .nan, .zero, 64), cell(1, 1, SIMD3(.infinity, 0, 0), 64),
      Gas.Cell(volume: 1, amount: reserved), cell(0, 1, .zero, 64),
    ] {
      #expect(throws: Gas.Failure.invalidState) {
        try Gas.advance([bad], newVolumes: [1], transfers: [])
      }
    }
    #expect(throws: Gas.Failure.invalidState) {
      try Gas.advance(initial, newVolumes: [1, 2], transfers: [])
    }
    for volume in [-1.0, Double.nan, Double.infinity] {
      #expect(throws: Gas.Failure.invalidState) {
        try Gas.advance([initial[0]], newVolumes: [volume], transfers: [])
      }
    }
  }
  @Test("Nonphysical wall trials and occupied dry results reject without modifying inputs")
  func failedTrial() {
    let old = initial
    for wall in [
      Gas.WallExchange(cell: 3, impulse: .zero, gasWork: 0),
      .init(cell: 0, impulse: SIMD3(.nan, 0, 0), gasWork: 0),
      .init(cell: 0, impulse: .zero, gasWork: .infinity),
      .init(cell: 0, impulse: .zero, gasWork: -64),
      .init(cell: 0, impulse: SIMD3(100, 0, 0), gasWork: 0),
    ] {
      #expect(throws: Gas.Failure.invalidState) {
        try Gas.advance(old, newVolumes: [1, 2, 4], transfers: [], walls: [wall])
      }
    }
    #expect(throws: Gas.Failure.occupiedDryCell) {
      try Gas.advance(old, newVolumes: [0, 2, 4], transfers: [])
    }
    #expect(old == initial)
  }
  @Test("Unrepresentable intermediate momentum or pressure fails instead of flooring")
  func extremeStates() {
    for bad in [cell(1, 1, SIMD3(1e200, 0, 0), 1e300), cell(1e-300, 1, .zero, 1e300)] {
      #expect(throws: Gas.Failure.invalidState) {
        try Gas.advance([bad], newVolumes: [bad.volume], transfers: [])
      }
    }
  }
}
