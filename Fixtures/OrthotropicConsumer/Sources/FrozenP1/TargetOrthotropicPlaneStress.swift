import Foundation
import simd

/// Small-strain, linear elastic plane stress in an oriented material sheet.
/// Chosen-model kernel only: no damage, plasticity, rate or thermal response.
/// Strain components are (epsilon_xx, epsilon_yy, engineering gamma_xy) in
/// the supplied sheet frame; stress components are (sigma_xx, sigma_yy, tau_xy).
/// This is a pure trial evaluation: rejection never mutates accepted history.
public struct TargetOrthotropicPlaneStress: Sendable {
    public enum MaterialError: Error { case invalidParameters, invalidFrame, invalidTrial }

    /// Orthonormal sheet axes in world coordinates. The grain angle is relative
    /// to x, toward y. A rigid world rotation changes these axes, not the strain.
    public struct Frame: Sendable {
        public let x: SIMD3<Double>
        public let y: SIMD3<Double>
        public var normal: SIMD3<Double> { simd_cross(x, y) }

        public init(x: SIMD3<Double> = SIMD3(1, 0, 0),
                    y: SIMD3<Double> = SIMD3(0, 1, 0)) throws {
            guard Self.finite(x), Self.finite(y),
                  abs(simd_dot(x, x) - 1) <= 1e-10,
                  abs(simd_dot(y, y) - 1) <= 1e-10,
                  abs(simd_dot(x, y)) <= 1e-10 else { throw MaterialError.invalidFrame }
            self.x = x; self.y = y
        }

        private static func finite(_ v: SIMD3<Double>) -> Bool {
            v.x.isFinite && v.y.isFinite && v.z.isFinite
        }
    }

    public struct Result: Sendable {
        public let strain: SIMD3<Double>
        public let stress: SIMD3<Double>
        /// Symmetric world Cauchy stress within this infinitesimal model;
        /// normal/shear tractions out of the sheet are zero by plane stress.
        public let worldStress: simd_double3x3
        public let energyDensity: Double
        public var dissipationDensity: Double { 0 }
    }

    public let youngAlong: Double
    public let youngAcross: Double
    public let shear: Double
    public let poissonAlongAcross: Double
    public let poissonAcrossAlong: Double
    public let maximumPrincipalStrain: Double
    private let q11: Double, q22: Double, q12: Double

    /// Reciprocity nu21 = nu12 E2/E1 and positive-definite compliance are
    /// required. Reject a compliance denominator <= 1e-12 and overflowing
    /// stiffness. The declared strain bound must be in (0, 0.01]; P1 uses 0.001.
    public init(youngAlong: Double, youngAcross: Double, shear: Double,
                poissonAlongAcross: Double, maximumPrincipalStrain: Double = 0.001) throws {
        guard youngAlong.isFinite, youngAlong > 0,
              youngAcross.isFinite, youngAcross > 0,
              shear.isFinite, shear > 0, poissonAlongAcross.isFinite,
              maximumPrincipalStrain.isFinite, maximumPrincipalStrain > 0,
              maximumPrincipalStrain <= 0.01 else { throw MaterialError.invalidParameters }
        let nu21 = poissonAlongAcross * (youngAcross / youngAlong)
        let denominator = 1 - poissonAlongAcross * nu21
        let a = youngAlong / denominator, b = youngAcross / denominator
        let c = poissonAlongAcross * b
        guard nu21.isFinite, denominator.isFinite, denominator > 1e-12,
              a.isFinite, b.isFinite, c.isFinite else { throw MaterialError.invalidParameters }
        self.youngAlong = youngAlong; self.youngAcross = youngAcross; self.shear = shear
        self.poissonAlongAcross = poissonAlongAcross; poissonAcrossAlong = nu21
        self.maximumPrincipalStrain = maximumPrincipalStrain
        q11 = a; q22 = b; q12 = c
    }

    public func evaluate(strain: SIMD3<Double>, grainAngleRadians: Double,
                         frame: Frame) throws -> Result {
        guard strain.x.isFinite, strain.y.isFinite, strain.z.isFinite,
              grainAngleRadians.isFinite,
              abs(strain.x) <= maximumPrincipalStrain,
              abs(strain.y) <= maximumPrincipalStrain,
              abs(strain.z) <= 2 * maximumPrincipalStrain else { throw MaterialError.invalidTrial }
        let mean = 0.5 * (strain.x + strain.y)
        let radius = hypot(0.5 * (strain.x - strain.y), 0.5 * strain.z)
        guard max(abs(mean + radius), abs(mean - radius)) <= maximumPrincipalStrain else {
            throw MaterialError.invalidTrial
        }
        let m = cos(grainAngleRadians), n = sin(grainAngleRadians)
        // Tensor transform: off-diagonal strain is half engineering shear.
        let e1 = m*m*strain.x + n*n*strain.y + m*n*strain.z
        let e2 = n*n*strain.x + m*m*strain.y - m*n*strain.z
        let gamma = 2*m*n*(strain.y - strain.x) + (m*m - n*n)*strain.z
        let s1 = q11*e1 + q12*e2, s2 = q12*e1 + q22*e2, tau = shear*gamma
        let stress = SIMD3(m*m*s1 + n*n*s2 - 2*m*n*tau,
                           n*n*s1 + m*m*s2 + 2*m*n*tau,
                           m*n*(s1 - s2) + (m*m - n*n)*tau)
        let energy = 0.5 * (e1*s1 + e2*s2 + gamma*tau)
        // S = sxx x⊗x + syy y⊗y + txy (x⊗y + y⊗x).
        let columns = (0..<3).map { i in
            stress.x * frame.x[i] * frame.x + stress.y * frame.y[i] * frame.y
                + stress.z * (frame.y[i] * frame.x + frame.x[i] * frame.y)
        }
        guard stress.x.isFinite, stress.y.isFinite, stress.z.isFinite,
              energy.isFinite, energy >= 0,
              columns.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw MaterialError.invalidTrial
        }
        return .init(strain: strain, stress: stress,
                     worldStress: simd_double3x3(columns: (columns[0], columns[1], columns[2])),
                     energyDensity: energy)
    }
}
