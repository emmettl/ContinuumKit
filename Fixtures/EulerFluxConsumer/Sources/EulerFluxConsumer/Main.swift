import CompressibleFlow
import Foundation
import simd

// The original is an immutable verification oracle, with its already released primitives.
typealias FractionalGasTransport = CompressibleFlow.PrescribedGasTransport
typealias IdealGasWallRiemann = CompressibleFlow.IdealGasWallRiemann
typealias Cell = PrescribedGasTransport.Cell

struct NativeCell: Codable, Equatable {
  let values: [Double]
  let bits: [String]
  init(_ c: Cell) {
    values =
      [c.volume] + (0..<8).map { c.amount[$0] }
      + (0..<3).map { c.velocity[$0] } + [c.pressure()]
    bits = values.map { String($0.bitPattern, radix: 16) }
  }
  var cell: Cell {
    Cell(
      volume: values[0],
      amount: SIMD8(
        values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8]))
  }
}
struct FaceInput: Codable {
  let a: Int, b: Int
  let normal: [Double], area: Double
  var left: NativeCell? = nil, right: NativeCell? = nil
}
struct WallInput: Codable {
  let cell: Int, normal: [Double], area: Double, velocity: [Double]
  var state: NativeCell? = nil
}
struct Interval: Codable {
  let time: Double, duration: Double, cfl: Double
  let limit: Double?, limitBits: String?
  let input: [NativeCell], faces: [FaceInput], walls: [WallInput]
  let result: [NativeCell]?, impulses: [[Double]]?, work: [Double]?
  let failure: String?, failureStage: String?
}
struct Case: Codable {
  let id: String, kind: String, parameters: [String: Double]
  let intervals: [Interval]
}
func vector(_ a: [Double]) -> SIMD3<Double> { SIMD3(a[0], a[1], a[2]) }
enum Backend {
  case original, shared
  func limit(_ cells: [Cell], _ f: [FaceInput], _ w: [WallInput], _ cfl: Double) throws -> Double {
    switch self {
    case .original:
      return try FractionalEulerFlux.maximumStep(
        cells,
        faces: f.map {
          .init(
            a: $0.a, b: $0.b, normal: vector($0.normal), area: $0.area, leftState: $0.left?.cell,
            rightState: $0.right?.cell)
        },
        walls: w.map {
          .init(
            cell: $0.cell, normal: vector($0.normal), area: $0.area, velocity: vector($0.velocity),
            state: $0.state?.cell)
        }, cfl: cfl)
    case .shared:
      return try CompressibleFlow.FractionalEulerFlux.maximumStep(
        cells,
        faces: f.map {
          .init(
            a: $0.a, b: $0.b, normal: vector($0.normal), area: $0.area, leftState: $0.left?.cell,
            rightState: $0.right?.cell)
        },
        walls: w.map {
          .init(
            cell: $0.cell, normal: vector($0.normal), area: $0.area, velocity: vector($0.velocity),
            state: $0.state?.cell)
        }, cfl: cfl)
    }
  }
  func step(_ cells: [Cell], _ f: [FaceInput], _ w: [WallInput], _ dt: Double, _ cfl: Double) throws
    -> ([Cell], [SIMD3<Double>], [Double])
  {
    switch self {
    case .original:
      let r = try FractionalEulerFlux.advanceWithWalls(
        cells,
        faces: f.map {
          .init(
            a: $0.a, b: $0.b, normal: vector($0.normal), area: $0.area, leftState: $0.left?.cell,
            rightState: $0.right?.cell)
        },
        walls: w.map {
          .init(
            cell: $0.cell, normal: vector($0.normal), area: $0.area, velocity: vector($0.velocity),
            state: $0.state?.cell)
        }, duration: dt, cfl: cfl)
      return (r.cells, r.wallImpulses, r.wallWork)
    case .shared:
      let r = try CompressibleFlow.FractionalEulerFlux.advanceWithWalls(
        cells,
        faces: f.map {
          .init(
            a: $0.a, b: $0.b, normal: vector($0.normal), area: $0.area, leftState: $0.left?.cell,
            rightState: $0.right?.cell)
        },
        walls: w.map {
          .init(
            cell: $0.cell, normal: vector($0.normal), area: $0.area, velocity: vector($0.velocity),
            state: $0.state?.cell)
        }, duration: dt, cfl: cfl)
      return (r.cells, r.wallImpulses, r.wallWork)
    }
  }
  func interval(
    _ cells: [Cell], faces: [FaceInput], walls: [WallInput] = [], time: Double = 0,
    duration: Double? = nil, cfl: Double = 0.4
  ) -> Interval {
    var limit: Double?
    var dt = duration ?? 0
    var phase = "maximumStep"
    do {
      let l = try self.limit(cells, faces, walls, cfl)
      limit = l
      dt = duration ?? (l.isFinite ? 0.001 * l : 0.001)
      phase = "advance"
      let (out, impulses, work) = try step(cells, faces, walls, dt, cfl)
      return Interval(
        time: time, duration: dt, cfl: cfl, limit: l.isFinite ? l : nil,
        limitBits: String(l.bitPattern, radix: 16),
        input: cells.map(NativeCell.init), faces: faces, walls: walls,
        result: out.map(NativeCell.init),
        impulses: impulses.map { [$0.x, $0.y, $0.z] }, work: work, failure: nil, failureStage: nil)
    } catch {
      let prefix: String
      if error is FractionalEulerFlux.Failure
        || error is CompressibleFlow.FractionalEulerFlux.Failure
      {
        prefix = "flux"
      } else if error is PrescribedGasTransport.Failure {
        prefix = "packet"
      } else if error is CompressibleFlow.IdealGasWallRiemann.Failure {
        prefix = "wall"
      } else {
        fatalError("Unexpected failure: \(error)")
      }
      return Interval(
        time: time, duration: dt, cfl: cfl, limit: limit.flatMap { $0.isFinite ? $0 : nil },
        limitBits: limit.map { String($0.bitPattern, radix: 16) },
        input: cells.map(NativeCell.init), faces: faces, walls: walls, result: nil, impulses: nil,
        work: nil,
        failure: prefix + "." + String(describing: error), failureStage: phase)
    }
  }
}

func cases(_ backend: Backend) throws -> [Case] {
  var output: [Case] = []
  let densities = [0.25, 1, 7]
  let pressures = [1.0, 100, 101325]
  let volumes = [1e-6, 1, 1e3]
  let velocities = [SIMD3<Double>.zero, SIMD3(1, -2, 3), SIMD3(100, 50, -25)]
  let normals = [[1.0, 0, 0], [0.6, 0.8, 0], [0, 0, 1]]
  for (di, rho) in densities.enumerated() {
    for (pi, p) in pressures.enumerated() {
      for (vi, u) in velocities.enumerated() {
        for (ni, n) in normals.enumerated() {
          for (si, v) in volumes.enumerated() {
            for traced in 0...1 {
              let cells = [
                Cell(volume: v, density: rho, velocity: u, pressure: p),
                Cell(volume: 2 * v, density: 1.25 * rho, velocity: -0.5 * u, pressure: 0.75 * p),
              ]
              var face = FaceInput(a: 0, b: 1, normal: n, area: 0.7)
              if traced == 1 {
                face.left = NativeCell(
                  Cell(volume: 0.5 * v, density: 0.9 * rho, velocity: u, pressure: 1.2 * p))
                face.right = NativeCell(
                  Cell(volume: 3 * v, density: 1.1 * rho, velocity: -0.5 * u, pressure: 0.8 * p))
              }
              output.append(
                Case(
                  id: "face/\(di)/\(pi)/\(vi)/\(ni)/\(si)/\(traced)", kind: "face", parameters: [:],
                  intervals: [backend.interval(cells, faces: [face])]))
            }
          }
          for (wi, speed) in [-0.5, 0.0, 0.5].enumerated() {
            let w = vector(n) * (speed * sqrt(1.4 * p / rho))
            let cell = Cell(volume: 1, density: rho, velocity: u, pressure: p)
            let wall = WallInput(cell: 0, normal: n, area: 0.7, velocity: [w.x, w.y, w.z])
            output.append(
              Case(
                id: "wall/\(di)/\(pi)/\(vi)/\(ni)/\(wi)", kind: "wall", parameters: [:],
                intervals: [backend.interval([cell], faces: [], walls: [wall])]))
          }
        }
      }
    }
  }
  let cells = [Cell](repeating: .init(volume: 1, density: 1, pressure: 1), count: 2)
  let face = FaceInput(a: 0, b: 1, normal: [1, 0, 0], area: 1)
  func reject(
    _ id: String, _ c: [Cell], _ f: [FaceInput], _ w: [WallInput] = [], _ dt: Double? = nil,
    _ cfl: Double = 0.4
  ) {
    output.append(
      Case(
        id: "failure/" + id, kind: "failure", parameters: [:],
        intervals: [backend.interval(c, faces: f, walls: w, duration: dt, cfl: cfl)]))
  }
  reject("index", cells, [FaceInput(a: -1, b: 1, normal: [1, 0, 0], area: 1)])
  reject("normal", cells, [FaceInput(a: 0, b: 1, normal: [2, 0, 0], area: 1)])
  reject("wall", cells, [], [WallInput(cell: 4, normal: [1, 0, 0], area: 1, velocity: [0, 0, 0])])
  reject("cflLow", cells, [], [], nil, 0)
  reject("cflHigh", cells, [], [], nil, 0.51)
  reject("duration", cells, [face], [], 0)
  reject("unstable", cells, [face], [], (try backend.limit(cells, [face], [], 0.4)).nextUp)
  reject("host", [Cell(volume: 1, amount: SIMD8(1, 0, 0, 0, 0, 0, 0, 0)), cells[1]], [face])
  let trace = NativeCell(Cell(volume: 1, density: 1000, velocity: SIMD3(100, 0, 0), pressure: 1))
  let traced = FaceInput(a: 0, b: 1, normal: [1, 0, 0], area: 1, left: trace, right: trace)
  reject("tracePositivity", cells, [traced], [], try backend.limit(cells, [traced], [], 0.4))
  reject("dryFace", [Cell(volume: 0, amount: .zero), cells[1]], [face])

  for kind in ["acoustic", "contact", "shock"] {
    for n in [32, 64, 128] {
      let h = 1.0 / Double(n)
      let end = kind == "shock" ? 0.05 : 0.15
      var state: [Cell] = []
      let c = sqrt(1.4)
      let eps = 1e-6
      let upstream = Cell(volume: h, density: 1, velocity: SIMD3(3 - 2 * c, 0, 0), pressure: 1)
      let downstream = Cell(
        volume: h, density: 8.0 / 3, velocity: SIMD3(3 - 0.75 * c, 0, 0), pressure: 4.5)
      if kind == "shock" {
        state = [downstream] + (0..<n).map { $0 < n / 4 ? downstream : upstream } + [upstream]
      } else {
        state = (0..<n).map {
          // Exact cell-averaged sine perturbation on [i h, (i+1) h].
          let s =
            (cos(2 * Double.pi * Double($0) * h) - cos(2 * Double.pi * Double($0 + 1) * h))
            / (2 * Double.pi * h)
          if kind == "contact" {
            return Cell(volume: h, density: 1 + 0.1 * s, velocity: SIMD3(0.7, 0, 0), pressure: 1)
          }
          return Cell(
            volume: h, density: 1 + eps * s, velocity: SIMD3(0.2 + eps * c * s, 0, 0),
            pressure: 1 + 1.4 * eps * s)
        }
      }
      let f: [FaceInput] =
        kind == "shock"
        ? (0...n).map { FaceInput(a: $0, b: $0 + 1, normal: [1, 0, 0], area: 1) }
        : (0..<n).map { FaceInput(a: $0, b: ($0 + 1) % n, normal: [1, 0, 0], area: 1) }
      var time = 0.0
      var intervals: [Interval] = []
      while time < end {
        if kind == "shock" {
          state[0] = downstream
          state[n + 1] = upstream
        }
        let dt = min(end - time, try backend.limit(state, f, [], 0.4))
        let interval = backend.interval(state, faces: f, time: time, duration: dt)
        guard let result = interval.result else {
          fatalError("Wave \(kind) failed: \(interval.failure ?? "unknown")")
        }
        intervals.append(interval)
        state = result.map(\.cell)
        time += dt
        guard intervals.count <= 10000 else { fatalError("Nonterminating wave clock") }
      }
      output.append(
        Case(
          id: "\(kind)/\(n)", kind: kind, parameters: ["cells": Double(n), "duration": end],
          intervals: intervals))
    }
  }
  return output
}

@main struct Main {
  static func main() throws {
    let env = ProcessInfo.processInfo.environment
    guard let path = env["CONTINUUMKIT_EULER_OUTPUT"],
      let revision = env["CONTINUUMKIT_CONSUMER_REVISION"]
    else {
      fatalError("Run Scripts/check-euler-flux-consumer.sh")
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let root = URL(fileURLWithPath: path)
    for (name, backend) in [("original", Backend.original), ("shared", Backend.shared)] {
      let result = try cases(backend)
      try encoder.encode(result).write(to: root.appending(path: name + ".json"))
      print("\(name): \(result.count) complete cases")
    }
    let summary = ["candidate": revision, "version": env["CONTINUUMKIT_CONSUMER_VERSION"] ?? ""]
    try encoder.encode(summary).write(to: root.appending(path: "summary.json"))
  }
}
