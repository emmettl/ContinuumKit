# Cloud report: Linux build of the Bessel-function files

Branch `claude/project-thread-1k6ql0`, 18 October 2026, based on main at `de567c2`. The change touches three Swift files and this report. No Metal, Python, fixture, manifest or documentation file was changed.

## What changed

`import Darwin` is now guarded so that Linux imports Glibc instead. Both libraries provide the C maths functions these files use, including the Bessel functions `j0` and `j1`. Apple platforms still import Darwin, so their build is unchanged.

- `Sources/BenchmarkSupport/CylinderModes.swift`
- `Tests/BenchmarkSupportTests/CylinderTests.swift`
- `Tests/SolidMechanicsTests/OrthotropicPlaneStressTests.swift`

The third file also imports simd, so SolidMechanicsTests still cannot build on Linux. It is changed so that the Darwin import is not a second blocker when SolidMechanics is ported.

## Test results

All runs used Swift 6.4 (swift-6.4-RELEASE) on x86_64 Linux. Swift and Metal were not built or tested on macOS.

- `swift build --target BenchmarkSupport` and `swift build --target continuumbench` succeed in the real package. Before the change both failed with "no such module 'Darwin'".
- `swift test` was run in a scratch copy whose manifest lists only the Linux-clean targets: SceneModel, SceneView, GeometryImport, ImpulseResponseKit, Thermodynamics, CompressibleFlow, ContactSearch, Numerics, LinearAcoustics and BenchmarkSupport. The full manifest cannot resolve on Linux because it declares Metal targets. Seven test targets ran and **227 tests passed with no failures**: CompressibleFlowTests 39, ContactSearchTests 9, NumericsTests 21, ThermodynamicsTests 7, ImpulseResponseKitTests 12, BenchmarkSupportTests 93 and LinearAcousticsTests 46. Before the change only the first five could build, giving 88 tests.
- `python3 -I Scripts/verify-gmres-source.py` still passes.
- No Python file was touched. `Scripts/check-doc-links.py` does not exist in this repository, so it was not run.

## Discrepancies found

- **GMRES is compiled out on Linux without warning.** `Sources/Numerics/GMRESImplementation.swift`, `RestartedGMRES.swift` and `Tests/NumericsTests/RestartedGMRESTests.swift` are each wrapped whole in `#if canImport(simd)`, so on Linux the solver does not exist and its 4 tests are skipped without any message. The engine only needs `simd_dot`, but this branch does not add a fallback. The engine file is frozen: `Scripts/verify-gmres-source.py` hashes its body and compares it with `docs/extraction/gmres-source.json` and the `Fixtures/GMRESConsumer` copy. Any change to that file means updating the provenance record, which is the maintainer's decision.
- **Still blocked on Linux**, not attempted here: SolidMechanics (`simd_double3x3` and its inverse, transpose and determinant), SpectralTransforms (Accelerate's vDSP real FFT) and DocumentKit (CryptoKit SHA-256). The Metal targets cannot build on Linux.
- BombCAD pins ContinuumKit to `0.1.0-alpha.28`, so this change reaches BombCAD only after a new tag and a bump of that pin.

The wider survey is in the project's shared folder at `linux-build/FINDINGS.md`.
