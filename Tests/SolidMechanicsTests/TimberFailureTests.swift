import Foundation
import SolidMechanics
import Testing

/// TimberFailure against closed forms: its elastic part against OrthotropicPlaneStress, each
/// brittle mode's peak at its strength and its work to separation at its fracture energy over
/// the band, crushing's plateau and permanent set, secant unloading and the mixed index.
@Suite struct TimberFailureTests {
    /// Spruce as Sandhaas and van de Kuilen (HERON 58, 2013, Table 1) give it, 50 mm bands in
    /// the plane and 35 mm through it.
    static func spruce(band: Double = 0.05, through: Double = 0.035) throws -> TimberFailure {
        try TimberFailure(
            alongModulus: 11_000e6, acrossModulus: 370e6, shearModulus: 690e6, rollingModulus: 50e6,
            poisson: 0.35, tensionAlong: 24e6, compressionAlong: 36e6, tensionAcross: 0.7e6,
            compressionAcross: 4.3e6, shearStrength: 6.9e6, rollingStrength: 0.5e6,
            fibreEnergy: 60e3, splittingEnergy: 500, shearEnergy: 1200, rollingEnergy: 600,
            bandLength: band, throughBandLength: through)
    }

    typealias Strain = TimberFailure.Components

    /// Drives the law along `path(t)` for t from 0 to 1 in `steps` increments; every state.
    static func drive(_ law: TimberFailure, steps: Int = 20_000, from start: TimberFailure.State? = nil,
                      _ path: (Double) -> Strain) throws -> [TimberFailure.State] {
        var state = start ?? law.zeroState
        var states: [TimberFailure.State] = []
        for i in 1...steps {
            state = try law.evaluate(strain: path(Double(i) / Double(steps)), from: state)
            states.append(state)
        }
        return states
    }

    @Test func elasticPartIsOrthotropicPlaneStress() throws {
        let law = try Self.spruce()
        let elastic = try OrthotropicPlaneStress(
            youngAlong: 11_000e6, youngAcross: 370e6, shear: 690e6, poissonAlongAcross: 0.35)
        // Within OrthotropicPlaneStress's principal-strain domain (0.001).
        let strain = Strain(along: 4e-4, across: -3e-4, shear: 6e-4, alongThrough: 1e-3, rolling: 4e-3)
        let state = try law.evaluate(strain: strain, from: law.zeroState)
        let reference = try elastic.evaluate(
            strain: SIMD3(4e-4, -3e-4, 6e-4), grainAngleRadians: 0, frame: .init()).stress
        #expect(abs(state.stress.along - reference.x) <= 1e-9 * abs(reference.x))
        #expect(abs(state.stress.across - reference.y) <= 1e-9 * abs(reference.y))
        #expect(abs(state.stress.shear - reference.z) <= 1e-9 * abs(reference.z))
        #expect(state.stress.alongThrough == 690e6 * 1e-3)
        #expect(state.stress.rolling == 50e6 * 4e-3)
        #expect(state.fibre == 0 && state.splitting == 0 && state.rollingShear == 0)
    }

    /// Each brittle mode alone: its peak is its strength and the work to separate it its
    /// fracture energy over its band, the energy at initiation reckoned with the modulus the
    /// path loads (Q11, Q22 in-plane, G for shear), within 0.5%.
    @Test(arguments: ["fibre", "splitting", "shear", "rolling"])
    func modePeakAndEnergy(_ mode: String) throws {
        // Shear's energy spreads over no more than 35 mm, so its band is 20 mm here.
        let law = try Self.spruce(band: mode == "shear" ? 0.02 : 0.05)
        let q = 1 / (1 - 0.35 * 0.35 * 370e6 / 11_000e6)
        let (strength, energy, band, end): (Double, Double, Double, Double) =
            switch mode {
            case "fibre": (24e6, 60e3, 0.05, 0.1)
            case "splitting": (0.7e6, 500, 0.05, 0.06)
            case "shear": (6.9e6, 1200, 0.02, 0.08)
            default: (0.5e6, 600, 0.035, 0.08)
            }
        let states = try Self.drive(law) { t in
            switch mode {
            case "fibre": Strain(along: end * t)
            case "splitting": Strain(across: end * t)
            case "shear": Strain(shear: end * t)
            default: Strain(rolling: end * t)
            }
        }
        func stress(_ s: TimberFailure.State) -> Double {
            switch mode {
            case "fibre": s.stress.along
            case "splitting": s.stress.across
            case "shear": s.stress.shear
            default: s.stress.rolling
            }
        }
        let peak = states.map(stress).max()!
        #expect(abs(peak - strength) < 2e-3 * strength, "\(mode): peak \(peak)")
        #expect(stress(states.last!) == 0, "\(mode): separated")
        // The law's ratio reckons the in-plane modes' energy at initiation with E, where this
        // path loads them with Q = q E, so the work is G/L over q there.
        let expected = energy / band / (mode == "fibre" || mode == "splitting" ? q : 1)
        // Work along a path that loads one component is that component's alone; the Poisson
        // stresses do no work against zero strain.
        let work = states.last!.workDensity
        #expect(abs(work - expected) < 5e-3 * expected, "\(mode): work \(work), expected \(expected)")
    }

    @Test func crushingIsPlasticAndLeavesASet() throws {
        let law = try Self.spruce()
        let loaded = try Self.drive(law, steps: 2000) { t in Strain(along: -0.03 * t) }
        let last = loaded.last!
        #expect(abs(last.stress.along + 36e6) < 1e-3 * 36e6)
        #expect(last.fibre == 0)
        // Unloaded to zero stress: the plastic strain is what is left.
        let set = last.plasticAlong
        let unloaded = try law.evaluate(strain: Strain(along: set), from: last)
        #expect(abs(unloaded.stress.along) < 1e-6 * 36e6)
        #expect(abs(set - (-0.03 + 36e6 / (11_000e6 / (1 - 0.35 * 0.35 * 370e6 / 11_000e6)))) < 1e-9)
        // Across the grain likewise, at its own strength.
        let across = try Self.drive(law, steps: 2000) { t in Strain(across: -0.05 * t) }.last!
        #expect(abs(across.stress.across + 4.3e6) < 1e-3 * 4.3e6)
    }

    @Test func partlyBrokenUnloadsAlongItsSecant() throws {
        let law = try Self.spruce()
        let onset = 0.7e6 / (370e6 / (1 - 0.35 * 0.35 * 370e6 / 11_000e6))
        let softened = try Self.drive(law, steps: 4000) { t in Strain(across: 3 * onset * t) }.last!
        #expect(softened.splitting > 0 && softened.splitting < 1)
        let half = try law.evaluate(strain: Strain(across: 1.5 * onset), from: softened)
        #expect(abs(half.stress.across - softened.stress.across / 2) < 1e-9 * softened.stress.across)
        #expect(half.splitting == softened.splitting)
        // Closed in compression, the crack carries compression in full.
        let closed = try law.evaluate(strain: Strain(across: -onset), from: half)
        #expect(closed.stress.across < 0)
        #expect(abs(closed.stress.across + 0.7e6) < 1e-6 * 0.7e6)
    }

    @Test func splittingIndexMixesOpeningAndSliding() throws {
        let law = try Self.spruce()
        // Opening and in-plane sliding each at 1/sqrt(2) of their strengths: on the surface.
        let q22 = 370e6 / (1 - 0.35 * 0.35 * 370e6 / 11_000e6)
        let opening = 0.7e6 / q22 / 2.squareRoot()
        let sliding = 6.9e6 / 690e6 / 2.squareRoot()
        let below = try law.evaluate(
            strain: Strain(across: 0.999 * opening, shear: 0.999 * sliding),
            from: law.zeroState)
        #expect(below.splitting == 0 && below.splittingIndex < 1)
        let past = try law.evaluate(strain: Strain(across: 1.01 * opening, shear: 1.01 * sliding), from: below)
        #expect(past.splitting > 0)
        #expect(abs(past.splittingIndex - 1.01) < 1e-9)
    }

    @Test func aBandTooLongBreaksAtOnce() throws {
        // Rolling shear with 0.5 m through the thickness: its energy cannot spread that far.
        let law = try Self.spruce(through: 0.5)
        let onset = 0.5e6 / 50e6
        let before = try law.evaluate(strain: Strain(rolling: 0.99 * onset), from: law.zeroState)
        let after = try law.evaluate(strain: Strain(rolling: 1.01 * onset), from: before)
        #expect(before.rollingShear == 0 && after.rollingShear == 1 && after.stress.rolling == 0)
    }

    @Test func rejections() throws {
        #expect(throws: TimberFailure.MaterialError.self) {
            try TimberFailure(
                alongModulus: 11_000e6, acrossModulus: 370e6, shearModulus: 690e6, rollingModulus: 50e6,
                poisson: 0.35, tensionAlong: -1, compressionAlong: 36e6, tensionAcross: 0.7e6,
                compressionAcross: 4.3e6, shearStrength: 6.9e6, rollingStrength: 0.5e6, fibreEnergy: 60e3,
                splittingEnergy: 500, shearEnergy: 1200, rollingEnergy: 600, bandLength: 0.05,
                throughBandLength: 0.035)
        }
        let law = try Self.spruce()
        let other = try Self.spruce(band: 0.1)
        #expect(throws: TimberFailure.MaterialError.self) {
            try law.evaluate(strain: Strain(along: 1e-4), from: other.zeroState)
        }
        #expect(throws: TimberFailure.MaterialError.self) {
            try law.evaluate(strain: Strain(along: .nan), from: law.zeroState)
        }
        #expect(throws: TimberFailure.MaterialError.self) {
            try law.evaluate(strain: Strain(across: 0.2), from: law.zeroState)
        }
        // Trial evaluation leaves accepted history alone: the same input gives the same output.
        let a = try law.evaluate(strain: Strain(across: 1e-2), from: law.zeroState)
        let b = try law.evaluate(strain: Strain(across: 1e-2), from: law.zeroState)
        #expect(a.stress == b.stress && a.splitting == b.splitting)
    }
}
