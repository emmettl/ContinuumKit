import Foundation
import SolidMechanics
import FrozenP2

func bits(_ actual: [Double], _ original: [Double]) {
    precondition(actual.map(\.bitPattern) == original.map(\.bitPattern), "public/frozen arithmetic differs")
}
var samples = 0
for hardening in [0.0, 5e8] {
    let shared = try VeneerCompression(young: 1e10, yieldStress: 2.5e7, hardening: hardening)
    let frozen = try TargetVeneerCompression(young: 1e10, yieldStress: 2.5e7, hardening: hardening)
    var a = shared.zeroState, b = frozen.zeroState
    for strain in [0, -0.001, -0.008, -0.004, 0, -0.01, -0.005, 0.001] {
        a = try shared.evaluate(strain: strain, from: a)
        b = try frozen.evaluate(strain: strain, from: b)
        bits([a.strain,a.stress,a.alpha,a.workDensity,a.elasticEnergyDensity,a.hardeningEnergyDensity,a.dissipationDensity],
             [b.strain,b.stress,b.alpha,b.workDensity,b.elasticEnergyDensity,b.hardeningEnergyDensity,b.dissipationDensity])
        samples += 1
    }
}
for shear in [false, true] {
    for length in [0.005, 0.0025] {
        let shared = try VeneerDamage(mode: shear ? .shear : .tension, modulus: 1e9, strength: 2e6, fractureEnergy: 100, bandLength: length)
        let frozen = try TargetVeneerDamage(mode: shear ? .shear : .tension, modulus: 1e9, strength: 2e6, fractureEnergy: 100, bandLength: length)
        var a = shared.zeroState, b = frozen.zeroState
        let sign = shear ? -1.0 : 1.0
        for strain in [0, 0.001, 0.004, 0, 0.008, 0.002, 0.02, 0.04, 0] {
            a = try shared.evaluate(strain: sign * strain, from: a)
            b = try frozen.evaluate(strain: sign * strain, from: b)
            bits([a.strain,a.stress,a.maximumEquivalentStrain,a.damage,a.energyDensity,a.dissipationDensity,a.workDensity],
                 [b.strain,b.stress,b.maximumEquivalentStrain,b.damage,b.energyDensity,b.dissipationDensity,b.workDensity])
            samples += 1
        }
    }
}
precondition(samples == 52)
print("PASS 52 public/frozen scalar material samples: exact bits in all state fields; adoption deferred")
