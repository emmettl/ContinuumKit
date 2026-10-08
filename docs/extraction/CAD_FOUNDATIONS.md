# CAD foundations extraction candidate

Source: [BombCAD](https://github.com/emmettl/bombcad), commit
`ad130448dc8a3d8b3181ad0107defcd38c29aef3`, `Packages/SimulationKit`.
The package subtree is clean even though unrelated gas-study work is pending in that
repository. The imported code is MIT licensed; Louis Emmett's attribution is retained.

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
Candidate and final evidence will be recorded after actual execution.

BombCAD and RoomCAD retain their current local package dependency. Their compatibility
aliases (`BlastCore.Box`/`Grid`, `BlastRender.OrbitCamera`) and original shared package
must remain until both have adopted a reviewed release. `dev.simulationkit.project`
and the required JSON payload names are deliberately unchanged.

Before real adoption, decide public dependency availability or configure authenticated
cross-repository read access. Do not create a release tag or alter repository visibility
as part of this extraction candidate. RoomCAD's repository split remains separate.
