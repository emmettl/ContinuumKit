# Cloud report: building the CPU libraries on Linux

Branch `claude/project-thread-1k6ql0`, 18 October 2026, based on main at `12947d3`. Commit 1 below was merged in #100; this branch adds commit 2. This branch makes every ContinuumKit library that does not use Metal build and pass its tests on Linux. Apple platform builds are meant to be unchanged: every Linux path sits behind `#if os(Linux)` in the manifest or behind `canImport` in source. Nothing was built or tested on macOS, and no Metal code was built.

## What changed

### Commit 1: Glibc instead of Darwin

`import Darwin` is now guarded so that Linux imports Glibc instead. Both provide the C maths functions these files use, including the Bessel functions `j0` and `j1`.

- `Sources/BenchmarkSupport/CylinderModes.swift`
- `Tests/BenchmarkSupportTests/CylinderTests.swift`
- `Tests/SolidMechanicsTests/OrthotropicPlaneStressTests.swift`

### Commit 2: SolidMechanics, SpectralTransforms and DocumentKit

The SolidMechanics kernels and `RealFFT.swift` are frozen. `verify-isotropic-tet-source.py`, `verify-orthotropic-source.py` and `verify-real-fft-source.py` check them byte for byte or by SHA-256, and the FFT check also requires that `RealFFT.swift` imports exactly `Accelerate`. None of those files is changed. Instead, on Linux only, the manifest adds two stand-in targets under the module names those files import:

- **`Sources/LinuxSIMD`, module `simd`.** It provides `simd_double3x3` with the operators, transpose, inverse (by cofactors) and determinant that SolidMechanics uses, a minimal `simd_quatd`, and the vector functions. It re-exports Glibc, as Apple's simd brings the C maths functions with it.
- **`Sources/LinuxAccelerate`, module `Accelerate`.** It provides the six vDSP calls that `RealFFT.swift` makes. A plain radix-2 complex FFT reproduces vDSP's packed real format, with the DC term in the real part and the Nyquist term in the imaginary part of element 0, a forward transform scaled by 2, and a forward and inverse pair that together scale by 2n.

Once a module named `simd` exists, `#if canImport(simd)` would give different answers in different targets depending on build order. So on Linux, every target that imports simd or tests `canImport(simd)` depends on the stand-in. Those targets are SceneModel, SceneView, GeometryImport, CompressibleFlow, Numerics, SolidMechanics and their tests. As a result, their own `SIMDFallback.swift` files are no longer compiled on Linux, and **GMRES now builds on Linux** through the stand-in. The frozen GMRES file itself is unchanged.

DocumentKit is not frozen, so it is changed directly:

- `ProjectArchive.swift` imports CryptoKit only where it exists. The new `SHA256Fallback.swift` provides SHA-256 (FIPS 180-4) elsewhere.
- The `FileWrapper` bridge (`fileWrapper()` and `init(fileWrapper:)`) is compiled on Apple platforms only, because Linux Foundation has no `FileWrapper`. On Linux, DocumentKit keeps validation, hashing and the URL reader `read(from:)`, but it has no way to write a project package.

## Test results

All runs used Swift 6.4 (swift-6.4-RELEASE) on x86_64 Linux.

- `swift build --target` succeeds for SolidMechanics, SpectralTransforms, DocumentKit, BenchmarkSupport and `continuumbench` in the real package.
- `swift test` was run in a scratch copy of this commit. The copy appends lines to the manifest that remove the targets that cannot build on Linux: SceneRender, ContactSearchMetal, LinearAcousticsMetal, their tests, and CADFoundationsTests, which mixes SceneRender into its tests. **258 tests passed with no failures.** By target: BenchmarkSupportTests 93, LinearAcousticsTests 46, CompressibleFlowTests 39, NumericsTests 25 (including the 4 GMRES tests), SolidMechanicsTests 17, ImpulseResponseKitTests 12, SpectralTransformsTests 10, ContactSearchTests 9 and ThermodynamicsTests 7. Main gave 88 tests on Linux, and commit 1 alone gave 227.
- The RealFFTConsumer fixture was built and run on Linux against this commit, following `Scripts/check-real-fft-consumer.sh` by hand. The script's `sysctl` and `otool` steps are macOS-only, so `environment.json` was written with the same fields from `/proc/cpuinfo`. `verify-real-fft-output.py` passed: 437 FFT cases and 4,953 output values agree with its independent scalar DFT, inverse, Parseval, gain, circular-filtering and direct-convolution references. `test-real-fft-gate.py` passed its 13 corruption controls.
- DocumentKit's own tests are in CADFoundationsTests, which cannot build on Linux. Instead, `ProjectManifest.Asset` digests from the fallback were compared with Python's `hashlib.sha256` for 13 input lengths from 0 to 1 MiB, covering every padding boundary. All 13 matched.
- These verifiers pass: `verify-real-fft-source.py`, `verify-isotropic-tet-source.py`, `verify-orthotropic-source.py`, `verify-scalar-material-source.py`, `verify-gmres-source.py`, `verify-normal-contact-source.py` and `test-inventory.py`.
- No Python file was changed. `Scripts/check-doc-links.py` does not exist in this repository, so it was not run.

## Discrepancies and limitations

- **The FFT check's intent.** `verify-real-fft-source.py` still passes, but its message calls the FFT an "explicit Accelerate-only capability". On Linux, the stand-in now satisfies `import Accelerate`. Whether that is acceptable is the maintainer's call. If it is not, dropping the `Accelerate` target leaves SpectralTransforms Apple-only again and changes nothing else.
- **Two code paths.** On Linux, these results come from the stand-ins rather than from Apple's simd and vDSP. They pass the same tests and the independent FFT gate, but they may differ from Apple's in the last bits. A macOS run is still the reference.
- **Module names.** The stand-ins take the names `simd` and `Accelerate` on Linux. If a later Swift toolchain for Linux ships a module with either name, the manifest will need revisiting.
- **The FFT consumer on Linux.** Inside the RealFFTConsumer fixture, the frozen RoomCAD `OriginalFFT.swift` also compiled against the stand-in. So on Linux, its "original" and "shared" records are not independent of each other. The Python references are what make that run meaningful.
- **Still Apple-only:** SceneRender, ContactSearchMetal, LinearAcousticsMetal, their tests and CADFoundationsTests.
- **Reaching BombCAD.** BombCAD pins ContinuumKit to `0.1.0-alpha.28`, so this branch reaches BombCAD only after a new tag and a bump of that pin.

The wider survey is in the project's shared folder at `linux-build/FINDINGS.md`.
