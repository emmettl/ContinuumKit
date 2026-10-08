# ContinuumKit

Shared Swift foundations for RoomCAD, BombCAD and Edgerton. The first release
contains the existing CAD foundations from BombCAD's SimulationKit package.
`0.1.0-alpha.1` is the first CAD foundations release. The next release also includes
RoomCAD's application-independent impulse-response interchange product.

| Product / module | Contents | Dependencies |
| --- | --- | --- |
| `SceneModel` | Codable bounds and Cartesian grids, metres with z up | Apple simd |
| `SceneView` | Orbit camera, framing, rays and picking helpers | SceneModel, Foundation, simd |
| `SceneRender` | Scene geometry, Metal rendering, snapshots and orbit-control view | SceneModel/View, Metal/MetalKit, AppKit/CoreGraphics |
| `GeometryImport` | Bounded OBJ and ASCII/binary STL reading | Foundation, simd |
| `DocumentKit` | Versioned project containers, assets, integrity and bounded readers | Foundation, CryptoKit |
| `ImpulseResponseKit` | Response metadata, float WAV I/O and common channel conditioning | Foundation |

Requires Swift 6.4 and macOS 15 or later. CPU products do not depend on SceneRender.
The full test suite and clean render consumer require a Metal device.

## Verification

From a clean committed candidate:

```sh
CONTINUUMKIT_REQUIRE_METAL=1 bash Scripts/check.sh
```

Checks run 15 CAD foundation tests, 12 response interchange tests and an isolated Git consumer in release
configuration. That consumer imports all six public products, round-trips an archive
on disk, reads OBJ geometry, checks camera/grid/picking contracts and verifies actual
offscreen pixels from the fetched package's shader. No path dependency or source alias
is used. The response checks include independently authored WAV bytes, format/dimension
compatibility, conditioning history and a disk round trip through the fetched product. CI runs on the physical Mac mini; see [CI operations](docs/CI.md).

The module implementations and shader are copied byte-for-byte. The rendering test
now fails on missing Metal instead of returning early. Saved identifiers, including
`dev.simulationkit.project`, are retained. See [extraction provenance](docs/extraction/CAD_FOUNDATIONS.md).

## Consumption and ownership

Consumers use an exact tag, add only needed products, and commit resolved dependencies:

```swift
.package(url: "https://github.com/emmettl/ContinuumKit.git", exact: "0.1.0-alpha.1")
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
