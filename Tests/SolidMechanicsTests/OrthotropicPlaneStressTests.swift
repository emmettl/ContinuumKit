import Foundation
import simd
import Darwin

private enum StudyError: Error { case failed(String) }

import SolidMechanics
import Testing

@Suite struct OrthotropicPlaneStressTests {
    @Test func frozenP1LawObjectivityEnergyAndDomain() throws {
        let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        try Self.run(fixtures: fixtures, output: output)
    }

    static func run(fixtures: URL, output: URL) throws {
        let args = ["", fixtures.appendingPathComponent("input.json").path,
                    fixtures.appendingPathComponent("constitutive-reference.csv").path,
                    fixtures.appendingPathComponent("bending-reference.csv").path,
                    fixtures.appendingPathComponent("rotated-reference.csv").path]
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [String: Any]
        func number(_ key: String) -> Double { (fixture[key] as! NSNumber).doubleValue }
        let material = try OrthotropicPlaneStress(youngAlong: number("E1_Pa"),
            youngAcross: number("E2_Pa"), shear: number("G12_Pa"), poissonAlongAcross: number("nu12"))
        let frame = try OrthotropicPlaneStress.Frame()
        var groups: [String: (count: Int, error: Double, tolerance: Double)] = [:]
        var comparisons = "kind,control,step,angle_degrees,stress_x_Pa,stress_y_Pa,shear_Pa,energy_density_J_per_m3\n"

        func check(_ group: String, _ error: Double, tolerance: Double = 1e-6) throws {
            guard error.isFinite, error <= tolerance else { throw StudyError.failed("\(group): \(error) exceeds \(tolerance)") }
            let old = groups[group] ?? (0, 0, tolerance)
            groups[group] = (old.count + 1, max(old.error, error), tolerance)
        }
        func vectorError(_ a: SIMD3<Double>, _ b: SIMD3<Double>, scale: Double) -> Double {
            max(abs(a.x-b.x), abs(a.y-b.y), abs(a.z-b.z))/scale
        }
        func matrixError(_ a: simd_double3x3, _ b: simd_double3x3, scale: Double) -> Double {
            (0..<3).map { vectorError(a[$0], b[$0], scale: scale) }.max()!
        }
        func rows(_ path: String) throws -> [[String]] {
            try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: { $0.isNewline }).dropFirst().map {
                $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            }
        }
        func d(_ row: [String], _ index: Int) throws -> Double {
            guard let v = Double(row[index]), v.isFinite else { throw StudyError.failed("invalid reference number") }
            return v
        }

        // Frozen P1 uniaxial stress and shear cycles, including compression/unload.
        let constitutive = try rows(args[2])
        guard constitutive.count == 21 else { throw StudyError.failed("expected 21 constitutive samples") }
        for (index, row) in constitutive.enumerated() {
            let strain = try SIMD3(d(row, 2), d(row, 3), d(row, 4))
            let expected = try SIMD3(d(row, 5), d(row, 6), d(row, 7))
            let energy = try d(row, 8)
            let result = try material.evaluate(strain: strain, grainAngleRadians: 0, frame: frame)
            let scale = max(1, abs(expected.x), abs(expected.y), abs(expected.z))
            try check("frozen-constitutive-stress", vectorError(result.stress, expected, scale: scale))
            try check("frozen-constitutive-energy", abs(result.energyDensity-energy)/max(1, abs(energy)))
            try check("zero-dissipation", abs(result.dissipationDensity), tolerance: 0)
            comparisons += "constitutive,\(row[0]),\(index),0,\(result.stress.x),\(result.stress.y),\(result.stress.z),\(result.energyDensity)\n"
        }

        // Supplemental reference produced by Python's closed-form rotated Q,
        // independently of this kernel's tensor-transform implementation.
        let rotated = try rows(args[4])
        guard rotated.count == 20 else { throw StudyError.failed("expected 20 rotated samples") }
        for (index, row) in rotated.enumerated() {
            let angle = try d(row, 0), strain = try SIMD3(d(row, 1), d(row, 2), d(row, 3))
            let expected = try SIMD3(d(row, 4), d(row, 5), d(row, 6)), energy = try d(row, 7)
            let result = try material.evaluate(strain: strain, grainAngleRadians: angle * .pi / 180, frame: frame)
            let scale = max(1, abs(expected.x), abs(expected.y), abs(expected.z))
            try check("rotated-reference-stress", vectorError(result.stress, expected, scale: scale))
            try check("rotated-reference-energy", abs(result.energyDensity-energy)/max(1, abs(energy)))
            comparisons += "rotated,mixed,\(index),\(angle),\(result.stress.x),\(result.stress.y),\(result.stress.z),\(result.energyDensity)\n"

            // Energy derivatives must return stress with ENGINEERING shear convention.
            let h = 1e-8
            var tangent = simd_double3x3()
            for j in 0..<3 {
                var plus = strain, minus = strain
                plus[j] += h; minus[j] -= h
                let rp = try material.evaluate(strain: plus, grainAngleRadians: angle * .pi / 180, frame: frame)
                let rm = try material.evaluate(strain: minus, grainAngleRadians: angle * .pi / 180, frame: frame)
                let derivative = (rp.energyDensity-rm.energyDensity)/(2*h)
                try check("energy-gradient", abs(derivative-result.stress[j])/scale)
                tangent[j] = (rp.stress-rm.stress)/(2*h)
            }
            try check("tangent-symmetry", matrixError(tangent, tangent.transpose, scale: material.youngAlong))
        }

        // Integrate kernel stress/energy through every ply with two Gauss points.
        // No spatial mesh or shell assembly is involved.
        let layups = fixture["layups_deg"] as! [String: [Double]]
        let thickness = number("ply_thickness_m"), area = number("length_m")*number("width_m")
        let bending = try rows(args[3])
        guard bending.count == 122 else { throw StudyError.failed("expected 122 bending samples") }
        var bendingCSV = "layup,step,curvature_per_m,Mx_N_per_unit_width,My_N_per_unit_width,energy_J,constraint_work_J\n"
        var prior: [String: (k: Double, mx: Double, work: Double)] = [:]
        for row in bending {
            let name = row[0], k = try d(row, 2)
            guard let angles = layups[name], angles.count == 3 else { throw StudyError.failed("unknown layup") }
            var moments = SIMD3<Double>.zero, energy = 0.0
            for (ply, angle) in angles.enumerated() {
                let center = Double(ply-1)*thickness
                for sign in [-1.0, 1.0] {
                    let z = center+sign*thickness/(2*sqrt(3.0))
                    let r = try material.evaluate(strain: SIMD3(-z*k, 0, 0), grainAngleRadians: angle * .pi / 180, frame: frame)
                    moments -= z*r.stress*(thickness/2)
                    energy += area*r.energyDensity*(thickness/2)
                    try check("zero-dissipation", abs(r.dissipationDensity), tolerance: 0)
                }
            }
            let old = prior[name] ?? (0, 0, 0)
            let work = old.work+area*(old.mx+moments.x)*(k-old.k)/2
            prior[name] = (k, moments.x, work)
            let expectedMx = try d(row, 3), expectedMy = try d(row, 4), expectedEnergy = try d(row, 5), expectedWork = try d(row, 6)
            try check("frozen-bending-Mx", abs(moments.x-expectedMx)/max(1, abs(expectedMx)))
            try check("frozen-bending-My", abs(moments.y-expectedMy)/max(0.01, abs(expectedMy)))
            try check("frozen-bending-energy", abs(energy-expectedEnergy)/max(1e-6, abs(expectedEnergy)))
            try check("frozen-bending-work", abs(work-expectedWork)/max(1e-6, abs(expectedEnergy)))
            try check("elastic-work-closure", abs(work-energy)/0.006566037735849055)
            bendingCSV += "\(name),\(row[1]),\(k),\(moments.x),\(moments.y),\(energy),\(work)\n"
        }

        // Arbitrary-axis rigid world rotations, not merely in-plane grain changes.
        let axis = simd_normalize(SIMD3<Double>(1, 2, 3))
        let strain = SIMD3<Double>(1e-4, -2e-5, 3e-5)
        for degrees in [30.0, 90.0] {
            let c = cos(degrees * .pi / 180), s = sin(degrees * .pi / 180)
            func rotate(_ v: SIMD3<Double>) -> SIMD3<Double> { c*v+s*simd_cross(axis, v)+(1-c)*simd_dot(axis, v)*axis }
            let rotation = simd_double3x3(columns: (rotate(SIMD3(1,0,0)), rotate(SIMD3(0,1,0)), rotate(SIMD3(0,0,1))))
            let movedFrame = try OrthotropicPlaneStress.Frame(x: rotate(frame.x), y: rotate(frame.y))
            for grain in [0.0, 30.0, 90.0] {
                let base = try material.evaluate(strain: strain, grainAngleRadians: grain * .pi / 180, frame: frame)
                let moved = try material.evaluate(strain: strain, grainAngleRadians: grain * .pi / 180, frame: movedFrame)
                let scale = max(1, simd_length(base.stress))
                try check("world-stress-objectivity", matrixError(moved.worldStress, rotation*base.worldStress*rotation.transpose, scale: scale))
                try check("world-energy-objectivity", abs(moved.energyDensity-base.energyDensity)/base.energyDensity)
                try check("plane-stress-normal-traction", simd_length(moved.worldStress*movedFrame.normal)/scale)
                try check("world-stress-symmetry", matrixError(moved.worldStress, moved.worldStress.transpose, scale: scale))
            }
        }

        // Isotropic limit and valid negative Poisson ratio protect generic reuse.
        let isotropic = try OrthotropicPlaneStress(youngAlong: 1e9, youngAcross: 1e9,
            shear: 1e9/(2*1.3), poissonAlongAcross: 0.3)
        let isotropicBase = try isotropic.evaluate(strain: strain, grainAngleRadians: 0, frame: frame)
        for angle in [0.3, 0.7, 1.2] {
            let r = try isotropic.evaluate(strain: strain, grainAngleRadians: angle, frame: frame)
            try check("isotropic-limit", vectorError(r.stress, isotropicBase.stress, scale: simd_length(isotropicBase.stress)))
        }
        let auxetic = try OrthotropicPlaneStress(youngAlong: 1e9, youngAcross: 1e9, shear: 1e9, poissonAlongAcross: -0.25)
        let auxeticResult = try auxetic.evaluate(strain: SIMD3(1e-4, 2.5e-5, 0), grainAngleRadians: 0, frame: frame)
        try check("auxetic-uniaxial", vectorError(auxeticResult.stress, SIMD3(1e5,0,0), scale: 1e5))

        func rejects(_ group: String, _ expected: OrthotropicPlaneStress.MaterialError,
                     _ operation: () throws -> Void) throws {
            do { try operation() }
            catch let error as OrthotropicPlaneStress.MaterialError {
                switch (expected, error) {
                case (.invalidParameters, .invalidParameters), (.invalidFrame, .invalidFrame), (.invalidTrial, .invalidTrial):
                    try check(group, 0, tolerance: 0); return
                default: throw StudyError.failed("wrong rejection type: \(group)")
                }
            }
            throw StudyError.failed("accepted invalid input: \(group)")
        }
        for value in [0.0, -1.0, Double.nan, Double.infinity] {
            for field in 0..<3 {
                try rejects("invalid-moduli", .invalidParameters) {
                    _ = try OrthotropicPlaneStress(youngAlong: field == 0 ? value : 1e10,
                        youngAcross: field == 1 ? value : 1e9, shear: field == 2 ? value : 5e8, poissonAlongAcross: 0.25)
                }
            }
        }
        for value in [Double.nan, Double.infinity, 4.0, sqrt(10*(1-5e-13))] {
            try rejects("invalid-compliance", .invalidParameters) {
                _ = try OrthotropicPlaneStress(youngAlong: 1e10, youngAcross: 1e9, shear: 5e8, poissonAlongAcross: value)
            }
        }
        try rejects("overflowing-stiffness", .invalidParameters) {
            _ = try OrthotropicPlaneStress(youngAlong: .greatestFiniteMagnitude,
                youngAcross: .greatestFiniteMagnitude, shear: 5e8, poissonAlongAcross: 0.8)
        }
        for limit in [0.0, -0.001, 0.02, Double.nan, Double.infinity] {
            try rejects("invalid-domain", .invalidParameters) {
                _ = try OrthotropicPlaneStress(youngAlong: 1e10, youngAcross: 1e9, shear: 5e8,
                    poissonAlongAcross: 0.25, maximumPrincipalStrain: limit)
            }
        }
        for axes in [(SIMD3<Double>(1.01,0,0), SIMD3<Double>(0,1,0)),
                     (SIMD3<Double>(1,0,0), SIMD3<Double>(cos(0.1),sin(0.1),0)),
                     (SIMD3<Double>(.nan,0,0), SIMD3<Double>(0,1,0)),
                     (SIMD3<Double>(1,0,0), SIMD3<Double>(0,.infinity,0))] {
            try rejects("invalid-frame", .invalidFrame) { _ = try OrthotropicPlaneStress.Frame(x: axes.0, y: axes.1) }
        }
        var accepted = try material.evaluate(strain: strain, grainAngleRadians: 0.3, frame: frame)
        let original = accepted
        let invalidStrains = [SIMD3<Double>(.nan,0,0), SIMD3<Double>(0,.infinity,0), SIMD3<Double>(0,0,.nan),
                              SIMD3<Double>(0.0011,0,0), SIMD3<Double>(0,0,0.0021),
                              SIMD3<Double>(0.0009,0.0009,0.0004), SIMD3<Double>(-0.0011,0,0)]
        for invalid in invalidStrains {
            try rejects("invalid-trial", .invalidTrial) {
                accepted = try material.evaluate(strain: invalid, grainAngleRadians: 0.3, frame: frame)
            }
            try check("rejected-trial-retains-accepted-state", vectorError(accepted.strain, original.strain, scale: 1), tolerance: 0)
            try check("rejected-trial-retains-accepted-state", vectorError(accepted.stress, original.stress, scale: 1), tolerance: 0)
            try check("rejected-trial-retains-accepted-state", abs(accepted.energyDensity-original.energyDensity), tolerance: 0)
            try check("rejected-trial-retains-accepted-state", matrixError(accepted.worldStress, original.worldStress, scale: 1), tolerance: 0)
        }
        for angle in [Double.nan, Double.infinity] {
            try rejects("invalid-angle", .invalidTrial) {
                accepted = try material.evaluate(strain: strain, grainAngleRadians: angle, frame: frame)
            }
            try check("rejected-angle-retains-accepted-state", vectorError(accepted.stress, original.stress, scale: 1), tolerance: 0)
        }
        // Signed pure-shear endpoint at the declared principal-strain bound.
        for value in [-0.002, 0.002] {
            let r = try material.evaluate(strain: SIMD3(0,0,value), grainAngleRadians: 0, frame: frame)
            try check("strain-boundary", abs(r.stress.z-material.shear*value)/abs(r.stress.z))
        }

        try comparisons.write(to: output.appendingPathComponent("material-comparison.csv"), atomically: true, encoding: .utf8)
        try bendingCSV.write(to: output.appendingPathComponent("integrated-bending-comparison.csv"), atomically: true, encoding: .utf8)
        let summary: [String: Any] = ["terminal_reason": "passed within material-kernel scope",
            "scope": "elastic plane-stress kernel and through-ply constitutive integration; no shell assembly, spatial mesh or measured validation",
            "maximum_principal_strain": material.maximumPrincipalStrain,
            "checks": groups.mapValues { ["count": Double($0.count), "max_normalized_error": $0.error, "tolerance": $0.tolerance] },
            "total_checks": groups.values.reduce(0) { $0+$1.count }]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("kernel-checks.json"))
        print("PASS orthotropic material kernel: \(groups.values.reduce(0) { $0+$1.count }) checks; 21 frozen constitutive, 20 rotated and 122 through-ply bending samples")
    }
}
