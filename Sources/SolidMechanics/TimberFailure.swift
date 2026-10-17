import Foundation

/// Small-strain orthotropic timber that breaks: one material point in its grain frame, in plane
/// stress with the two shears through the thickness, after the Hashin-type criteria of Sandhaas
/// and van de Kuilen (HERON 58, 2013) with crack-band softening (Bazant and Oh; Lapczyk and
/// Hurtado, Composites A 38, 2007).
///
/// Strain is (epsilon_L, epsilon_T, engineering gamma_LT) in the plane and (gamma_LZ, gamma_TZ)
/// through it: L along the grain, T across it in the plane, Z the normal. Three brittle modes
/// each soften linearly over their fracture energy per band length:
/// - fibre: tension along the grain, (sigma_L / f_t0)^2 >= 1, softening sigma_L in tension;
/// - splitting: (sigma_T / f_t90)^2 + (tau_LT / f_v)^2 + (tau_LZ / f_v)^2 >= 1, with sigma_T
///   counted in tension only, softening sigma_T in tension, tau_LT and tau_LZ;
/// - rolling shear: (tau_TZ / f_r)^2 >= 1, softening tau_TZ.
/// Compression along and across the grain is perfectly plastic at f_c0 and f_c90 (the crushing
/// of timber is ductile), and closes cracks: damage never softens compression.
///
/// A mode's softening ends at `ratio` times its initiation, the fracture energy per band length
/// over the elastic energy density at initiation (at the current mixity, for splitting), or at
/// once when that ratio is below one (a band too long for the energy). Indices are of the
/// undamaged (effective) stress. Rate effects are the caller's: scale the strengths.
/// This is a pure trial evaluation: rejection never mutates accepted history.
public struct TimberFailure: Sendable {
    public enum MaterialError: Error { case invalidParameters, invalidTrial, incompatibleState }

    /// Strains or stresses: in-plane L, T and LT (engineering shear for strain), then through
    /// the thickness LZ and TZ.
    public struct Components: Sendable, Equatable {
        public var along: Double, across: Double, shear: Double, alongThrough: Double, rolling: Double
        public init(along: Double = 0, across: Double = 0, shear: Double = 0, alongThrough: Double = 0,
                    rolling: Double = 0) {
            self.along = along; self.across = across; self.shear = shear
            self.alongThrough = alongThrough; self.rolling = rolling
        }
        var all: [Double] { [along, across, shear, alongThrough, rolling] }
    }

    public struct State: Sendable {
        public let strain: Components
        public let stress: Components
        /// Damage of each mode, 0 sound to 1 broken.
        public let fibre: Double, splitting: Double, rollingShear: Double
        /// The largest failure index each mode has reached.
        public let fibreIndex: Double, splittingIndex: Double, rollingIndex: Double
        /// Plastic (crushing) strain along and across the grain, compressive negative.
        public let plasticAlong: Double, plasticAcross: Double
        /// External work density, by the trapezoid rule over accepted increments (J/m^3).
        public let workDensity: Double
        fileprivate let signature: [Double]
    }

    public let alongModulus: Double, acrossModulus: Double, shearModulus: Double, rollingModulus: Double
    public let poisson: Double
    public let tensionAlong: Double, compressionAlong: Double, tensionAcross: Double
    public let compressionAcross: Double, shearStrength: Double, rollingStrength: Double
    public let fibreEnergy: Double, splittingEnergy: Double, shearEnergy: Double, rollingEnergy: Double
    public let bandLength: Double, throughBandLength: Double
    public let maximumStrain: Double
    private let q11: Double, q22: Double, q12: Double

    /// Moduli and strengths in Pa, fracture energies in J/m^2, bands in m. `poisson` is
    /// nu_LT (strain across over strain along under stress along); nu_TL follows by reciprocity.
    /// `bandLength` smears the in-plane modes, `throughBandLength` rolling shear.
    public init(alongModulus: Double, acrossModulus: Double, shearModulus: Double, rollingModulus: Double,
                poisson: Double, tensionAlong: Double, compressionAlong: Double, tensionAcross: Double,
                compressionAcross: Double, shearStrength: Double, rollingStrength: Double,
                fibreEnergy: Double, splittingEnergy: Double, shearEnergy: Double, rollingEnergy: Double,
                bandLength: Double, throughBandLength: Double, maximumStrain: Double = 0.1) throws {
        let positive = [alongModulus, acrossModulus, shearModulus, rollingModulus, tensionAlong,
                        compressionAlong, tensionAcross, compressionAcross, shearStrength, rollingStrength,
                        fibreEnergy, splittingEnergy, shearEnergy, rollingEnergy, bandLength,
                        throughBandLength, maximumStrain]
        let nuTL = poisson * acrossModulus / alongModulus
        let denominator = 1 - poisson * nuTL
        guard positive.allSatisfy({ $0.isFinite && $0 > 0 }), poisson.isFinite, maximumStrain <= 1,
              denominator.isFinite, denominator > 1e-12 else { throw MaterialError.invalidParameters }
        self.alongModulus = alongModulus; self.acrossModulus = acrossModulus
        self.shearModulus = shearModulus; self.rollingModulus = rollingModulus; self.poisson = poisson
        self.tensionAlong = tensionAlong; self.compressionAlong = compressionAlong
        self.tensionAcross = tensionAcross; self.compressionAcross = compressionAcross
        self.shearStrength = shearStrength; self.rollingStrength = rollingStrength
        self.fibreEnergy = fibreEnergy; self.splittingEnergy = splittingEnergy
        self.shearEnergy = shearEnergy; self.rollingEnergy = rollingEnergy
        self.bandLength = bandLength; self.throughBandLength = throughBandLength
        self.maximumStrain = maximumStrain
        q11 = alongModulus / denominator; q22 = acrossModulus / denominator; q12 = poisson * q22
    }

    private var signature: [Double] {
        [alongModulus, acrossModulus, shearModulus, rollingModulus, poisson, tensionAlong, compressionAlong,
         tensionAcross, compressionAcross, shearStrength, rollingStrength, fibreEnergy, splittingEnergy,
         shearEnergy, rollingEnergy, bandLength, throughBandLength, maximumStrain]
    }

    public var zeroState: State {
        .init(strain: .init(), stress: .init(), fibre: 0, splitting: 0, rollingShear: 0, fibreIndex: 0,
              splittingIndex: 0, rollingIndex: 0, plasticAlong: 0, plasticAcross: 0, workDensity: 0,
              signature: signature)
    }

    /// Damage for a largest index `r` and softening that ends at `ratio` times initiation:
    /// linear softening of the effective stress's index, sudden where `ratio` <= 1.
    static func damage(index r: Double, ratio: Double) -> Double {
        if r <= 1 { return 0 }
        if ratio <= 1 { return 1 }
        return min(1, ratio / (ratio - 1) * (1 - 1 / r))
    }

    public func evaluate(strain: Components, from previous: State) throws -> State {
        guard previous.signature == signature else { throw MaterialError.incompatibleState }
        guard strain.all.allSatisfy({ $0.isFinite && abs($0) <= maximumStrain }) else {
            throw MaterialError.invalidTrial
        }
        // Crushing: the effective stress held at the compressive strengths by plastic strain,
        // along and across together (a few sweeps settle the Poisson coupling).
        var plasticAlong = previous.plasticAlong, plasticAcross = previous.plasticAcross
        func effective() -> (Double, Double) {
            let a = strain.along - plasticAlong, b = strain.across - plasticAcross
            return (q11 * a + q12 * b, q12 * a + q22 * b)
        }
        for _ in 0..<20 {
            var (sL, sT) = effective()
            if sL < -compressionAlong { plasticAlong += (sL + compressionAlong) / q11; (sL, sT) = effective() }
            if sT < -compressionAcross { plasticAcross += (sT + compressionAcross) / q22 }
        }
        let (sL, sT) = effective()
        let tLT = shearModulus * strain.shear
        let tLZ = shearModulus * strain.alongThrough
        let tTZ = rollingModulus * strain.rolling

        // Indices of the effective stress, and each mode's softening ratio at initiation.
        let fibreIndex = max(previous.fibreIndex, max(sL, 0) / tensionAlong)
        let fibreRatio = (fibreEnergy / bandLength) / (0.5 * tensionAlong * tensionAlong / alongModulus)
        let tension = max(sT, 0) / tensionAcross
        let sliding = (tLT * tLT + tLZ * tLZ).squareRoot() / shearStrength
        let split = (tension * tension + sliding * sliding).squareRoot()
        let splittingIndex = max(previous.splittingIndex, split)
        // At the current mixity: shares of opening and sliding in the index.
        let opening = split > 0 ? tension * tension / (split * split) : 1
        let mixedEnergy = opening * splittingEnergy + (1 - opening) * shearEnergy
        let initiation = 0.5 * (opening * tensionAcross * tensionAcross / acrossModulus
            + (1 - opening) * shearStrength * shearStrength / shearModulus)
        let splittingRatio = (mixedEnergy / bandLength) / initiation
        let rollingIndex = max(previous.rollingIndex, abs(tTZ) / rollingStrength)
        let rollingRatio = (rollingEnergy / throughBandLength)
            / (0.5 * rollingStrength * rollingStrength / rollingModulus)

        let fibre = max(previous.fibre, Self.damage(index: fibreIndex, ratio: fibreRatio))
        let splitting = max(previous.splitting, Self.damage(index: splittingIndex, ratio: splittingRatio))
        let rollingShear = max(previous.rollingShear, Self.damage(index: rollingIndex, ratio: rollingRatio))
        let stress = Components(
            along: sL > 0 ? (1 - fibre) * sL : sL, across: sT > 0 ? (1 - splitting) * sT : sT,
            shear: (1 - splitting) * tLT, alongThrough: (1 - splitting) * tLZ,
            rolling: (1 - rollingShear) * tTZ)
        var work = previous.workDensity
        for (s0, s1, e0, e1) in zip(zip(previous.stress.all, stress.all), zip(previous.strain.all, strain.all))
            .map({ ($0.0, $0.1, $1.0, $1.1) }) {
            work += 0.5 * (s0 + s1) * (e1 - e0)
        }
        guard stress.all.allSatisfy(\.isFinite), work.isFinite, plasticAlong.isFinite, plasticAcross.isFinite
        else { throw MaterialError.invalidTrial }
        return .init(strain: strain, stress: stress, fibre: fibre, splitting: splitting,
                     rollingShear: rollingShear, fibreIndex: fibreIndex, splittingIndex: splittingIndex,
                     rollingIndex: rollingIndex, plasticAlong: plasticAlong, plasticAcross: plasticAcross,
                     workDensity: work, signature: signature)
    }
}
