import Foundation

public struct TiltedPulseHistory: Codable, Sendable {
  public let fields: RigidModeHistory, inside: [UInt8], faces: [Float], layoutFaces: [Float]
  public let layoutDt, materialImpedance: Double
  public let wallCells: [Int], wallPressures: [[Double]]?, dissipation: [Double]?,
    patchDissipation: [Double]
  public init(
    fields: RigidModeHistory, inside: [UInt8], faces: [Float], layoutFaces: [Float],
    layoutDt: Double, materialImpedance: Double, wallCells: [Int], wallPressures: [[Double]]?,
    dissipation: [Double]?, patchDissipation: [Double]
  ) {
    self.fields = fields
    self.inside = inside
    self.faces = faces
    self.layoutFaces = layoutFaces
    self.layoutDt = layoutDt
    self.materialImpedance = materialImpedance
    self.wallCells = wallCells
    self.wallPressures = wallPressures
    self.dissipation = dissipation
    self.patchDissipation = patchDissipation
  }
}
public struct TiltedPulseErrors: Codable, Sendable {
  public let fieldL2: [Double], maxPressure: Double, maxVelocity: Double
  public let energyBudget: Double?, globalWorkError: Double?, patchWorkError: Double
  public let initialEnergyError, initialStateError, boundaryVelocity, inactivePreservation, zeroZ,
    areaRelativeError, coefficientLayoutError, geometryVolumeError: Double
  public let reflectedCoefficient, referenceCoefficient, continuumCoefficient, pulseShift,
    referenceShift, patchWorkJ, referencePatchWorkJ: Double
}
public struct TiltedPulseResult: Codable, Sendable {
  public let schemaVersion: Int, model: String, status: String, reference: String, reason: String?
  public let specification: TiltedPulseCase, resolution: TiltedPulseResolution?,
    environment: BenchmarkEnvironment, runtime: Double
  public let history: TiltedPulseHistory?, errors: TiltedPulseErrors?
  public static func evaluate(
    model: String, c: TiltedPulseCase, r: TiltedPulseResolution, environment: BenchmarkEnvironment,
    h: TiltedPulseHistory, runtime: Double, reference: Bool = false
  ) throws -> Self {
    let grid = try TiltedPulseGrid(c, r)
    let dt = h.fields.dt
    let volume = grid.spacing.reduce(1, *)
    guard runtime.isFinite, runtime >= 0, dt.isFinite, dt > 0,
      abs(dt * Double(r.steps) / c.duration - 1) < 1e-6,
      h.inside == grid.inside, h.faces.count == grid.faceKinds.count,
      h.layoutFaces.count == grid.faceKinds.count,
      h.faces.allSatisfy(\.isFinite), h.layoutFaces.allSatisfy(\.isFinite), h.layoutDt.isFinite,
      h.layoutDt > 0,
      h.materialImpedance.isFinite, abs(h.materialImpedance / c.impedance - 1) < 1e-6,
      h.fields.spacing.count == 3,
      (0..<3).allSatisfy({ abs(h.fields.spacing[$0] / grid.spacing[$0] - 1) < 1e-6 }),
      h.fields.frames.map(\.step) == r.captures,
      h.fields.frames.allSatisfy({ f in
        (0...3).allSatisfy {
          f.fields[$0].count == grid.shape($0).reduce(1, *) && f.fields[$0].allSatisfy(\.isFinite)
        }
      }),
      h.wallCells == grid.wallCells, h.patchDissipation.count == r.captures.count,
      h.patchDissipation.first == 0,
      h.patchDissipation.allSatisfy({ $0.isFinite && $0 >= 0 }),
      zip(h.patchDissipation.dropFirst(), h.patchDissipation).allSatisfy({ $0 + 1e-18 >= $1 })
    else { throw BenchmarkFailure.invalidSamples }
    let ideal = grid.faces(dt: h.layoutDt)
    var area = 0.0
    var coefficientError = 0.0
    for index in grid.faceKinds.indices {
      let kind = grid.faceKinds[index]
      let raw = Double(h.layoutFaces[index])
      let scaled = Double(h.faces[index])
      if kind < 0 {
        guard raw == -1 && scaled == -1 else { throw BenchmarkFailure.invalidSamples }
      } else if kind == 0 {
        guard raw == 0 && scaled == 0 else { throw BenchmarkFailure.invalidSamples }
      } else {
        guard raw > 0, abs(scaled - raw * dt / h.layoutDt) < max(1e-12, abs(scaled) * 2e-6) else {
          throw BenchmarkFailure.invalidSamples
        }
        coefficientError = max(coefficientError, abs(raw / Double(ideal[index]) - 1))
        area += 2 * raw * volume * c.impedance / (c.speed * h.layoutDt)
      }
    }
    guard coefficientError < 2e-6 else { throw BenchmarkFailure.invalidSamples }
    let expected = try TiltedPulseOracle.history(c, r, faces: h.faces, dt: dt)
    let initial = try TiltedPulseOracle.initial(c, r, dt: dt)
    let rates = try grid.rates(faces: h.faces, dt: dt)
    if !reference {
      guard let trace = h.wallPressures, let global = h.dissipation,
        global.count == r.captures.count, global.first == 0,
        global.allSatisfy({ $0.isFinite && $0 >= 0 }),
        zip(global.dropFirst(), global).allSatisfy({ $0 + 1e-18 >= $1 }),
        trace.count == r.steps + 1,
        trace.allSatisfy({ $0.count == h.wallCells.count && $0.allSatisfy(\.isFinite) })
      else { throw BenchmarkFailure.invalidSamples }
      var work = 0.0
      var patch = 0.0
      var capture = 0
      for step in 0...r.steps {
        if step > 0 {
          for (i, cell) in h.wallCells.enumerated() {
            let energy =
              dt * volume * pow((trace[step - 1][i] + trace[step][i]) / 2, 2)
              / (c.density * c.speed * c.speed)
            work += energy * rates.total[cell]
            patch += energy * rates.patch[cell]
          }
        }
        if r.captures[capture] == step {
          guard abs(global[capture] - work) / c.energy < 1e-9,
            abs(h.patchDissipation[capture] - patch) / c.patchEnergy < 1e-9
          else { throw BenchmarkFailure.invalidSamples }
          for (i, cell) in h.wallCells.enumerated() {
            guard abs(trace[step][i] - h.fields.frames[capture].p[cell]) < 1e-6 else {
              throw BenchmarkFailure.invalidSamples
            }
          }
          if capture + 1 < r.captures.count { capture += 1 }
        }
      }
    } else {
      guard h.wallPressures == nil else { throw BenchmarkFailure.invalidSamples }
    }
    var squares = [Double](repeating: 0, count: 3)
    var norms = squares
    var maxP = 0.0
    var maxV = 0.0
    var boundary = 0.0
    var inactive = 0.0
    var zeroZ = 0.0
    var initialError = 0.0
    var budget = 0.0
    var patchError = 0.0
    var globalError = 0.0
    var e0: Double?
    for (capture, frame) in h.fields.frames.enumerated() {
      for field in 0...3 {
        for index in frame.fields[field].indices {
          let value = frame.fields[field][index]
          let scale = field == 0 ? 1 / c.amplitude : c.density * c.speed / c.amplitude
          if field == 3 { zeroZ = max(zeroZ, abs(value) * scale) }
          if !grid.openFields[field][index] {
            if field == 0 {
              inactive = max(inactive, abs(value - c.inactivePressure) / c.amplitude)
            } else {
              boundary = max(boundary, abs(value) * scale)
            }
            continue
          }
          if capture == 0 {
            initialError = max(initialError, abs(value - initial.fields[field][index]) * scale)
          }
          guard field < 3, c.observation(grid.position(field, index)) else { continue }
          let truth = expected.fields.frames[capture].fields[field][index]
          let delta = value - truth
          squares[field] += delta * delta
          norms[field] += truth * truth
          if field == 0 {
            maxP = max(maxP, abs(delta) * scale)
          } else {
            maxV = max(maxV, abs(delta) * scale)
          }
        }
      }
      var energy =
        grid.inside.indices.filter { grid.inside[$0] == 1 }.reduce(0.0) {
          $0 + frame.p[$1] * frame.p[$1]
        } * volume / (2 * c.density * c.speed * c.speed)
      for axis in 0..<3 {
        let shape = grid.shape(axis + 1)
        let stride = [1, r.nx, r.nx * r.ny][axis]
        for index in frame.fields[axis + 1].indices where grid.openFields[axis + 1][index] {
          let xyz = [index % shape[0], index / shape[0] % shape[1], index / (shape[0] * shape[1])]
          let plus = xyz[0] + r.nx * (xyz[1] + r.ny * xyz[2])
          let v = frame.fields[axis + 1][index]
          let next =
            v - dt * (frame.p[plus] - frame.p[plus - stride]) / (c.density * grid.spacing[axis])
          energy += c.density * volume * v * next / 2
        }
      }
      guard energy.isFinite, energy > 0 else { throw BenchmarkFailure.invalidSamples }
      if e0 == nil { e0 = energy }
      if !reference { budget = max(budget, abs(energy + h.dissipation![capture] - e0!) / e0!) }
      patchError = max(
        patchError, abs(h.patchDissipation[capture] - expected.patchWork[capture]) / c.patchEnergy)
      if !reference && r.axis == "time" {
        globalError = max(
          globalError, abs(h.dissipation![capture] - expected.work[capture]) / c.energy)
      }
    }
    guard norms.allSatisfy({ $0.isFinite && $0 > 0 }), let e0 else {
      throw BenchmarkFailure.invalidSamples
    }
    let fit = TiltedPulseOracle.reflectionFit(c, r, grid: grid, p: h.fields.frames.last!.p)
    let expectedFit =
      r.axis == "space"
      ? (coefficient: c.reflection, shift: 0.0)
      : TiltedPulseOracle.reflectionFit(c, r, grid: grid, p: expected.fields.frames.last!.p)
    return Self(
      schemaVersion: 1, model: model, status: reference ? "reference" : "supported",
      reference: r.axis == "space" ? "causal-plane-pulse-region" : "fixed-finite-plan-graph",
      reason: nil, specification: c, resolution: r, environment: environment, runtime: runtime,
      history: h,
      errors: TiltedPulseErrors(
        fieldL2: zip(squares, norms).map { sqrt($0 / $1) }, maxPressure: maxP, maxVelocity: maxV,
        energyBudget: reference ? nil : budget,
        globalWorkError: !reference && r.axis == "time" ? globalError : nil,
        patchWorkError: patchError,
        initialEnergyError: abs(e0 / c.energy - 1), initialStateError: initialError,
        boundaryVelocity: boundary, inactivePreservation: inactive, zeroZ: zeroZ,
        areaRelativeError: abs(area / c.sideArea - 1), coefficientLayoutError: coefficientError,
        geometryVolumeError: abs(
          Double(grid.inside.filter { $0 == 1 }.count) * volume / c.volume - 1),
        reflectedCoefficient: fit.coefficient, referenceCoefficient: expectedFit.coefficient,
        continuumCoefficient: c.reflection, pulseShift: fit.shift,
        referenceShift: expectedFit.shift, patchWorkJ: h.patchDissipation.last!,
        referencePatchWorkJ: expected.patchWork.last!))
  }
  func replacing(status: String, reason: String) -> Self {
    Self(
      schemaVersion: schemaVersion, model: model, status: status, reference: reference,
      reason: reason, specification: specification, resolution: resolution,
      environment: environment, runtime: runtime, history: history, errors: errors)
  }
}
public enum TiltedPulseCommand {
  public static func numericalBounds(_ r: TiltedPulseResult) throws {
    guard let e = r.errors, e.fieldL2.count == 3, e.fieldL2.allSatisfy({ $0.isFinite && $0 >= 0 }),
      let budget = e.energyBudget, budget.isFinite, budget >= 0, budget < 1e-4,
      [e.initialStateError, e.boundaryVelocity, e.inactivePreservation, e.zeroZ].allSatisfy({
        $0.isFinite && $0 >= 0 && $0 < 1e-6
      })
    else {
      throw BenchmarkFailure.failedConformance("tilted source field or work integrity failed")
    }
  }
  public static func check(_ series: [TiltedPulseResult]) throws -> [[Double]] {
    let c = TiltedPulseCase()
    guard series.count == 3, let axis = series.last?.resolution?.axis,
      series.compactMap(\.resolution)
        == TiltedPulseResolution.standard(c).filter({ $0.axis == axis }),
      series.allSatisfy({ $0.specification == c && $0.status == "supported" })
    else { throw BenchmarkFailure.invalidSamples }
    for r in series { try numericalBounds(r) }
    let e = series.last!.errors!
    guard e.fieldL2.allSatisfy({ $0 < (axis == "space" ? 0.10 : 0.01) }),
      e.maxPressure < (axis == "space" ? 0.20 : 0.03),
      e.maxVelocity < (axis == "space" ? 0.20 : 0.03),
      e.patchWorkError < (axis == "space" ? 0.05 : 0.002),
      e.initialEnergyError < 0.01, e.areaRelativeError < (axis == "space" ? 0.005 : 0.03),
      e.geometryVolumeError < 0.01,
      abs(e.reflectedCoefficient - e.referenceCoefficient) < (axis == "space" ? 0.03 : 0.005),
      abs(e.pulseShift - e.referenceShift) / c.halfWidth < (axis == "space" ? 0.10 : 0.005),
      axis == "space" || (e.globalWorkError ?? .infinity) < 0.002
    else {
      throw BenchmarkFailure.failedConformance(
        "tilted pulse finest field, reflection or central-patch work gate failed")
    }
    var orders: [[Double]] = []
    for field in 0..<3 {
      let errors = series.map { $0.errors!.fieldL2[field] }
      guard errors.allSatisfy({ $0 > 0 }) else { throw BenchmarkFailure.invalidSamples }
      let row = (0..<2).map { i in
        log(errors[i] / errors[i + 1])
          / log(
            axis == "space"
              ? Double(series[i + 1].resolution!.nx) / Double(series[i].resolution!.nx)
              : series[i].history!.fields.dt / series[i + 1].history!.fields.dt)
      }
      if axis == "space" {
        guard (0.5...2.5).contains(log(errors[0] / errors[2]) / log(4)) else {
          throw BenchmarkFailure.failedConformance("tilted spatial field does not refine")
        }
      } else {
        guard row.allSatisfy({ (1.7...2.3).contains($0) }) else {
          throw BenchmarkFailure.failedConformance("tilted temporal field is not second order")
        }
      }
      orders.append(row)
    }
    return orders
  }
  public static func runReference() throws {
    try run(model: "ContinuumKit.tilted-pulse-reference", supported: true, reference: true) {
      c, r in
      let grid = try TiltedPulseGrid(c, r)
      let dt = c.duration / Double(r.steps)
      let faces = grid.faces(dt: dt)
      let h = try TiltedPulseOracle.history(c, r, faces: faces, dt: dt)
      return TiltedPulseHistory(
        fields: h.fields, inside: grid.inside, faces: faces, layoutFaces: faces, layoutDt: dt,
        materialImpedance: c.impedance, wallCells: grid.wallCells, wallPressures: nil,
        dissipation: r.axis == "time" ? h.work : nil, patchDissipation: h.patchWork)
    }
  }
  public static func run(
    model: String, supported: Bool, reference: Bool = false,
    history: (TiltedPulseCase, TiltedPulseResolution) throws -> TiltedPulseHistory
  ) throws {
    let args = CommandLine.arguments
    guard let out = args.firstIndex(of: "--output"), out + 1 < args.count,
      let meta = args.firstIndex(of: "--metadata"), meta + 1 < args.count
    else { throw BenchmarkFailure.invalidCase }
    let root = URL(fileURLWithPath: args[out + 1])
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let env = try JSONDecoder().decode(
      BenchmarkEnvironment.self, from: Data(contentsOf: URL(fileURLWithPath: args[meta + 1])))
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let c = TiltedPulseCase()
    var results: [TiltedPulseResult] = []
    var reports: [[String: String]] = []
    var failed = false
    if !supported {
      results = [
        TiltedPulseResult(
          schemaVersion: 1, model: model, status: "unsupported",
          reference: "causal-plane-pulse-region",
          reason: "Production solver has no masked tilted impedance plan update", specification: c,
          resolution: nil, environment: env, runtime: 0, history: nil, errors: nil)
      ]
      reports = [
        [
          "case": c.id, "axis": "all", "status": "unsupported",
          "reason": "No tilted masked impedance plan update",
        ]
      ]
    } else {
      var series: [TiltedPulseResult] = []
      for r in TiltedPulseResolution.standard(c) {
        do {
          let clock = ContinuousClock()
          let start = clock.now
          let h = try history(c, r)
          let elapsed = start.duration(to: clock.now).components
          series.append(
            try TiltedPulseResult.evaluate(
              model: model, c: c, r: r, environment: env, h: h,
              runtime: Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18,
              reference: reference))
        } catch {
          failed = true
          series.append(
            TiltedPulseResult(
              schemaVersion: 1, model: model, status: "failed", reference: "not-evaluated",
              reason: String(describing: error), specification: c, resolution: r, environment: env,
              runtime: 0, history: nil, errors: nil))
        }
      }
      for axis in ["space", "time"] {
        do {
          let subset = series.filter { $0.resolution?.axis == axis }
          if !reference { for r in subset { try numericalBounds(r) } }
          let orders = reference ? [] : try check(subset)
          reports.append([
            "case": c.id, "axis": axis, "status": reference ? "reference" : "passed",
            "orders": String(describing: orders),
          ])
          print("\(reference ? "REFERENCE":"PASS") \(c.id) \(axis): \(orders)")
        } catch {
          let integrityOK =
            !reference && axis == "space"
            && series.filter { $0.resolution?.axis == axis }.allSatisfy {
              (try? numericalBounds($0)) != nil
            }
          let status = integrityOK ? "gap" : "failed"
          let reason = String(describing: error)
          if !integrityOK { failed = true }
          for i in series.indices where series[i].resolution?.axis == axis {
            series[i] = series[i].replacing(status: status, reason: reason)
          }
          reports.append(["case": c.id, "axis": axis, "status": status, "reason": reason])
          print("\(status.uppercased()) \(c.id) \(axis): \(reason)")
        }
      }
      results = series
    }
    try encoder.encode([c]).write(to: root.appendingPathComponent("cases.json"))
    try encoder.encode(results).write(to: root.appendingPathComponent("results.json"))
    try encoder.encode(reports).write(to: root.appendingPathComponent("conformance.json"))
    var csv =
      "model,case,status,axis,nx,steps,pressure_l2,ux_l2,uy_l2,energy_budget,patch_work_error,reflection,reference_reflection,shift_m,reference_shift_m,reference,runtime_s\n"
    for r in results {
      var values = [
        r.model, c.id, r.status, r.resolution?.axis ?? "unsupported",
        r.resolution.map { String($0.nx) } ?? "", r.resolution.map { String($0.steps) } ?? "",
      ]
      values += (0..<3).map { i in r.errors.map { String($0.fieldL2[i]) } ?? "" }
      values += [
        r.errors?.energyBudget.map { String($0) } ?? "",
        r.errors.map { String($0.patchWorkError) } ?? "",
        r.errors.map { String($0.reflectedCoefficient) } ?? "",
        r.errors.map { String($0.referenceCoefficient) } ?? "",
        r.errors.map { String($0.pulseShift) } ?? "",
        r.errors.map { String($0.referenceShift) } ?? "", r.reference, String(r.runtime),
      ]
      csv += values.joined(separator: ",") + "\n"
    }
    try csv.write(to: root.appendingPathComponent("summary.csv"), atomically: true, encoding: .utf8)
    if failed {
      throw BenchmarkFailure.failedConformance(
        "tilted pulse numerical or time suite failed; complete reports retained")
    }
  }
}
