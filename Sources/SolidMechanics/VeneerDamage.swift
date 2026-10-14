import Foundation

/// Scalar tension or symmetric engineering-shear crack-band surrogate. A single
/// declared material mode is active; this is not coupled orthotropic damage.
/// Includes elastic work in Gf: complete separation consumes Gf / bandLength.
public struct VeneerDamage: Sendable {
    public enum Mode: Sendable { case tension, shear }
    public enum MaterialError: Error { case invalidParameters, invalidTrial, incompatibleState }
    public struct State: Sendable {
        public let strain: Double
        public let stress: Double
        public let maximumEquivalentStrain: Double
        public let damage: Double
        public let energyDensity: Double
        public let dissipationDensity: Double
        public let workDensity: Double
        fileprivate let signature: [Double]
    }
    public let mode: Mode
    public let modulus: Double
    public let strength: Double
    public let fractureEnergy: Double
    public let bandLength: Double
    public let maximumStrain: Double
    public var initiationStrain: Double { strength / modulus }
    public var failureStrain: Double { 2 * (fractureEnergy / bandLength) / strength }
    private var signature: [Double] {
        [mode == .tension ? 0 : 1, modulus, strength, fractureEnergy, bandLength, maximumStrain]
    }
    public init(mode: Mode, modulus: Double, strength: Double, fractureEnergy: Double,
                bandLength: Double, maximumStrain: Double = 0.1) throws {
        let e0 = strength / modulus, ef = 2 * (fractureEnergy / bandLength) / strength
        guard [modulus, strength, fractureEnergy, bandLength, maximumStrain, e0, ef].allSatisfy(\.isFinite),
              modulus > 0, strength > 0, fractureEnergy > 0, bandLength > 0,
              maximumStrain > 0, maximumStrain <= 0.1, e0 > 0, ef > e0,
              ef <= maximumStrain else { throw MaterialError.invalidParameters }
        self.mode = mode; self.modulus = modulus; self.strength = strength
        self.fractureEnergy = fractureEnergy; self.bandLength = bandLength
        self.maximumStrain = maximumStrain
    }
    public var zeroState: State {
        .init(strain: 0, stress: 0, maximumEquivalentStrain: 0, damage: 0,
              energyDensity: 0, dissipationDensity: 0, workDensity: 0, signature: signature)
    }
    private func envelope(_ q: Double) -> Double {
        if q <= initiationStrain { return modulus * q }
        if q >= failureStrain { return 0 }
        return strength * (failureStrain - q) / (failureStrain - initiationStrain)
    }
    private func damage(_ q: Double) -> Double {
        q <= initiationStrain ? 0 : min(1, max(0, 1 - envelope(q) / (modulus * q)))
    }
    public func evaluate(strain: Double, from previous: State) throws -> State {
        guard previous.signature == signature else { throw MaterialError.incompatibleState }
        guard strain.isFinite, abs(strain) <= maximumStrain,
              mode == .shear || strain >= 0 else { throw MaterialError.invalidTrial }
        let q = max(previous.maximumEquivalentStrain, abs(strain))
        let d = damage(q), stress = (1 - d) * modulus * strain
        let energy = 0.5 * stress * strain
        let capped = min(q, failureStrain)
        let loss: Double
        if capped <= initiationStrain { loss = 0 }
        else {
            let area = 0.5 * strength * initiationStrain
                + 0.5 * (strength + envelope(capped)) * (capped - initiationStrain)
            loss = area - 0.5 * envelope(capped) * capped
        }
        // Exact stress-path integration. Split at envelope, unloading and sign
        // changes; never compute external work as storage + dissipation.
        var cuts = [previous.strain, strain]
        for point in [-failureStrain, -initiationStrain, -previous.maximumEquivalentStrain,
                       0, previous.maximumEquivalentStrain, initiationStrain, failureStrain] {
            if point > min(previous.strain, strain) && point < max(previous.strain, strain) { cuts.append(point) }
        }
        cuts.sort(); if strain < previous.strain { cuts.reverse() }
        func pathStress(_ e: Double) -> Double {
            let k = max(previous.maximumEquivalentStrain, abs(e))
            return (1 - damage(k)) * modulus * e
        }
        var work = previous.workDensity
        for (a, b) in zip(cuts, cuts.dropFirst()) { work += 0.5 * (pathStress(a) + pathStress(b)) * (b - a) }
        guard [q, d, stress, energy, loss, work].allSatisfy(\.isFinite) else { throw MaterialError.invalidTrial }
        return .init(strain: strain, stress: stress, maximumEquivalentStrain: q,
                     damage: d, energyDensity: energy, dissipationDensity: loss,
                     workDensity: work, signature: signature)
    }
}
