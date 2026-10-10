import CompressibleFlow
import Foundation

struct Case: Codable {
  let density, pressure, normalVelocity, gamma: Double
  let originalPressure, originalSignalSpeed: Double
  let sharedPressure, sharedSignalSpeed: Double
  let vacuum: Bool
  let pressureBits, signalSpeedBits: UInt64
}

@main
enum GasWallConsumer {
  static func main() throws {
    var cases: [Case] = []
    for gamma in [1.1, 1.4, 5.0 / 3, 3] {
      for density in [0.25, 1.225, 7] {
        for pressure in [0.01, 101325, 1e7] {
          let c = sqrt(gamma * pressure / density)
          for mach in [-8.0, -3, -1, -0.5, -0.1, 0, 0.001, 0.5, 1, 5] {
            let velocity = mach * c
            let old = try IdealGasWallRiemann.solve(
              density: density, pressure: pressure, normalVelocity: velocity, gamma: gamma)
            let new = try CompressibleFlow.IdealGasWallRiemann.solve(
              density: density, pressure: pressure, normalVelocity: velocity, gamma: gamma)
            guard old.pressure.bitPattern == new.pressure.bitPattern,
              old.signalSpeed.bitPattern == new.signalSpeed.bitPattern, old.vacuum == new.vacuum
            else { throw Failure.mismatch }
            cases.append(
              Case(
                density: density, pressure: pressure, normalVelocity: velocity, gamma: gamma,
                originalPressure: old.pressure, originalSignalSpeed: old.signalSpeed,
                sharedPressure: new.pressure, sharedSignalSpeed: new.signalSpeed,
                vacuum: new.vacuum,
                pressureBits: new.pressure.bitPattern, signalSpeedBits: new.signalSpeed.bitPattern))
          }
        }
      }
    }
    guard cases.count == 360 else { throw Failure.mismatch }
    let limit = try CompressibleFlow.IdealGasWallRiemann.solve(
      density: 1, pressure: 1, normalVelocity: -0.2, gamma: (1.0).nextUp)
    guard abs(limit.pressure - exp(-0.2)) < 1e-12 else { throw Failure.mismatch }
    let environment = ProcessInfo.processInfo.environment
    guard let output = environment["CONTINUUMKIT_GAS_OUTPUT"] else { throw Failure.missingOutput }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(cases).write(
      to: URL(fileURLWithPath: output).appendingPathComponent("cases.json"))
    let summary: [String: String] = [
      "candidate": environment["CONTINUUMKIT_CONSUMER_REVISION"] ?? "unknown",
      "version": environment["CONTINUUMKIT_CONSUMER_VERSION"] ?? "",
      "completeSourceCases": "360", "ordinaryBitMismatches": "0",
      "nearIsothermalPressure": String(limit.pressure),
      "scope": "uniform planar ideal-gas wall reference; no transport/app/Metal dependency",
    ]
    try encoder.encode(summary).write(
      to: URL(fileURLWithPath: output).appendingPathComponent("summary.json"))
    print(
      "PASS fetched CompressibleFlow public API: 360 exact original cases and independent near-isothermal limit"
    )
  }
  enum Failure: Error { case mismatch, missingOutput }
}
