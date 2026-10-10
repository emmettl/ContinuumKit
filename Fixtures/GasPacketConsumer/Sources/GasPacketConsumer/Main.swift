import CompressibleFlow
import Foundation
import simd

struct Snapshot: Codable {
  let volume: Double
  let amount, velocity: [Double]
  let pressure: Double
  let bits: [UInt64]
  init(volume: Double, amount: SIMD8<Double>, velocity: SIMD3<Double>, pressure: Double) {
    self.volume = volume
    self.amount = (0..<8).map { amount[$0] }
    self.velocity = (0..<3).map { velocity[$0] }
    self.pressure = pressure
    bits = ([volume] + self.amount + self.velocity + [pressure]).map(\.bitPattern)
  }
}
struct Transfer: Codable {
  let from, to: Int
  let volume: Double
}
struct Wall: Codable {
  let cell: Int
  let impulse: [Double]
  let gasWork: Double
}
struct Case: Codable {
  let id: String
  let matrix: [Int]?
  let originalInput, sharedInput: [Snapshot]
  let newVolumes: [Double]
  let newVolumeBits: [UInt64]
  let transfers: [Transfer]
  let walls: [Wall]
  let original, shared: [Snapshot]?
  let originalFailure, sharedFailure: String?
}
@main enum GasPacketConsumer {
  typealias New = PrescribedGasTransport
  typealias Old = FractionalGasTransport
  static func snapshot(_ c: Old.Cell) -> Snapshot {
    Snapshot(volume: c.volume, amount: c.amount, velocity: c.velocity, pressure: c.pressure())
  }
  static func snapshot(_ c: New.Cell) -> Snapshot {
    Snapshot(volume: c.volume, amount: c.amount, velocity: c.velocity, pressure: c.pressure())
  }
  static func record(
    id: String, matrix: [Int]? = nil, old: [Old.Cell], new: [New.Cell], volumes: [Double],
    transfers: [Transfer], walls: [Wall] = []
  ) throws -> Case {
    let oi = old.map(snapshot)
    let ni = new.map(snapshot)
    guard oi.map(\.bits) == ni.map(\.bits) else { throw Failure.mismatch(id + " constructor") }
    var original: [Snapshot]?
    var shared: [Snapshot]?
    var originalFailure: String?
    var sharedFailure: String?
    do {
      original = try Old.advance(
        old, newVolumes: volumes,
        transfers: transfers.map { .init(from: $0.from, to: $0.to, volume: $0.volume) },
        walls: walls.map {
          .init(
            cell: $0.cell, impulse: SIMD3($0.impulse[0], $0.impulse[1], $0.impulse[2]),
            gasWork: $0.gasWork)
        }
      ).map(snapshot)
    } catch { originalFailure = String(describing: error) }
    do {
      shared = try New.advance(
        new, newVolumes: volumes,
        transfers: transfers.map { .init(from: $0.from, to: $0.to, volume: $0.volume) },
        walls: walls.map {
          .init(
            cell: $0.cell, impulse: SIMD3($0.impulse[0], $0.impulse[1], $0.impulse[2]),
            gasWork: $0.gasWork)
        }
      ).map(snapshot)
    } catch { sharedFailure = String(describing: error) }
    guard originalFailure == sharedFailure, original?.map(\.bits) == shared?.map(\.bits) else {
      throw Failure.mismatch(id + " update")
    }
    return Case(
      id: id, matrix: matrix, originalInput: oi, sharedInput: ni, newVolumes: volumes,
      newVolumeBits: volumes.map(\.bitPattern),
      transfers: transfers, walls: walls, original: original, shared: shared,
      originalFailure: originalFailure, sharedFailure: sharedFailure)
  }
  static func main() throws {
    var cases: [Case] = []
    let scales = [1e-9, 1.0, 1e6]
    let densities = [0.25, 1.225, 7.0]
    let pressures = [1.0, 101325, 1e7]
    let velocities = [SIMD3<Double>.zero, SIMD3(1, -2, 3), SIMD3(100, 50, -25)]
    let fractions = [0.0, 0.125, 0.5, 1.0]
    for (si, s) in scales.enumerated() {
      for (di, rho) in densities.enumerated() {
        for (pi, p) in pressures.enumerated() {
          for (vi, u) in velocities.enumerated() {
            for (fi, f) in fractions.enumerated() {
              for topology in 0..<5 {
                let count = topology == 0 ? 2 : 3
                let volumes = (0..<count).map { n in topology == 3 && n == 2 ? 0 : s * [1, 2, 4][n]
                }
                let rs = [rho, 2 * rho, 0.5 * rho]
                let ps = [p, 0.5 * p, 2 * p]
                let vs = [u, -0.5 * u, 0.25 * u]
                let old = (0..<count).map {
                  Old.Cell(volume: volumes[$0], density: rs[$0], velocity: vs[$0], pressure: ps[$0])
                }
                let new = (0..<count).map {
                  New.Cell(volume: volumes[$0], density: rs[$0], velocity: vs[$0], pressure: ps[$0])
                }
                var transfers = [Transfer(from: 0, to: 1, volume: s * f)]
                var next = [s * (1 - f), s * (2 + f)]
                if topology != 0 {
                  let outgoing = topology == 3 ? s * f : 2 * s * f
                  transfers.append(Transfer(from: 1, to: 2, volume: outgoing))
                  next = [s * (1 - f), 2 * s + s * f - outgoing, volumes[2] + outgoing]
                }
                if topology == 2 {
                  transfers.append(Transfer(from: 2, to: 0, volume: 4 * s * f))
                  next[0] += 4 * s * f
                  next[2] -= 4 * s * f
                }
                var walls: [Wall] = []
                if topology == 4 {
                  let mass = old[1].amount[0] * (1 - f) + old[0].amount[0] * f
                  let momentum =
                    SIMD3(old[1].amount[1], old[1].amount[2], old[1].amount[3]) * (1 - f) + SIMD3(
                      old[0].amount[1], old[0].amount[2], old[0].amount[3]) * f
                  let impulse = mass * SIMD3<Double>(0.01, -0.02, 0.005)
                  let work =
                    simd_dot(momentum, impulse) / mass + simd_length_squared(impulse) / (2 * mass)
                    + s * p / 16
                  walls = [
                    Wall(cell: 1, impulse: [impulse.x, impulse.y, impulse.z], gasWork: work)
                  ]
                }
                let matrix = [si, di, pi, vi, fi, topology]
                let item = try record(
                  id: "matrix/" + matrix.map(String.init).joined(separator: "/"), matrix: matrix,
                  old: old, new: new, volumes: next, transfers: transfers, walls: walls)
                guard item.originalFailure == nil else {
                  throw Failure.mismatch(item.id + " unexpected failure")
                }
                cases.append(item)
              }
            }
          }
        }
      }
    }
    let a = Old.Cell(volume: 1, amount: SIMD8(1, 1, 0, 0, 64, 0, 0, 0))
    let b = Old.Cell(volume: 0, amount: .zero)
    let base = [a, b]
    let newBase = base.map { New.Cell(volume: $0.volume, amount: $0.amount) }
    for (label, old, volumes, transfers, walls) in [
      ("self", base, [1.0, 0], [Transfer(from: 0, to: 0, volume: 0)], []),
      ("negativeIndex", base, [1.0, 0], [Transfer(from: -1, to: 1, volume: 0)], []),
      ("largeIndex", base, [1.0, 0], [Transfer(from: 0, to: 2, volume: 0)], []),
      ("negativeTransfer", base, [1.0, 0], [Transfer(from: 0, to: 1, volume: -1)], []),
      ("excessiveOutflow", base, [0.0, 1], [Transfer(from: 0, to: 1, volume: 1.01)], []),
      ("occupiedDry", base, [0.0, 1], [], []),
      ("invalidVolume", base, [-1.0, 1], [], []),
      ("mismatchedCount", base, [1.0], [], []),
      ("negativeEnergy", base, [1.0, 0], [], [Wall(cell: 0, impulse: [0, 0, 0], gasWork: -64)]),
      ("excessiveImpulse", base, [1.0, 0], [], [Wall(cell: 0, impulse: [100, 0, 0], gasWork: 0)]),
      ("invalidWall", base, [1.0, 0], [], [Wall(cell: 2, impulse: [0, 0, 0], gasWork: 0)]),
      (
        "reservedLane", [Old.Cell(volume: 1, amount: SIMD8(1, 1, 0, 0, 64, 0, 0, 1)), b], [1.0, 0],
        [], []
      ),
    ] as [(String, [Old.Cell], [Double], [Transfer], [Wall])] {
      let sharedOld = old.map { New.Cell(volume: $0.volume, amount: $0.amount) }
      cases.append(
        try record(
          id: "rejection/" + label, old: old, new: sharedOld, volumes: volumes,
          transfers: transfers, walls: walls))
    }
    let threshold = Double(sign: .plus, exponent: -40, significand: 1)
    for (label, work) in [
      ("below", threshold.nextDown), ("at", threshold), ("above", threshold.nextUp),
    ] {
      cases.append(
        try record(
          id: "cleanup/" + label, old: base, new: newBase, volumes: [0, 1],
          transfers: [Transfer(from: 0, to: 1, volume: 1)],
          walls: [Wall(cell: 0, impulse: [0, 0, 0], gasWork: work)]))
    }
    let signed = Old.Cell(volume: -0.0, amount: SIMD8(repeating: -0.0))
    cases.append(
      try record(
        id: "signedZero", old: [signed],
        new: [New.Cell(volume: signed.volume, amount: signed.amount)], volumes: [-0.0],
        transfers: []))
    cases.append(try record(id: "empty", old: [], new: [], volumes: [], transfers: []))
    let environment = ProcessInfo.processInfo.environment
    guard let output = environment["CONTINUUMKIT_PACKET_OUTPUT"] else { throw Failure.output }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(cases).write(
      to: URL(fileURLWithPath: output).appendingPathComponent("cases.json"))
    let summary = [
      "candidate": environment["CONTINUUMKIT_CONSUMER_REVISION"] ?? "unknown",
      "version": environment["CONTINUUMKIT_CONSUMER_VERSION"] ?? "", "matrixCases": "1620",
      "totalCases": String(cases.count), "bitMismatches": "0",
      "scope":
        "prescribed extensive packet transfer and external gas impulse/work; no geometry/flux/timestep/Metal dependency",
    ]
    try encoder.encode(summary).write(
      to: URL(fileURLWithPath: output).appendingPathComponent("summary.json"))
    print("PASS fetched public gas packet API: \(cases.count) complete original/shared cases")
  }
  enum Failure: Error {
    case mismatch(String)
    case output
  }
}
