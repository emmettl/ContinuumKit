# ContinuumKit

Shared Swift foundations for RoomCAD, BombCAD and Edgerton. The package contains the existing CAD foundations from BombCAD's SimulationKit and
RoomCAD's application-independent response interchange, and a checked adiabatic reservoir
with independent conformance. [`0.1.0-alpha.16`](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.16)
is the current prerelease; earlier tags remain available for existing consumers.

| Product / module | Contents | Dependencies |
| --- | --- | --- |
| `SceneModel` | Codable bounds and Cartesian grids, metres with z up | Apple simd |
| `SceneView` | Orbit camera, framing, rays and picking helpers | SceneModel, Foundation, simd |
| `SceneRender` | Scene geometry, Metal rendering, snapshots and orbit-control view | SceneModel/View, Metal/MetalKit, AppKit/CoreGraphics |
| `GeometryImport` | Bounded OBJ and ASCII/binary STL reading | Foundation, simd |
| `DocumentKit` | Versioned project containers, assets, integrity and bounded readers | Foundation, CryptoKit |
| `ImpulseResponseKit` | Response metadata, float WAV I/O and common channel conditioning | Foundation |
| `Thermodynamics` | Checked uniform adiabatic reservoir potential and signed work | Foundation |
| `CompressibleFlow` | Planar ideal-gas wall, prescribed gas packets and paired Euler reference | Foundation, simd |
| `LinearAcoustics` | Checked masked CPU updates, pressure forcing and receiver observation; explicit serial/parallel execution | Swift standard library, Dispatch |
| `LinearAcousticsMetal` | Resident GPU updates, pressure forcing, receiver sampling and bundled kernels | LinearAcoustics, Foundation, Metal |
| `BenchmarkSupport` | Versioned adiabatic/acoustic cases, analytic references and complete-field reports | Thermodynamics, Foundation |

Requires Swift 6.4 and macOS 15 or later. CPU products do not depend on SceneRender.
The full test suite and clean render consumer require a Metal device.

## Verification

From a clean committed candidate:

```sh
CONTINUUMKIT_REQUIRE_METAL=1 bash Scripts/check.sh
```

The complete package gate builds and tests all eleven public libraries, then verifies
six clean optimized Git consumers: all-library CAD/model smoke, CPU waves, resident
Metal waves, ideal-gas wall reference, prescribed gas packets and paired Euler flux. CPU-only consumers
reject Metal/UI framework linkage. Complete reference/source/geometry reports retain
physical gaps separately from numerical conformance. CI runs on the physical Mac mini;
see [CI operations](docs/CI.md). The committed candidate is fetched through Git, with
an exact version requirement at release verification.

The module implementations and shader are copied byte-for-byte. The rendering test
now fails on missing Metal instead of returning early. Saved identifiers, including
`dev.simulationkit.project`, are retained. See [CAD provenance](docs/extraction/CAD_FOUNDATIONS.md) and
[response provenance](docs/extraction/IMPULSE_RESPONSE.md).

## Consumption and ownership

Consumers use an exact tag, add only needed products, and commit resolved dependencies:

```swift
.package(url: "https://github.com/emmettl/ContinuumKit.git", exact: "0.1.0-alpha.3")
// In an application target's dependencies:
.product(name: "SceneModel", package: "continuumkit")
```

All products share a repository version. The repository is public; consumers can
resolve its tagged Git source without cross-repository credentials.

Applications own their schemas, semantic model conversion, scenarios, authored
presentation, workflows and integration tests. Future independently verified models
bring their own conformance and benchmark suites; no speculative targets are added.

See the [roadmap](ROADMAP.md), [inventory](docs/INVENTORY.md), [architecture](docs/ARCHITECTURE.md),
[verification policy](docs/VERIFICATION.md), [contributing](CONTRIBUTING.md) and
[release procedure](docs/RELEASING.md). MIT licensed, with original attribution retained.

The first numerical tranche is released in `0.1.0-alpha.3`, with a `continuumbench`
command and [adiabatic contract/reference cases](docs/benchmarks/ADIABATIC.md). Existing
application releases remain pinned independently. Benchmark source adapters exercise the
current Edgerton calculation and BombCAD's single-volume work reference.

The next committed benchmark candidate adds [axial travelling-pulse and rigid-wall
conformance](docs/benchmarks/ACOUSTICS.md), with independent spatial/temporal references.
It does not move an acoustic solver or change the current release tag.

The next boundary candidate adds [mixed-axis modes and real impedance](docs/benchmarks/ACOUSTIC_BOUNDARIES.md), with explicit unsupported capabilities.

Masked acoustic geometry contracts: [scope and checks](docs/benchmarks/MASKED_DOMAINS.md).

The [serial CPU wave candidate](docs/extraction/LINEAR_WAVE_CPU.md) has seventeen
independent contract/reference tests, exact-block source comparison and an optimized
Git consumer that requires no Metal or UI framework. It is present on main and is
not included in `alpha.5`; Metal and app integration remain later gates.

The [resident Metal wave candidate](docs/extraction/LINEAR_WAVE_METAL.md) has eleven
actual-device contract/reference tests, exact packaged kernel provenance and its own
optimized Git consumer. CPU and GPU requirements remain explicit.

`0.1.0-alpha.6` releases the source-free CPU/Metal wave products after [exact-tag
mini verification](https://github.com/emmettl/ContinuumKit/actions/runs/38003236841):
169 tests and all three consumers resolve the exact version. [Actual benchmark
readiness](docs/extraction/SHARED_WAVE_READINESS.md) includes 96 complete exact
original/shared records. Production source/receiver integration is separate.

The released [CPU pressure-forcing API](docs/extraction/LINEAR_WAVE_FORCING_CPU.md)
adds checked sparse source plans without application imports. Its declared phase order,
independent work/refinement references and legacy damped-forcing accuracy limit are
included in `0.1.0-alpha.7` after exact-tag verification.

The released [resident Metal forcing API](docs/extraction/LINEAR_WAVE_FORCING_METAL.md)
uses the checked CPU source description with opaque device mappings and 128-sample
staging. It preserves original GPU arithmetic and explicit completion/snapshot semantics.

`0.1.0-alpha.8` releases [CPU receiver observation](docs/extraction/LINEAR_WAVE_OBSERVATION_CPU.md)
and [resident Metal sampling](docs/extraction/LINEAR_WAVE_OBSERVATION_METAL.md),
with owned bounded histories, native clocks, backend arithmetic identity and explicit
one-frame lookahead/final-half-step policy. Its [exact-tag mini check](https://github.com/emmettl/ContinuumKit/actions/runs/38014077324)
passed 207 tests and all three optimized exact-version consumers. [Publication proof](docs/extraction/alpha8-release-verification.json)
records scope and identities. Source/receiver geometry, microphone mixing, cancellation
and production application adoption remain caller-owned.

`0.1.0-alpha.9` releases [explicit synchronous CPU slabs and fused finite certification](docs/extraction/CPU_WAVE_EXECUTION.md).
Serial remains the API default; callers choose parallel counts and small-grid policy.
The [exact-tag mini release](https://github.com/emmettl/ContinuumKit/actions/runs/38019570607)
passed 215 tests and all three exact-version consumers, including actual packaged
parallel CPU and CPU-only linkage. [Publication proof](docs/extraction/alpha9-release-verification.json)
records identities. Complete model reports remain identical to alpha.8 across both
Macs; application throughput/default and measured acoustic accuracy remain separate.

Alpha.13 releases the [planar ideal-gas wall reference](docs/extraction/IDEAL_GAS_WALL.md),
independently verified and adopted in BombCAD. The next
[prescribed gas packet candidate](docs/extraction/PRESCRIBED_GAS_PACKETS.md) retains
source arithmetic and explicit dry cleanup, with independent conservation references
and complete native original/shared comparison. Release and application adoption
remain distinct gates.

[Alpha.14](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.14)
releases prescribed gas-packet conservation after exact-tag mini verification of
247 tests and five fetched version-pinned consumers.
[Publication proof](docs/extraction/gas-packet-release.json) records identities;
application adapter and complete integration verification remain the next step.

BombCAD now consumes alpha.14's packet operator after [complete native application
verification](https://github.com/emmettl/bombcad/pull/23); its production duplicate
is retired. Application fluxes, geometry, reservoir and body/timestep policy remain
separate from the shared packet-conservation contract.

The [prescribed Euler flux candidate](docs/extraction/FRACTIONAL_EULER_FLUX.md) adds
a fixed-gamma CPU reference with independent characteristic, wall-ledger and
shock/contact/acoustic refinement gates. Alpha.15 passes its exact-tag
release gate and is published. Alpha.16 releases public Result assembly
for app-owned SSPRK2 after complete two-host and exact-tag 261-test/six-consumer
verification. BombCAD adoption remains a separate integration gate.

BombCAD now consumes alpha.16's Euler reference after [complete application
adoption](https://github.com/emmettl/bombcad/pull/24), including app-owned multistage
result assembly. Geometry, reconstruction, time/body policy and production air
remain separate. The next independent primitive is the [real FFT verification plan](docs/extraction/REAL_FFT_PLAN.md).

The implemented [checked real FFT candidate](docs/extraction/REAL_FFT.md) adds
`SpectralTransforms` with explicit Accelerate capability, independent DFT/inverse
and direct convolution references, protected original/shared native conformance
and safe public boundaries. Alpha.17 releases it; RoomCAD adoption remains separate.

[Alpha.17](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.17)
now releases `SpectralTransforms` after the exact-tag physical-mini gate passes
271 tests, seven optimized exact-version consumers and actual Metal work. Complete
437-case FFT arrays remain byte-identical to the accepted two-host candidate.
[Publication proof](docs/extraction/alpha17-release-verification.json) records
immutable identities; RoomCAD adoption remains separate.
