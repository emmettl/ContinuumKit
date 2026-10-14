import Foundation

/// Bounded uniaxial compression surrogate, evaluated along one veneer material
/// axis. No coupling, damage, finite-strain crushing, rate or empirical calibration.
/// Compression is negative. Plastic strain = -alpha; linear hardening stores
/// H alpha²/2, while yield friction dissipates Y alpha. Trials are immutable.
public struct TargetVeneerCompression: Sendable {
    public enum MaterialError: Error { case invalidParameters, invalidTrial, incompatibleState }
    public struct State: Sendable {
        public let strain: Double
        public let stress: Double
        public let alpha: Double
        public let workDensity: Double
        public let elasticEnergyDensity: Double
        public let hardeningEnergyDensity: Double
        public let dissipationDensity: Double
        fileprivate let signature: [Double]
    }
    public let young: Double
    public let yieldStress: Double
    public let hardening: Double
    public let minimumStrain: Double
    public let maximumStrain: Double
    private var signature: [Double] { [young, yieldStress, hardening, minimumStrain, maximumStrain] }

    public init(young: Double, yieldStress: Double, hardening: Double,
                minimumStrain: Double = -0.03, maximumStrain: Double = 0.001) throws {
        guard [young, yieldStress, hardening, minimumStrain, maximumStrain].allSatisfy(\.isFinite),
              young > 0, yieldStress > 0, hardening >= 0,
              (young + hardening).isFinite, minimumStrain >= -0.03,
              minimumStrain < 0, maximumStrain >= 0, maximumStrain <= 0.001 else {
            throw MaterialError.invalidParameters
        }
        self.young = young; self.yieldStress = yieldStress; self.hardening = hardening
        self.minimumStrain = minimumStrain; self.maximumStrain = maximumStrain
    }
    public var zeroState: State {
        .init(strain: 0, stress: 0, alpha: 0, workDensity: 0,
              elasticEnergyDensity: 0, hardeningEnergyDensity: 0,
              dissipationDensity: 0, signature: signature)
    }
    /// Return mapping for compression only. The caller explicitly accepts by
    /// assigning the returned state; failed and abandoned trials leave history intact.
    public func evaluate(strain: Double, from previous: State) throws -> State {
        guard previous.signature == signature else { throw MaterialError.incompatibleState }
        guard strain.isFinite, strain >= minimumStrain, strain <= maximumStrain else {
            throw MaterialError.invalidTrial
        }
        let trialStress = young * (strain + previous.alpha)
        let excess = -trialStress - (yieldStress + hardening * previous.alpha)
        let increment = max(0, excess / (young + hardening))
        let alpha = previous.alpha + increment
        let stress = young * (strain + alpha)
        var workIncrement: Double
        if increment > 0 {
            // Exact piecewise-linear stress integral, split at first yield.
            let onset = -(yieldStress + (young + hardening) * previous.alpha) / young
            let onsetStress = -(yieldStress + hardening * previous.alpha)
            workIncrement = 0.5 * (previous.stress + onsetStress) * (onset - previous.strain)
            workIncrement += 0.5 * (onsetStress + stress) * (strain - onset)
        } else {
            workIncrement = 0.5 * (previous.stress + stress) * (strain - previous.strain)
        }
        let elastic = stress * stress / (2 * young)
        let stored = 0.5 * hardening * alpha * alpha
        let dissipated = yieldStress * alpha
        let work = previous.workDensity + workIncrement
        guard [alpha, stress, elastic, stored, dissipated, work].allSatisfy(\.isFinite) else {
            throw MaterialError.invalidTrial
        }
        return .init(strain: strain, stress: stress, alpha: alpha, workDensity: work,
                     elasticEnergyDensity: elastic, hardeningEnergyDensity: stored,
                     dissipationDensity: dissipated, signature: signature)
    }
}
