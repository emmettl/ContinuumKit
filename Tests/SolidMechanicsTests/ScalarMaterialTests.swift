import Foundation
import SolidMechanics
import Testing

@Suite(.serialized) struct ScalarMaterialTests {
    @Test(arguments: ["Compression", "Damage"])
    func independentFrozenCoupons(_ kind: String) throws {
        let fixtures = Bundle.module.resourceURL!.appendingPathComponent("Fixtures/P2\(kind)")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let reference = scratch.appendingPathComponent("reference.csv")
        _ = FileManager.default.createFile(atPath: reference.path, contents: nil)
        let handle = try FileHandle(forWritingTo: reference)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", fixtures.appendingPathComponent("reference.csv.gz").path]
        process.standardOutput = handle
        try process.run(); process.waitUntilExit(); try handle.close()
        #expect(process.terminationStatus == 0)
        let args = ["", fixtures.appendingPathComponent("input.json").path, reference.path, scratch.path]
        if kind == "Compression" { try P2CompressionVerification.run(args) }
        else { try P2DamageVerification.run(args) }
        let report = try JSONSerialization.jsonObject(with: Data(contentsOf: scratch.appendingPathComponent("verification.json"))) as! [String: Any]
        #expect(report["passed"] as? Bool == true)
        #expect(report["cases"] as? Int == (kind == "Compression" ? 12 : 24))
        #expect(report["samples"] as? Int == (kind == "Compression" ? 1964 : 2796))
        #expect((report["checks"] as? Int ?? 0) >= (kind == "Compression" ? 30257 : 77524))
    }

    @Test func compressionAnalyticPermanentSet() throws {
        let law = try VeneerCompression(young: 1000, yieldStress: 2, hardening: 100)
        let loaded = try law.evaluate(strain: -0.02, from: law.zeroState)
        let alpha = (20.0 - 2.0) / 1100.0
        #expect(abs(loaded.alpha - alpha) < 1e-16)
        let unloaded = try law.evaluate(strain: -alpha, from: loaded)
        #expect(abs(unloaded.stress) < 1e-14)
        #expect(abs(unloaded.workDensity - (50 * alpha * alpha + 2 * alpha)) < 1e-15)
        #expect(unloaded.alpha == loaded.alpha)
    }

    @Test func damageSeparationAndStateCompatibility() throws {
        let law = try VeneerDamage(mode: .shear, modulus: 1000, strength: 2, fractureEnergy: 0.01, bandLength: 0.1)
        let failed = try law.evaluate(strain: -law.failureStrain, from: law.zeroState)
        #expect(failed.damage == 1)
        #expect(abs(failed.dissipationDensity - 0.1) < 1e-15)
        let reclosed = try law.evaluate(strain: 0, from: failed)
        #expect(reclosed.dissipationDensity == failed.dissipationDensity)
        let tensile = try VeneerDamage(mode: .tension, modulus: 1000, strength: 2, fractureEnergy: 0.01, bandLength: 0.1)
        #expect(throws: VeneerDamage.MaterialError.incompatibleState) { try tensile.evaluate(strain: 0, from: failed) }
    }
}
