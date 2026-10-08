import BenchmarkSupport
import Foundation
import Testing

@Suite("Acoustic benchmark contract")
struct AcousticBenchmarkTests {
  let environment = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:],
    hardware: "test", toolchain: "test", operatingSystem: "test")

  @Test("Compact profile and Neumann image have independent golden states")
  func golden() throws {
    let c = try AcousticCase.standard()[1]
    #expect(abs(c.profile(at: c.centreM) - 1) < 1e-15)
    #expect(abs(c.profile(at: c.centreM + c.halfWidthM / 2) - 0.25) < 1e-15)
    #expect(c.profile(at: c.centreM + c.halfWidthM) == 0)
    let wall = AcousticOracle.continuum(c, xM: c.lengthM, timeS: c.wallHitTimeS)
    #expect(abs(wall.pressurePa - 2) < 1e-14 && abs(wall.velocityMps) < 1e-14)
    let reflected = AcousticOracle.continuum(c, xM: 0.15, timeS: c.durationS)
    #expect(abs(reflected.pressurePa - 1) < 1e-14)
    #expect(abs(reflected.velocityMps + 1 / 400.0) < 1e-14)
  }

  @Test("Continuum reference obeys both first-order acoustic equations")
  func equations() throws {
    let c = try AcousticCase.standard()[0]
    let t = 0.00005
    let x = c.centreM + c.halfWidthM * 0.3 + c.soundSpeedMps * t
    func residual(_ h: Double) -> Double {
      let a = AcousticOracle.continuum(c, xM: x, timeS: t + h / c.soundSpeedMps)
      let b = AcousticOracle.continuum(c, xM: x, timeS: t - h / c.soundSpeedMps)
      let left = AcousticOracle.continuum(c, xM: x - h, timeS: t)
      let right = AcousticOracle.continuum(c, xM: x + h, timeS: t)
      return abs(
        (a.pressurePa - b.pressurePa) * c.soundSpeedMps / (2 * h)
          + c.densityKgM3 * c.soundSpeedMps * c.soundSpeedMps
          * (right.velocityMps - left.velocityMps) / (2 * h))
        + abs(
          (a.velocityMps - b.velocityMps) * c.soundSpeedMps / (2 * h)
            + (right.pressurePa - left.pressurePa) / (2 * h * c.densityKgM3))
    }
    #expect(residual(1e-5) < 1e-6)
  }

  @Test("Continuum energy agrees with the cos-eight integral before, during and after reflection")
  func energy() throws {
    let c = try AcousticCase.standard()[1]
    let n = 1024
    let dx = c.lengthM / Double(n)
    for time in [0, c.wallHitTimeS / 2, c.wallHitTimeS, c.durationS] {
      var integral = 0.0
      for i in 0...n {
        let s = AcousticOracle.continuum(c, xM: Double(i) * dx, timeS: time)
        let e =
          s.pressurePa * s.pressurePa / (2 * c.densityKgM3 * c.soundSpeedMps * c.soundSpeedMps)
          + c.densityKgM3 * s.velocityMps * s.velocityMps / 2
        integral += e * Double(i == 0 || i == n ? 1 : i % 2 == 0 ? 2 : 4)
      }
      #expect(abs(integral * dx / 3 / c.referenceEnergyJPerM2 - 1) < 1e-8)
    }
  }

  @Test("Two-cell spatial lattice has an independent closed-form oscillator solution")
  func latticeGolden() throws {
    let c = try AcousticCase.standard()[0]
    let dx = c.lengthM / 2
    let oracle = try AcousticOracle.SpatialLattice(c, cells: 2, spacingM: dx)
    let omega = sqrt(2.0) * c.soundSpeedMps / dx
    let quarter = oracle.fields(timeS: .pi / (2 * omega))
    #expect(quarter.pressurePa.allSatisfy { abs($0 - 0.125) < 1e-14 })
    #expect(abs(quarter.velocityMps[1] - 0.25 / sqrt(2.0) / 400) < 1e-14)
    let half = oracle.fields(timeS: .pi / omega)
    #expect(abs(half.pressurePa[0]) < 1e-14 && abs(half.pressurePa[1] - 0.25) < 1e-14)
    #expect(quarter.velocityMps[0] == 0 && quarter.velocityMps[2] == 0)
  }

  func numericalHistory(_ c: AcousticCase, _ r: AcousticResolution) -> AcousticHistory {
    let dx = c.lengthM / Double(r.cells)
    let dt = c.durationS / Double(r.steps)
    var (p, u) = AcousticOracle.initialFields(c, cells: r.cells, spacingM: dx, timeStepS: dt)
    var frames: [AcousticFrame] = []
    let captures = Set(r.captureSteps(for: c))
    for step in 0...r.steps {
      if captures.contains(step) {
        frames.append(AcousticFrame(step: step, pressurePa: p, normalVelocityMps: u))
      }
      if step == r.steps { break }
      for i in 1..<r.cells { u[i] -= dt * (p[i] - p[i - 1]) / (c.densityKgM3 * dx) }
      for i in 0..<r.cells {
        p[i] -= c.densityKgM3 * c.soundSpeedMps * c.soundSpeedMps * dt * (u[i + 1] - u[i]) / dx
      }
    }
    return AcousticHistory(spacingM: dx, timeStepS: dt, frames: frames)
  }
  @Test("Space and time refine independently against their analytic references")
  func refinement() throws {
    for c in try AcousticCase.standard() {
      let results = try AcousticResolution.standard(for: c).map { r in
        try AcousticResult.evaluate(
          model: "test-only-staggered-control", caseSpecification: c, resolution: r,
          environment: environment, runtimeS: 0, history: numericalHistory(c, r))
      }
      for axis in [AcousticResolution.Axis.space, .time] {
        let orders = try AcousticCommand.check(results.filter { $0.resolution.axis == axis })
        #expect(orders.count == 2)
      }
      #expect(results.allSatisfy { $0.errors!.maximumDiscreteEnergyDrift < 1e-12 })
    }
  }

  @Test("Conservation alone cannot pass a pulse with the wrong speed")
  func wrongSpeed() throws {
    let c = try AcousticCase.standard()[0]
    let results = try AcousticResolution.standard(for: c).filter { $0.axis == .space }.map { r in
      let dx = c.lengthM / Double(r.cells)
      let dt = c.durationS / Double(r.steps)
      let frames = r.captureSteps(for: c).map { step in
        let t = Double(step) * dt
        return AcousticFrame(
          step: step,
          pressurePa: (0..<r.cells).map {
            AcousticOracle.continuum(c, xM: (Double($0) + 0.5) * dx, timeS: t / 2).pressurePa
          },
          normalVelocityMps: (0...r.cells).map {
            AcousticOracle.continuum(c, xM: Double($0) * dx, timeS: (t - dt / 2) / 2).velocityMps
          })
      }
      return try AcousticResult.evaluate(
        model: "wrong-speed", caseSpecification: c, resolution: r,
        environment: environment, runtimeS: 0,
        history: AcousticHistory(spacingM: dx, timeStepS: dt, frames: frames))
    }
    #expect(results.last!.errors!.pressureRelativeL2 > 0.5)
    #expect(throws: BenchmarkFailure.self) { try AcousticCommand.check(results) }
  }

  @Test("Missing fields, clock mismatch and unsupported required cases cannot pass")
  func malformed() throws {
    let c = try AcousticCase.standard()[0]
    let r = AcousticResolution.standard(for: c)[0]
    let h = numericalHistory(c, r)
    #expect(throws: BenchmarkFailure.self) {
      try AcousticResult.evaluate(
        model: "missing", caseSpecification: c, resolution: r,
        environment: environment, runtimeS: 0,
        history: AcousticHistory(
          spacingM: h.spacingM, timeStepS: h.timeStepS, frames: Array(h.frames.dropLast())))
    }
    #expect(throws: BenchmarkFailure.self) {
      try AcousticResult.evaluate(
        model: "wrong-clock", caseSpecification: c, resolution: r,
        environment: environment, runtimeS: 0,
        history: AcousticHistory(spacingM: h.spacingM, timeStepS: h.timeStepS * 2, frames: h.frames)
      )
    }
    var overflowFrames = h.frames
    var overflowPressure = overflowFrames[0].pressurePa
    overflowPressure[0] = Double.greatestFiniteMagnitude
    overflowFrames[0] = AcousticFrame(
      step: 0, pressurePa: overflowPressure, normalVelocityMps: h.frames[0].normalVelocityMps)
    #expect(throws: BenchmarkFailure.self) {
      try AcousticResult.evaluate(
        model: "overflow", caseSpecification: c, resolution: r, environment: environment,
        runtimeS: 0,
        history: AcousticHistory(
          spacingM: h.spacingM, timeStepS: h.timeStepS, frames: overflowFrames))
    }
    #expect(throws: BenchmarkFailure.self) {
      try AcousticCommand.check([
        AcousticResult.unavailable(
          model: "unsupported", status: "unsupported", reason: "no rigid wall",
          caseSpecification: c, resolution: r, environment: environment)
      ])
    }
  }

  @Test("Versioned cases reject invalid parameters and unsupported return-to-left-wall times")
  func invalid() throws {
    #expect(throws: BenchmarkFailure.self) {
      try AcousticCase(id: "bad", kind: .travellingPulse, densityKgM3: 0, durationS: 0.1 / 320)
    }
    #expect(throws: BenchmarkFailure.self) {
      try AcousticCase(id: "bad", kind: .rigidWall, durationS: 0.5 / 320)
    }
    let data = try JSONEncoder().encode(AcousticCase.standard()[0])
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object["version"] = 2
    let decoded = try JSONDecoder().decode(
      AcousticCase.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(throws: BenchmarkFailure.self) { try decoded.validate() }
  }

  @Test("JSON/CSV retain both spatial staggers and their declared clocks")
  func reports() throws {
    let c = try AcousticCase.standard()[0]
    let r = AcousticResolution.standard(for: c)[0]
    let result = try AcousticResult.evaluate(
      model: "fixture", caseSpecification: c, resolution: r, environment: environment,
      runtimeS: 0, history: numericalHistory(c, r))
    let decoded = try JSONDecoder().decode(AcousticResult.self, from: JSONEncoder().encode(result))
    #expect(decoded.history!.frames.count == r.captureSteps(for: c).count)
    #expect(decoded.fieldCSV.contains("normal_velocity,0,0.0,0.0,m/s"))
    #expect(
      decoded.fieldCSV.split(separator: "\n").count == 1 + r.captureSteps(for: c).count
        * (2 * r.cells + 1))
  }
}
