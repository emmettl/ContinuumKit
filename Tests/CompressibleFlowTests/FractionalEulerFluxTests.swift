import CompressibleFlow
import Foundation
import Testing
import simd

@Suite("Independent prescribed Euler flux contracts")
struct FractionalEulerFluxTests {
  private typealias Cell = PrescribedGasTransport.Cell
  private typealias Flux = FractionalEulerFlux
  private func near(_ actual: Double, _ expected: Double, scale: Double = 1) {
    #expect(abs(actual - expected) <= 2e-12 * max(scale, abs(expected)))
  }

  @Test("SI oblique Euler flux transports momentum and total enthalpy")
  func obliqueFlux() throws {
    let cells = [Cell](
      repeating: .init(
        volume: 1, density: 2,
        velocity: SIMD3(3, 4, 0), pressure: 10), count: 2)
    let result = try Flux.advance(
      cells,
      faces: [.init(a: 0, b: 1, normal: SIMD3(0.6, 0.8, 0), area: 2)], duration: 0.001)
    // E = 50 J/m³, u.n = 5 m/s; F = (10,36,48,0,300), A dt = .002.
    let packet = SIMD8<Double>(0.02, 0.072, 0.096, 0, 0.6, 0, 0, 0)
    for k in 0..<8 {
      near(cells[0].amount[k] - result[0].amount[k], packet[k])
      near(result[1].amount[k] - cells[1].amount[k], packet[k])
    }
  }

  @Test("A stationary discontinuity has the characteristic-speed Rusanov diffusion")
  func dissipativeFlux() throws {
    let cells = [
      Cell(volume: 1, density: 1, pressure: 1),
      Cell(volume: 2, density: 4, pressure: 4),
    ]
    let result = try Flux.advance(
      cells,
      faces: [.init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 1)], duration: 0.01)
    let c = sqrt(1.4)
    // F = (-3c/2, (1+4)/2, 0, 0, -7.5c/2).
    let expected = SIMD8<Double>(-0.015 * c, 0.025, 0, 0, -0.0375 * c, 0, 0, 0)
    for k in 0..<8 { near(cells[0].amount[k] - result[0].amount[k], expected[k]) }
  }

  @Test("The CFL clock uses the incident characteristic, every face and cell volume")
  func characteristicClock() throws {
    let cells = [
      Cell(volume: 0.25, density: 2, velocity: SIMD3(3, 8, 0), pressure: 10),
      Cell(volume: 2, density: 2, velocity: SIMD3(-1, -10, 0), pressure: 10),
    ]
    let faces = [
      Flux.Face(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 2),
      .init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 3),
    ]
    near(try Flux.maximumStep(cells, faces: faces, cfl: 0.5), 0.5 * 0.25 / (5 * (3 + sqrt(7))))
    #expect(try Flux.maximumStep(cells, faces: []) == .infinity)
    #expect(try Flux.maximumStep([], faces: []) == .infinity)
  }

  @Test("Trace fluxes use intensive values while the CFL clock uses host volumes")
  func suppliedTrace() throws {
    let hosts = [Cell](repeating: .init(volume: 1, density: 2, pressure: 10), count: 2)
    let a = Cell(volume: 0.3, density: 2, velocity: SIMD3(3, 4, 0), pressure: 10)
    let b = Cell(volume: 7, density: 2, velocity: SIMD3(3, 4, 0), pressure: 10)
    let faces = [
      Flux.Face(
        a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 1,
        leftState: a, rightState: b)
    ]
    let result = try Flux.advance(hosts, faces: faces, duration: 0.001)
    near(try Flux.maximumStep(hosts, faces: faces), 0.4 / (3 + sqrt(7)))
    for (k, expected) in [0.006, 0.028, 0.024, 0, 0.18].enumerated() {
      near(hosts[0].amount[k] - result[0].amount[k], expected)
    }
  }

  @Test("Face reversal preserves the paired extensive result")
  func reversal() throws {
    let cells = [
      Cell(volume: 0.8, density: 2, velocity: SIMD3(3, -1, 2), pressure: 10),
      Cell(volume: 1.3, density: 1, velocity: SIMD3(-2, 4, 1), pressure: 3),
    ]
    let a = try Flux.advance(
      cells,
      faces: [.init(a: 0, b: 1, normal: SIMD3(0.6, 0.8, 0), area: 0.2)], duration: 0.001)
    let b = try Flux.advance(
      cells,
      faces: [.init(a: 1, b: 0, normal: SIMD3(-0.6, -0.8, 0), area: 0.2)], duration: 0.001)
    #expect(a == b)
  }

  @Test("A supplied wall trace determines pressure and signal but preserves host identity")
  func wallTrace() throws {
    let host = Cell(volume: 0.5, density: 1, pressure: 1)
    let trace = Cell(volume: 7, density: 2, velocity: SIMD3(0, 3, 0), pressure: 10)
    let wall = Flux.Wall(cell: 0, normal: SIMD3(1, 0, 0), area: 1, state: trace)
    let result = try Flux.advanceWithWalls([host], faces: [], walls: [wall], duration: 0.001)
    near(try Flux.maximumStep([host], faces: [], walls: [wall]), 0.4 * 0.5 / sqrt(7))
    near(result.wallImpulses[0].x, 0.01)
    #expect(result.cells[0].volume == host.volume)
    #expect(result.cells[0].amount[0] == host.amount[0])
    #expect(result.cells[0].amount[4] == host.amount[4] && result.wallWork == [0])
  }

  @Test("Independent Mach-two shock relations determine wall impulse, work and clock")
  func shockWall() throws {
    let c = sqrt(1.4)
    let wallSpeed = 0.3
    // For M=2, p*/p=4.5 and velocity toward the wall = (5/4)c.
    let cell = Cell(volume: 1, density: 1, velocity: SIMD3(wallSpeed + 1.25 * c, 2, 0), pressure: 1)
    let wall = Flux.Wall(cell: 0, normal: SIMD3(1, 0, 0), area: 2, velocity: SIMD3(wallSpeed, 7, 0))
    let result = try Flux.advanceWithWalls([cell], faces: [], walls: [wall], duration: 0.001)
    near(result.wallImpulses[0].x, 0.009)
    near(result.wallWork[0], 0.0027)
    near(result.cells[0].amount[4] - cell.amount[4], -0.0027)
    near(result.cells[0].volume, 1.0006)
    near(try Flux.maximumStep([cell], faces: [], walls: [wall]), 0.4 / (2 * (3.25 * c + wallSpeed)))
  }

  @Test("A separating wall uses the isentropic rarefaction pressure and vacuum limit")
  func rarefactionWall() throws {
    let c = sqrt(1.4)
    let wall = Flux.Wall(cell: 0, normal: SIMD3(1, 0, 0), area: 1)
    let cell = Cell(volume: 1, density: 1, velocity: SIMD3(-c, 0, 0), pressure: 1)
    let result = try Flux.advanceWithWalls([cell], faces: [], walls: [wall], duration: 0.001)
    near(result.wallImpulses[0].x, 0.001 * pow(0.8, 7))
    #expect(result.wallWork == [0])
    let vacuum = Cell(volume: 1, density: 1, velocity: SIMD3(-6 * c, 0, 0), pressure: 1)
    let free = try Flux.advanceWithWalls([vacuum], faces: [], walls: [wall], duration: 0.001)
    #expect(free.cells == [vacuum] && free.wallImpulses == [.zero])
  }

  @Test("Paired faces conserve and prescribed walls supply opposite momentum and work")
  func ledger() throws {
    let cells = [
      Cell(volume: 1, density: 1, velocity: SIMD3(0.2, 1, -2), pressure: 1),
      Cell(volume: 0.5, density: 2, velocity: SIMD3(-0.1, 3, 1), pressure: 2),
    ]
    let walls = [
      Flux.Wall(cell: 0, normal: SIMD3(-1, 0, 0), area: 0.3, velocity: SIMD3(-0.2, 4, 0)),
      .init(cell: 1, normal: SIMD3(1, 0, 0), area: 0.3, velocity: SIMD3(0.1, 3, 0)),
    ]
    let result = try Flux.advanceWithWalls(
      cells,
      faces: [.init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 0.3)], walls: walls, duration: 0.001)
    let before = cells.reduce(SIMD8<Double>.zero) { $0 + $1.amount }
    let after = result.cells.reduce(SIMD8<Double>.zero) { $0 + $1.amount }
    near(after[0], before[0])
    for k in 0..<3 {
      near(after[k + 1] - before[k + 1], -result.wallImpulses.reduce(0) { $0 + $1[k] })
    }
    near(after[4] - before[4], -result.wallWork.reduce(0, +))
    for k in 5..<8 { #expect(after[k] == 0) }
  }

  @Test("Arbitrary traces can fail below the CFL bound without floors or mutation")
  func traceRejection() throws {
    let cells = [Cell](repeating: .init(volume: 1, density: 1, pressure: 1), count: 2)
    let trace = Cell(volume: 1, density: 1000, velocity: SIMD3(100, 0, 0), pressure: 1)
    let face = Flux.Face(
      a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 1, leftState: trace, rightState: trace)
    let step = try Flux.maximumStep(cells, faces: [face])
    #expect(step.isFinite && step > 0)
    #expect(throws: PrescribedGasTransport.Failure.invalidState) {
      try Flux.advance(cells, faces: [face], duration: step)
    }
    #expect(cells[0].amount[0] == 1 && cells[1].amount[0] == 1)
  }

  @Test("Invalid geometry, clocks and traces retain distinct transactional failures")
  func failureContracts() throws {
    let cells = [Cell](repeating: .init(volume: 1, density: 1, pressure: 1), count: 2)
    for face in [
      Flux.Face(a: -1, b: 1, normal: SIMD3(1, 0, 0), area: 1),
      .init(a: 0, b: 0, normal: SIMD3(1, 0, 0), area: 1),
      .init(a: 0, b: 1, normal: SIMD3(2, 0, 0), area: 1),
      .init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: -1),
    ] {
      #expect(throws: Flux.Failure.invalidFace) { try Flux.maximumStep(cells, faces: [face]) }
    }
    for cfl in [0.0, 0.51, Double.nan, Double.infinity] {
      #expect(throws: Flux.Failure.invalidStep) { try Flux.maximumStep(cells, faces: [], cfl: cfl) }
    }
    for dt in [0.0, -1, Double.nan, Double.infinity] {
      #expect(throws: Flux.Failure.invalidStep) { try Flux.advance(cells, faces: [], duration: dt) }
    }
    let face = Flux.Face(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 1)
    let limit = try Flux.maximumStep(cells, faces: [face])
    #expect(throws: Flux.Failure.unstableStep) {
      try Flux.advance(cells, faces: [face], duration: limit.nextUp)
    }
    #expect(throws: Flux.Failure.invalidWall) {
      try Flux.maximumStep(
        cells, faces: [],
        walls: [.init(cell: 0, normal: SIMD3(1, 0, 0), area: 1, velocity: SIMD3(.nan, 0, 0))])
    }
    let bad = Cell(volume: 1, amount: SIMD8(1, 0, 0, 0, 0, 0, 0, 0))
    #expect(throws: PrescribedGasTransport.Failure.invalidState) {
      try Flux.maximumStep(
        cells, faces: [.init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 1, leftState: bad)])
    }
  }

  @Test("Dry isolated cells and zero-area validated interfaces carry no flux")
  func inactiveGeometry() throws {
    let dry = Cell(volume: 0, amount: .zero)
    #expect(try Flux.advance([dry], faces: [], duration: 1) == [dry])
    let cells = [Cell](repeating: .init(volume: 1, density: 1, pressure: 1), count: 2)
    let result = try Flux.advanceWithWalls(
      cells,
      faces: [.init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 0)],
      walls: [.init(cell: 0, normal: SIMD3(1, 0, 0), area: 0)], duration: 1)
    #expect(result.cells == cells && result.wallImpulses == [.zero] && result.wallWork == [0])
    #expect(throws: Flux.Failure.invalidFace) {
      try Flux.maximumStep(
        [dry, cells[0]], faces: [.init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 0)])
    }
  }

  @Test("An unrepresentable incident characteristic rejects rather than inventing a clock")
  func characteristicOverflow() throws {
    let cells = [Cell](repeating: .init(volume: 1, density: 1e-300, pressure: 1e307), count: 2)
    #expect(throws: Flux.Failure.invalidFace) {
      try Flux.maximumStep(cells, faces: [.init(a: 0, b: 1, normal: SIMD3(1, 0, 0), area: 1)])
    }
  }
}
