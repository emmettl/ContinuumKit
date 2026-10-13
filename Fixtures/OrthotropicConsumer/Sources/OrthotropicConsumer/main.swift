import Foundation
import simd
import SolidMechanics

func require(_ value: Bool, _ message: String) throws {
    if !value { throw NSError(domain: message, code: 1) }
}
let fixture = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
let data = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("input.json"))) as! [String: Any]
@MainActor func number(_ name: String) -> Double { (data[name] as! NSNumber).doubleValue }
let law = try OrthotropicPlaneStress(youngAlong: number("E1_Pa"), youngAcross: number("E2_Pa"),
    shear: number("G12_Pa"), poissonAlongAcross: number("nu12"))
let frame = try OrthotropicPlaneStress.Frame()
var samples = 0
for name in ["constitutive-reference.csv", "rotated-reference.csv"] {
    let lines = try String(contentsOf: fixture.appendingPathComponent(name), encoding: .utf8).split(whereSeparator: { $0.isNewline }).dropFirst()
    for line in lines {
        let row = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let rotated = name.hasPrefix("rotated")
        let index = rotated ? 1 : 2
        let strain = SIMD3(Double(row[index])!, Double(row[index+1])!, Double(row[index+2])!)
        let expected = SIMD3(Double(row[index+3])!, Double(row[index+4])!, Double(row[index+5])!)
        let energy = Double(row[index+6])!
        let result = try law.evaluate(strain: strain, grainAngleRadians: rotated ? Double(row[0])! * .pi/180 : 0, frame: frame)
        let scale = max(1, abs(expected.x), abs(expected.y), abs(expected.z))
        try require(simd_length(result.stress-expected)/scale <= 1e-6, "independent frozen stress")
        try require(abs(result.energyDensity-energy)/max(1, abs(energy)) <= 1e-6, "independent frozen energy")
        try require(result.dissipationDensity == 0, "elastic dissipation")
        samples += 1
    }
}
try require(samples == 41, "complete frozen matrix")
let moved = try OrthotropicPlaneStress.Frame(x: SIMD3(0,1,0), y: SIMD3(0,0,1))
let result = try law.evaluate(strain: SIMD3(1e-4,0,0), grainAngleRadians: 0, frame: moved)
try require(simd_length(result.worldStress*moved.normal) == 0, "normal traction")
do {
    _ = try law.evaluate(strain: SIMD3(0.002,0,0), grainAngleRadians: 0, frame: moved)
    throw NSError(domain: "accepted invalid trial", code: 1)
} catch OrthotropicPlaneStress.MaterialError.invalidTrial {}
print("PASS public SolidMechanics consumer: 41 frozen independent samples, world frame and typed rejection")
