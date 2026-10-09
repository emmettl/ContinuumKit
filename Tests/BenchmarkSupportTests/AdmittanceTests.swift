import BenchmarkSupport
import Foundation
import Testing

@Suite("Physical wall area and isolated impedance flow") struct AdmittanceTests {
  let env = BenchmarkEnvironment(
    repository: "test", revision: "test", sourceHashes: [:], hardware: "test", toolchain: "test",
    operatingSystem: "test")
  func reference(_ kind: AdmittanceCase.Kind = .cylinder) throws -> (
    AdmittanceCase, AdmittanceResolution, AdmittanceHistory, AdmittanceResult
  ) {
    let c = AdmittanceCase(kind: kind)
    let r = AdmittanceResolution(axis: "space", nx: 32, courant: 0.2)
    let h = try AdmittanceOracle.reference(c, r)
    return (
      c, r, h,
      try AdmittanceResult.evaluate(
        model: "test", c: c, r: r, environment: env, h: h, runtime: 0, reference: true)
    )
  }
  @Test("Physical side area and prescribed power have independent geometric goldens")
  func geometryGoldens() {
    let box = AdmittanceCase(kind: .alignedBox)
    let circle = AdmittanceCase(kind: .cylinder)
    #expect(box.sideArea == 0.09375 && box.prescribedPower == 0.000078125)
    #expect(abs(circle.sideArea - 0.07363107781851078) < 1e-15)
    #expect(abs(circle.prescribedPower - circle.sideArea / 1200) < 1e-18)
  }
  @Test("Cartesian circle perimeter retains 4/pi bias under refinement") func staircaseBias() throws
  {
    let c = AdmittanceCase(kind: .cylinder)
    for n in [16, 32, 64] {
      let r = AdmittanceResolution(axis: "space", nx: n, courant: 0.2)
      let h = try AdmittanceOracle.reference(c, r)
      let result = try AdmittanceResult.evaluate(
        model: "full-stairs", c: c, r: r, environment: env, h: h, runtime: 0, reference: true)
      #expect(abs(result.errors!.effectiveArea / 0.09375 - 1) < 1e-7)
      #expect(abs(result.errors!.areaRelativeError - (4 / Double.pi - 1)) < 2e-7)
      #expect(result.physicalStatus == "gap")
    }
  }
  @Test("Aligned box passes physical area independent of its pressure time error") func control()
    throws
  {
    let (_, _, _, result) = try reference(.alignedBox)
    #expect(result.physicalStatus == "passed" && result.errors!.areaRelativeError < 1e-7)
  }
  @Test("Exponential scalar wall reference has exact independent rate") func scalarRate() throws {
    let (c, r, h, _) = try reference(.alignedBox)
    let g = try AdmittanceGrid(c, r)
    let rates = try AdmittanceOracle.rates(g, faces: h.faces, dt: h.fields.dt)
    let cell = 4 + 32 * (4 + 32 * 4)
    #expect(abs(rates[cell] / (2 * c.speed / (c.impedance * g.spacing[0])) - 1) < 1e-7)
    #expect(abs(h.fields.frames[1].p[cell] - exp(-rates[cell] * r.dt(c))) < 1e-14)
  }
  @Test("Pressure-derived area weighting can pass the physical gate without changing the mask")
  func correctedArea() throws {
    let (c, r, h, _) = try reference()
    let g = try AdmittanceGrid(c, r)
    let weight = Double.pi / 4
    let faces = h.faces.map { $0 > 0 ? Float(Double($0) * weight) : $0 }
    let rates = try AdmittanceOracle.rates(g, faces: faces, dt: h.fields.dt)
    let initial = h.fields.frames[0]
    let final = RigidModeFrame(
      step: 1,
      p: initial.p.indices.map {
        g.labels[$0] >= 0 ? exp(-rates[$0] * h.fields.dt) : initial.p[$0]
      }, u: initial.u, v: initial.v, w: initial.w)
    let weighted = AdmittanceHistory(
      fields: RigidModeHistory(
        spacing: h.fields.spacing, dt: h.fields.dt, frames: [initial, final]), inside: h.inside,
      faces: faces, layoutFaces: faces, layoutDt: h.layoutDt, materialImpedance: h.materialImpedance
    )
    let result = try AdmittanceResult.evaluate(
      model: "analytic-area-weight-control", c: c, r: r, environment: env, h: weighted, runtime: 0,
      reference: true)
    #expect(result.physicalStatus == "passed" && result.errors!.areaRelativeError < 1e-7)
  }
  @Test("A second-order isolated wall substep cannot hide a physical geometry gap")
  func splitStatuses() throws {
    let c = AdmittanceCase(kind: .cylinder)
    var series: [AdmittanceResult] = []
    for r in AdmittanceResolution.standard().filter({ $0.axis == "time" }) {
      let h = try AdmittanceOracle.reference(c, r)
      let g = try AdmittanceGrid(c, r)
      let rates = try AdmittanceOracle.rates(g, faces: h.faces, dt: h.fields.dt)
      let first = h.fields.frames[0]
      let p = first.p.indices.map { i in
        g.labels[i] >= 0
          ? (1 - rates[i] * h.fields.dt / 2) / (1 + rates[i] * h.fields.dt / 2) : first.p[i]
      }
      let last = RigidModeFrame(step: 1, p: p, u: first.u, v: first.v, w: first.w)
      let source = AdmittanceHistory(
        fields: RigidModeHistory(
          spacing: h.fields.spacing, dt: h.fields.dt, frames: [first, last]), inside: h.inside,
        faces: h.faces, layoutFaces: h.layoutFaces, layoutDt: h.layoutDt,
        materialImpedance: h.materialImpedance)
      let result = try AdmittanceResult.evaluate(
        model: "independent-trapezoidal-control", c: c, r: r, environment: env, h: source,
        runtime: 0)
      #expect(
        result.numericalStatus == "passed" && result.physicalStatus == "gap"
          && result.status == "gap")
      series.append(result)
    }
    #expect(try AdmittanceCommand.timeCheck(series).allSatisfy { (1.7...2.3).contains($0) })
  }
  @Test("Incompatible face clocks and false cap absorption reject") func layoutRejection() throws {
    let (c, r, h, _) = try reference()
    var faces = h.faces
    faces[4 * h.inside.count + 16 + 32 * 16] = 0.1
    for bad in [
      AdmittanceHistory(
        fields: h.fields, inside: h.inside, faces: faces, layoutFaces: faces, layoutDt: h.layoutDt,
        materialImpedance: 3),
      AdmittanceHistory(
        fields: h.fields, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
        layoutDt: 2 * h.layoutDt, materialImpedance: 3),
    ] {
      #expect(throws: BenchmarkFailure.self) {
        try AdmittanceResult.evaluate(
          model: "wrong-layout", c: c, r: r, environment: env, h: bad, runtime: 0)
      }
    }
  }
  @Test("Wrong masks and native field dimensions reject") func fieldRejection() throws {
    let (c, r, h, _) = try reference()
    var inside = h.inside
    inside[0] = 1
    let broken = RigidModeHistory(
      spacing: h.fields.spacing, dt: h.fields.dt,
      frames: h.fields.frames.map {
        RigidModeFrame(step: $0.step, p: $0.p, u: $0.u, v: $0.v, w: [])
      })
    for bad in [
      AdmittanceHistory(
        fields: h.fields, inside: inside, faces: h.faces, layoutFaces: h.layoutFaces,
        layoutDt: h.layoutDt, materialImpedance: 3),
      AdmittanceHistory(
        fields: broken, inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces,
        layoutDt: h.layoutDt, materialImpedance: 3),
    ] {
      #expect(throws: BenchmarkFailure.self) {
        try AdmittanceResult.evaluate(
          model: "bad-fields", c: c, r: r, environment: env, h: bad, runtime: 0)
      }
    }
  }
  @Test("Inactive corruption is explicit and cannot become numerical conformance") func padding()
    throws
  {
    let (c, r, h, _) = try reference()
    let first = h.fields.frames[0]
    var p = h.fields.frames[1].p
    p[0] += 1
    let last = RigidModeFrame(step: 1, p: p, u: first.u, v: first.v, w: first.w)
    let broken = AdmittanceHistory(
      fields: RigidModeHistory(spacing: h.fields.spacing, dt: h.fields.dt, frames: [first, last]),
      inside: h.inside, faces: h.faces, layoutFaces: h.layoutFaces, layoutDt: h.layoutDt,
      materialImpedance: 3)
    let result = try AdmittanceResult.evaluate(
      model: "padding", c: c, r: r, environment: env, h: broken, runtime: 0)
    #expect(result.numericalStatus == "failed" && result.errors!.inactivePreservation == 1)
  }
  @Test("Malformed decoded cases and missing series reject") func invalid() throws {
    var dict =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(AdmittanceCase(kind: .cylinder)))
      as! [String: Any]
    dict["impedance"] = -1
    let bad = try JSONDecoder().decode(
      AdmittanceCase.self, from: JSONSerialization.data(withJSONObject: dict))
    #expect(throws: BenchmarkFailure.self) { try bad.validate() }
    #expect(throws: BenchmarkFailure.self) { try AdmittanceCommand.timeCheck([]) }
  }
}
