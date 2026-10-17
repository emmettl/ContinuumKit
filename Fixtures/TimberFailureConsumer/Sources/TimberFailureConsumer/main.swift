import Foundation
import SolidMechanics

// The public TimberFailure, optimised, from a clean Git consumer: each brittle mode peaks at its
// strength and separates on its fracture energy over the band; crushing holds its strength.
let law = try TimberFailure(
    alongModulus: 11_000e6, acrossModulus: 370e6, shearModulus: 690e6, rollingModulus: 50e6, poisson: 0.35,
    tensionAlong: 24e6, compressionAlong: 36e6, tensionAcross: 0.7e6, compressionAcross: 4.3e6,
    shearStrength: 6.9e6, rollingStrength: 0.5e6, fibreEnergy: 60e3, splittingEnergy: 500, shearEnergy: 1200,
    rollingEnergy: 600, bandLength: 0.05, throughBandLength: 0.035)
let q = 1 / (1 - 0.35 * 0.35 * 370e6 / 11_000e6)
var checks = 0
for (name, strength, separation, end, component) in [
    ("fibre", 24e6, 60e3 / 0.05 / q, 0.1, \TimberFailure.Components.along),
    ("splitting", 0.7e6, 500 / 0.05 / q, 0.06, \TimberFailure.Components.across),
    ("rolling", 0.5e6, 600 / 0.035, 0.08, \TimberFailure.Components.rolling),
] {
    var state = law.zeroState
    var peak = 0.0
    for i in 1...20_000 {
        var strain = TimberFailure.Components()
        strain[keyPath: component] = end * Double(i) / 20_000
        state = try law.evaluate(strain: strain, from: state)
        peak = max(peak, state.stress[keyPath: component])
    }
    precondition(abs(peak - strength) < 2e-3 * strength, "\(name) peak \(peak)")
    precondition(abs(state.workDensity - separation) < 5e-3 * separation, "\(name) work \(state.workDensity)")
    checks += 2
}
var crushed = law.zeroState
for i in 1...2000 { crushed = try law.evaluate(strain: .init(along: -0.03 * Double(i) / 2000), from: crushed) }
precondition(abs(crushed.stress.along + 36e6) < 1e-3 * 36e6 && crushed.fibre == 0)
checks += 1
print("PASS \(checks) TimberFailure public-consumer closed-form checks")
