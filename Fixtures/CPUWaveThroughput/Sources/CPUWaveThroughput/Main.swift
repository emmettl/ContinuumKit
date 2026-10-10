import Darwin
import Foundation
import LinearAcoustics

protocol Stepper {
  var slabCount: Int { get }
  func advance(
    source: PreparedPressureSource, amplitudes: [Float], observing: PreparedWaveObservation
  ) throws -> [WaveObservationFrame]
  func snapshot() throws -> WaveSnapshot
}
extension CPUWaveStepper: Stepper {}
extension Alpha8CPUWaveStepper: Stepper { var slabCount: Int { 1 } }
struct Timing: Codable {
  let mode: String, repetition: Int, steps: Int, slabs: Int
  let wallSeconds, cpuSeconds: Double
  let fieldsFile: String
}
struct Configuration: Codable {
  let dimensions: [Int], spacing: [Double]
  let speed, dt: Double
  let activeMask: String, initialFields: String
  let wallTerm: Float
  let sourceCells: [Int], sourceWeights: [Float]
  let receiverCells: [Int]
  let velocityAxis: [Double]
  let timings: [Timing]
}
struct Fields: Codable {
  let step: Int
  let pressureTime, velocityTime: Double
  let values: [[Float]], bits: [[UInt32]]
  let pressure: [[Double]], velocity: [[Double?]]
  let pressureBits: [[UInt64]], velocityBits: [[UInt64?]]
}
enum Failure: Error { case badArguments, mismatch }
@main struct Main {
  static func cpuSeconds() -> Double {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return .nan }
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
      + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
  }
  static func arrays(_ h: WaveSnapshot) -> [[Float]] {
    [h.pressureOverDensity, h.velocityX, h.velocityY, h.velocityZ]
  }
  static func write<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    try encoder.encode(value).write(to: url)
  }
  static func main() throws {
    let args = CommandLine.arguments
    guard let flag = args.firstIndex(of: "--output"), flag + 1 < args.count else {
      throw Failure.badArguments
    }
    let output = URL(fileURLWithPath: args[flag + 1])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    var reports: [Configuration] = []
    let dimensions: [SIMD3<Int>] = [[24, 18, 9], [47, 35, 18], [105, 79, 40]]
    for d in dimensions {
      let count = d.x * d.y * d.z
      let plane = d.x * d.y
      let spacing = SIMD3<Double>(8, 6, 3) / SIMD3<Double>(d)
      let speed = 343.21462268256795
      let limit = 0.95 / (speed * (1 / (spacing * spacing)).sum().squareRoot())
      var decimation = 1
      while Double(2 * decimation) / 48000 <= limit { decimation *= 2 }
      let dt = Double(decimation) / 48000
      let wall: Float = 0.003
      var faces = [Float](repeating: -1, count: 6 * count)
      for at in 0..<count {
        let xyz = [at % d.x, at / d.x % d.y, at / plane]
        for axis in 0..<3 {
          if xyz[axis] == 0 { faces[2 * axis * count + at] = wall }
          if xyz[axis] == d[axis] - 1 { faces[(2 * axis + 1) * count + at] = wall }
        }
      }
      let grid = try PreparedWaveGrid(
        dimensions: d, spacing: spacing, soundSpeed: speed, density: 1, timeStep: dt,
        activeCells: Array(repeating: 1, count: count), boundaryTerms: faces)
      let zero = [Float](repeating: 0, count: count)
      let initial = WaveInitialFields(
        pressureOverDensity: zero, velocityX: zero, velocityY: zero, velocityZ: zero)
      let cell = d.x / 3 + d.x * (d.y / 3 + d.y * (d.z / 2))
      let sourceCells = [
        cell, cell + 1, cell + d.x, cell + d.x + 1, cell + plane, cell + plane + 1,
        cell + plane + d.x, cell + plane + d.x + 1,
      ]
      let source = try PreparedPressureSource(
        grid: grid, cellIndices: sourceCells, coefficients: Array(repeating: 0.015625, count: 8))
      let receiver = 2 * d.x / 3 + d.x * (d.y / 2 + d.y * (d.z / 2))
      let observation = try PreparedWaveObservation(
        grid: grid,
        receivers: [
          WaveReceiverStencil(
            pressureCells: Array(repeating: receiver, count: 8),
            pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0]),
          WaveReceiverStencil(
            pressureCells: Array(repeating: receiver + 1, count: 8),
            pressureWeights: [1, 0, 0, 0, 0, 0, 0, 0], velocityCell: receiver + 1,
            velocityAxis: [0.4, -0.7, 0.2]),
        ])
      func create(_ mode: String) throws -> any Stepper {
        if mode == "alpha8" { return try Alpha8CPUWaveStepper(grid: grid, initialFields: initial) }
        return try CPUWaveStepper(
          grid: grid, initialFields: initial,
          execution: mode == "serial" ? .serial : .parallel(slabs: min(16, d.z)))
      }
      func run(_ mode: String, _ steps: Int) throws -> (Double, Double, Int, Fields) {
        let s = try create(mode)
        var frames: [WaveObservationFrame] = []
        let clock = ContinuousClock()
        let start = clock.now
        let cpu = cpuSeconds()
        for first in stride(from: 0, to: steps, by: 64) {
          let amplitudes = (first..<min(first + 64, steps)).map {
            Float(sin(2 * Double.pi * 37 * (Double($0) + 0.5) * dt))
          }
          frames += try s.advance(source: source, amplitudes: amplitudes, observing: observation)
        }
        let duration = start.duration(to: clock.now).components
        let wall = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        let cpuTime = cpuSeconds() - cpu
        let h = try s.snapshot()
        let a = arrays(h)
        return (
          wall, cpuTime, s.slabCount,
          Fields(
            step: h.pressureStepIndex, pressureTime: h.pressureTime, velocityTime: h.velocityTime,
            values: a, bits: a.map { $0.map(\.bitPattern) },
            pressure: frames.map(\.pressureOverDensity), velocity: frames.map(\.projectedVelocity),
            pressureBits: frames.map { $0.pressureOverDensity.map(\.bitPattern) },
            velocityBits: frames.map { $0.projectedVelocity.map { $0?.bitPattern } })
        )
      }
      for mode in ["alpha8", "serial", "parallel"] { _ = try run(mode, 64) }
      var timings: [Timing] = []
      let stem = "\(d.x)x\(d.y)x\(d.z)"
      let directory = output.appendingPathComponent(stem)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      for repetition in 0..<3 {
        var results: [String: Fields] = [:]
        let modes = ["alpha8", "serial", "parallel"]
        for offset in 0..<3 {
          let mode = modes[(offset + repetition) % 3]
          let (wall, cpu, slabs, fields) = try run(mode, 1024)
          let name = stem + "/\(mode)-\(repetition).json"
          try write(fields, to: output.appendingPathComponent(name))
          results[mode] = fields
          timings.append(
            Timing(
              mode: mode, repetition: repetition, steps: 1024, slabs: slabs, wallSeconds: wall,
              cpuSeconds: cpu,
              fieldsFile: name))
        }
        for mode in ["serial", "parallel"] {
          guard results[mode]!.bits == results["alpha8"]!.bits,
            results[mode]!.pressureBits == results["alpha8"]!.pressureBits,
            results[mode]!.velocityBits == results["alpha8"]!.velocityBits
          else { throw Failure.mismatch }
        }
      }
      reports.append(
        Configuration(
          dimensions: [d.x, d.y, d.z], spacing: [spacing.x, spacing.y, spacing.z], speed: speed,
          dt: dt, activeMask: "all active", initialFields: "all four fields zero", wallTerm: wall,
          sourceCells: sourceCells, sourceWeights: source.coefficients,
          receiverCells: [receiver, receiver + 1], velocityAxis: [0.4, -0.7, 0.2], timings: timings)
      )
      print("PASS alpha8/serial/parallel complete native fields and receiver histories", stem)
    }
    try write(reports, to: output.appendingPathComponent("timings.json"))
  }
}
