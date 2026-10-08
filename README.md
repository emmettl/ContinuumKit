# ContinuumKit

Shared Swift foundations for RoomCAD, BombCAD and Edgerton. The package contains the existing CAD foundations from BombCAD's SimulationKit and
RoomCAD's application-independent response interchange, and a checked adiabatic reservoir
with independent conformance. [`0.1.0-alpha.3`](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.3)
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
| `BenchmarkSupport` | Versioned adiabatic/acoustic cases, analytic references and complete-field reports | Thermodynamics, Foundation |

Requires Swift 6.4 and macOS 15 or later. CPU products do not depend on SceneRender.
The full test suite and clean render consumer require a Metal device.

## Verification

From a clean committed candidate:

```sh
CONTINUUMKIT_REQUIRE_METAL=1 bash Scripts/check.sh
```

Checks run 15 CAD foundation tests, 12 response interchange tests and 14 adiabatic and 9 acoustic numerical/conformance tests and an isolated Git consumer in release
configuration. That consumer imports all eight public libraries, round-trips an archive
on disk, reads OBJ geometry, checks camera/grid/picking contracts and verifies actual
offscreen pixels from the fetched package's shader. No path dependency or source alias
is used. The response checks include independently authored WAV bytes, format/dimension
compatibility, conditioning history and a disk round trip through the fetched product. CI runs on the physical Mac mini; see [CI operations](docs/CI.md).

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
