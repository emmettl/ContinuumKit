# CAD foundations extraction and adoption

Source: [BombCAD](https://github.com/emmettl/bombcad), commit
`ad130448dc8a3d8b3181ad0107defcd38c29aef3`, `Packages/SimulationKit`.
At extraction, the package subtree was clean while unrelated gas-study work was
pending in that repository. The imported code is MIT licensed; Louis Emmett's
attribution is retained.

The [file manifest](cad-foundations-source.json) records original paths and SHA-256
hashes. All eight module Swift files and `Scene.metal` retain their original bytes.
The four existing test files move to `Tests/CADFoundationsTests`; only the Metal-device
guard in `SceneRenderTests` changes, from an early return to a required device/queue.
No algorithms, public model/view APIs, saved-file identifiers or shader behavior change.

## Package changes

- Swift tools minimum is explicitly 6.4, matching the original package and applications.
- The five original products keep their names and dependency graph.
- The empty bootstrap product is removed; no released consumer depends on it.
- SceneRender keeps its copied shader directory and `Bundle.module` lookup.
- A permanent external consumer fixture uses only public APIs, built through a fetched
  Git dependency in release configuration. It checks every product and actual rendering.

## Verification and adoption

`Scripts/check.sh` checks the working tree, existing debug tests, Metal compute and
the committed release consumer. Consumer checks are independent of application targets.
[Verification evidence](cad-foundations-verification.json) records 15 passing tests
and the optimized Git consumer on both the development host and physical mini.
The consumer also passed an exact-version resolution check in a disposable tagged
clone before publication.

In isolated BombCAD source clones, manifest-only adapters to the candidate passed a
BombCAD release build and RoomCAD's 16 document plus 27 UI tests. Their module/shader
bytes match the final candidate. At that candidate stage, no full BombCAD or
AcousticCore suite or manual UI review was repeated. The previously observed acoustic calibration discrepancy remains
in the inventory; this extraction does not claim to resolve it.

Compatibility aliases (`BlastCore.Box`/`Grid`, `BlastRender.OrbitCamera`),
`dev.simulationkit.project` and the required JSON payload names remain unchanged.
RoomCAD's repository split remains separate.

## Publication

With user authorization, PR #1 was merged, ContinuumKit made public and the tested
`0.1.0-alpha.1` tag published at commit `80f2db8e6c290b48c26a801082b459987ca2ba3c`.
The [release workflow](https://github.com/emmettl/ContinuumKit/actions/runs/37826361790)
passed exact-version verification on the mini and created the prerelease. Public
Git resolution removes the original cross-repository authentication gate.

## Application adoption

[BombCAD PR #2](https://github.com/emmettl/bombcad/pull/2), merged at
`5309b0606028f166c41b6bb33f872805b817fbe0`, switches both CAD manifests
to the exact release and commits both resolved dependency files at the tag's source
revision. It retires the duplicate local implementation and tests, retaining a
historical package README. No numerical model source changes are included.

Both applications build and package from the actual public release. Their deep strict
ad-hoc signature checks and packaged shader hashes pass. The packaged RoomCAD snapshot
loads the new `ContinuumKit_SceneRender.bundle` and renders successfully. RoomCAD's
16 document and 27 UI tests pass; both applications' eight release-script tests pass.
The [full Mac mini repository check](https://github.com/emmettl/bombcad/actions/runs/37827888524)
also passes: lint, 107 BombDocument and 374 BlastCore tests, all RoomCAD suites
(including 91 AcousticCore tests), release/nightly scripts and build. The earlier
calibration discrepancy remains a historical reliability observation; no acoustic
implementation or assertion was changed.

The unrelated BombCAD gas-study checkpoint `bfc4f5f6ec16629ad390ebfc7017137c7b46a0ed`
is preserved locally; it is not part of the adoption PR.
