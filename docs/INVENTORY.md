# Extraction inventory — 8 October 2026

Inventory taken while application work is paused. It identifies a bounded first move
and later candidates. The tables record the pre-extraction state; the subsequent
CAD extraction and adoption are recorded in [provenance](extraction/CAD_FOUNDATIONS.md).
See the [roadmap](../ROADMAP.md) for the longer sequence.

## Source baselines

| Source | Baseline | Working-tree qualification |
| --- | --- | --- |
| ContinuumKit | `9f781e0119dbf31fe9e5266ba4c5d2162c6d4520` | Clean before this inventory change |
| BombCAD | `ad130448dc8a3d8b3181ad0107defcd38c29aef3` | Pending gas-study/geometry/demo/docs edits and untracked `GasQuadratureTests.swift`; preserve them |
| SimulationKit | Same BombCAD revision, `Packages/SimulationKit` | Subtree clean and identical to archived commit |
| RoomCAD | Same BombCAD revision, `RoomCAD` | Subtree clean and identical to archived commit |
| Edgerton | No Git commit or origin in this checkout | Project content is untracked; hashes identify the inspected working tree |

**Follow-up checkpoint, 8 October:** Edgerton now has initial commit
`b810ca2054da9b44d15342d665c65954386e26a3`, a private
[GitHub remote](https://github.com/emmettl/edgerton) and an MIT licence for authored
code. The working tree is clean and every file hash in the original Edgerton inventory
still matches. See the [checkpoint record](inventory/2026-10-08-edgerton-checkpoint.json).
The table above remains the historical state at initial collection.

The [machine inventory](inventory/2026-10-08.json) records scoped file hashes,
SwiftPM targets/dependencies, resources and lexical imports/test annotations. It is
a source audit, not executed-test or physical-validation evidence. Scopes overlap:
BombCAD includes SimulationKit; RoomCAD belongs to the same Git repository. Edgerton
study movies/images are excluded; numerical source and verification text are included.
This manifest identifies content but is not a backup of uncommitted work.

| Scope | File records | SHA-256 content digest |
| --- | ---: | --- |
| SimulationKit | 15 | `4fc32fd0069e19106f464b30342e7c129228427a86913315a8d7ab0e7d17962f` |
| RoomCAD | 97 | `75856ac49fa14f238e9c2828bf503f62b753857db0b706728c3f56665ac7552d` |
| BombCAD selected code/tests/scripts | 214 | `2dc321495ebe93080b01efc08881e69ce7d67a2e1a8303f886cfa80f076a51d1` |
| Edgerton selected code/studies/calibration | 958 | `0f804236fbd5a586fbc2cab569ccca6ab983fae4cbd2f9150210a70d7e1c115c` |

At collection, all inspected application/package manifests declared Swift 6.4 and
macOS 15, while ContinuumKit declared Swift 6.0. The first extraction explicitly
adopted Swift 6.4.

## Fresh verification

SimulationKit and RoomCAD were tested on a committed-source archive on the physical
Mac mini, outside active application checkouts. Swift was 6.4; a direct device check
reported Apple M4. See [CAD evidence](inventory/evidence/2026-10-08-cad-tests.txt).

| Check | Result | Qualification |
| --- | --- | --- |
| SimulationKit | 15 tests in 4 suites passed | Includes offscreen cutaway/highlight rendering |
| RoomDocumentTests | 16 tests passed | Current document integration baseline |
| RoomCADTests | 27 tests passed | Application tests, not manual UI review |
| ImpulseResponseKitTests | 8 tests passed | Independent second extraction candidate |
| AuditionTests | 9 tests passed | Current consumer baseline; clips need not move |
| AcousticCoreTests, full run | 91 tests reported, one issue | `AbsorptionCalibrationTests.swift:24` expected the unfitted result to differ from 1.2 s by more than 10%; that assertion failed |
| AbsorptionCalibrationTests, isolated recheck | Both tests passed | Discrepancy unresolved; complete backend baseline is not green |
| Edgerton geometry/path study, local optimized compile | Passed | [Layered paths, stopping/work, invalid inputs](inventory/evidence/2026-10-08-edgerton-geometry.txt) |
| Edgerton scalar contact study, local optimized compile | Passed | [Analytic events, energy, composition, impulses](inventory/evidence/2026-10-08-edgerton-contact.txt) |

No fresh BombCAD gas/structural suite, Edgerton full mechanics suite or measured validation
was run. Tests/studies named below are inspected evidence unless listed above. No
tolerances or source implementations were changed.

## Recommended first move: shared CAD foundations

Extract **all five SimulationKit products together**, retaining module names. This
changes the package boundary without changing numerical behavior. Both CAD apps
already consume these products.

| Product | Implementation | Dependencies/resources | Existing checks |
| --- | --- | --- | --- |
| `SceneModel` | `Box.swift`, `Grid.swift` | simd | Codable bounds, indexing |
| `SceneView` | `OrbitCamera.swift` | SceneModel, Foundation, simd | Framing, view rays, picking |
| `SceneRender` | `SceneGeometry.swift`, `MeshRenderer.swift`, `OrbitControlView.swift` | SceneModel/View, Metal/MetalKit, AppKit/CoreGraphics; copied `Shaders/Scene.metal` | Normals, picking, offscreen cutaway/highlight |
| `GeometryImport` | `MeshFile.swift` | Foundation, simd | Bounded OBJ and ASCII/binary STL, grouping, malformed inputs; 3 tests |
| `DocumentKit` | `ProjectArchive.swift` | Foundation, CryptoKit | Archive integrity, bounds, paths/symlinks; 6 tests |

This is eight Swift files, one shader and four test files, plus the manifest/README.
The root BombCAD MIT licence covers the authored code. Preserve attribution and
record the source revision/digest.

### Compatibility constraints

- Keep **`dev.simulationkit.project`**, its schema version, required `scene.json` and
  `settings.json`, optional `view.json`, limits and checksums. Repository naming does
  not authorize a saved-file migration.
- Keep `BlastCore.Box`/`Grid` and `BlastRender.OrbitCamera` compatibility aliases,
  Codable representations, units and camera conventions.
- Preserve shader loading through `Bundle.module` and test it from an external Git
  consumer. SceneRender is macOS/UI-dependent; CPU products must not acquire that
  dependency. Apple simd does not imply Linux portability.
- MeshFile is an OBJ/STL reader. Room/building interpretation and external IFC
  conversion do not move with it.
- Current render tests return early without Metal. Retain the required device
  preflight and tighten that suite's device requirement during extraction.

### Concrete extraction and adoption plan

1. Recheck clean subtree hashes; copy the products, shader and tests into a focused
   ContinuumKit branch with provenance. Keep app sources unchanged initially.
2. Declare these products and Swift 6.4. Extend the clean consumer to exercise every
   public product: archives, import, geometry/camera and offscreen rendering.
3. Run independent debug tests and a release consumer on the mini, including resources.
4. After review and release authorization, adopt an exact prerelease by changing
   package identity/product references in BombCAD and RoomCAD. Keep module imports
   and aliases unchanged; commit each app's resolved dependency.
5. Check integration/builds, saved documents and resources before retiring the local
   package. Keep the AcousticCore full-suite discrepancy visible.

**Access gate at collection (now resolved):** ContinuumKit was private; BombCAD, including RoomCAD, is public.
Consumer resolution needs a public dependency or configured cross-repository read
access. A repository's Actions token does not automatically read another private
repository. Current clean-consumer checks use local Git and do not establish remote
private-repo access. Decide this before external adoption.

RoomCAD's independent repository split is a separate step. BombCAD's pending gas
changes and Edgerton's uncommitted tree are outside this first tranche.

## Subsequent candidates

Readiness is separate from physical accuracy. A standalone model can belong in core
with one consumer when its assumptions and verification are explicit.

| Candidate | Source and dependencies | Evidence / remaining gate | Recommendation |
| --- | --- | --- | --- |
| Response interchange | RoomCAD `ImpulseResponseKit`: 2 files, Foundation only | Fresh 8-test pass; preserve `dev.roomcad.impulse-response`, gains, timing and channels | **Released as `0.1.0-alpha.2`; adopted by standalone RoomCAD** |
| Acoustic backend | RoomCAD `AcousticCore`: 30 files; ImpulseResponseKit, Foundation/simd, Accelerate, Metal, Synchronization | Geometry, energy/decay, free-field/modes and CPU/GPU tests; calibration discrepancy; presets and validation scenes mixed with model code | Separate policy and resolve test reliability before moving the full backend |
| Linear wave evolution | RoomCAD `WaveSolver`, `MetalWaveSolver`, `WaveAccuracy`; Edgerton `WaveSolver`/`Waves.metal` | Matched source adapters and masked/curved/dissipative gates now exist; exact source map and [proposed contract](extraction/LINEAR_WAVE_UPDATE.md) are recorded | [Serial CPU candidate](extraction/LINEAR_WAVE_CPU.md) implemented with independent tests/clean consumer; Metal and app adoption follow separately |
| FFT/spectral helpers | RoomCAD `RealFFT` and band processing | Accelerate, internal API and normalization conventions; tested through acoustics | Add dedicated transform/normalization references before a numerical module |
| Ideal-gas wall reference | BombCAD `IdealGasWallRiemann` | Foundation only, internal API; shock/rarefaction/vacuum tests exist | Small gas-model candidate with explicit API and migrated references |
| Conservative gas packets/fluxes | BombCAD `FractionalGasTransport`, `FractionalEulerFlux`, `LimitedTubeFlux`, remap/piston helpers | simd/Foundation, internal types, caller-supplied geometry; transport/flux/wall/piston tests | Define a coherent reference module; distinct from the production GPU solver |
| Connected/moving cut volumes | BombCAD `ConnectedGasGroups`, `FractionalBoxGeometry`, sweeps/remap and rigid-box coupling | Volume/geometry and budgets studied; modified/untracked source; coupled spatial convergence open | Hold for committed checkpoint and numerical gates |
| Blast solver and spherical start | BombCAD `BlastSolver`, `SolverTypes`, `Refinement`, `SphericalBlast`, shaders | GPU state, masks, structure coupling, diagnostics and scenarios intertwined | Later backend extraction, separating gas evolution from orchestration |
| Adiabatic reservoir law | Edgerton `SupportedCavityPressure` | Law embedded in a chosen bore/spring/support fixture; work/refinement studies exist | Extract law and references, not the fixture as a generic gas model |
| Reservoir exchange/sinks | Edgerton `PressureEnergyMixing`/`PressureEnergyVenting` | Analytic exchange and energy sinks; VisualImpactError and breakthrough scheduling bind them to impact recordings | Separate pure operations from policy; do not imply mass/momentum transport |
| Geometry/path probes | Edgerton `TargetGeometry`, fixtures, probe laws | Fresh independent geometry study passed; explicit region ordering/reduced resistance | Eligible after source/licence checkpoint; keep geometry and resistance distinct |
| Scalar contact flow | Edgerton `TargetNormalContactSolver` | Foundation only; fresh analytic event/energy/impulse/composition pass | Strong primitive candidate after checkpoint; not general 3D collision |
| Krylov iteration | Edgerton `TargetKrylov` | Internal SIMD3-vector GMRES; `TargetMatrixFreeStudy` includes a known nonsymmetric restarted-solve oracle | Migrate oracle; define vector, input and failure contracts |
| Isotropic element law | Edgerton `TargetIsotropicTet` | Neo-Hookean/log-bulk kernel; TargetGeometryError and corrected gradient from TargetImplicitFaceContact; force/work/objectivity/isotropy studies | Separate helper/error contracts without changing material behavior |
| Larger mechanics | Edgerton cell/matrix-free/peel/contact/fracture families; BombCAD structure/shell/bond-slip models | Specialized studies, topology/recording dependencies and spatial/contact sensitivity | Keep stabilizing; move bounded verified components individually |
| Fitting mathematics | Edgerton `RelaxationCalibration`/`MaterialFit`; RoomCAD absorption fitting | Algorithms mixed with references, provenance and CSV/JSON or room policy | Separate algorithm, references and export; verify fitting contracts |

At initial collection, Edgerton lacked a source commit and licence record. That gate
is now resolved by the checkpoint above. Third-party reference excerpts retain their
attribution; the MIT licence covers authored code. Bulky generated exports remain
local with a size/hash catalogue, and are not required for the application build.

## Application-owned content

Keep BombCAD charge/scenario presets, building semantics and structural orchestration;
RoomCAD documents, authored presets/measured scenes, preview policy and credited dry
clips; Edgerton calibre inputs, visual effects, footage matching, impact scheduling and
native recording/export flows. Edgerton's cavity-union display surface depends on
visual capsule state and is not mechanical excavation.

External IFC conversion needs its own application/process and third-party licence audit.
The generic mesh reader can move without that importer.

## Reproducing the inventory

Generate SwiftPM descriptions for SimulationKit, RoomCAD, BombCAD and Edgerton using
`swift package --package-path ... describe --type json`. Name the outputs
`simulationkit-package.json`, `roomcad-package.json`, `bombcad-package.json` and
`edgerton-package.json`, then run:

```sh
python3 Scripts/inventory.py --bombcad /path/to/bombcad --edgerton /path/to/edgerton \
  --descriptions /path/to/descriptions --output /path/to/new-inventory.json
```

Use a new dated record; do not replace this baseline silently. The collector writes
only its output and excludes Git/build caches. Review candidate hashes and pending
edits before treating the pause as a source freeze.

Publication follow-up: the user authorized a public core, and `0.1.0-alpha.1` is now released. Cross-repository private authentication is no longer an adoption gate.


Repository follow-up, 8 October: response interchange is extracted and released;
[provenance and verification](extraction/IMPULSE_RESPONSE.md) record its independent
suite and actual Git consumer. [RoomCAD](https://github.com/emmettl/RoomCAD) is now
standalone, with its own physical Mac mini CI, source hashes and history map. Its
acoustic source and measured fixtures retain their bytes. The calibration and fitted-zone
reference fixtures use canonical receiver UUIDs after a stochastic full-suite failure;
[the separate test change](https://github.com/emmettl/RoomCAD/pull/1) preserves tolerances.

BombCAD's previously pending gas work is committed at
`bfc4f5f6ec16629ad390ebfc7017137c7b46a0ed`, pushed, and its full 377-test core suite
passes in [the checkpoint CI](https://github.com/emmettl/bombcad/actions/runs/37829822956).
The initial source/hash tables remain collection-time evidence. Committing that work
resolves its source-control gate; moving-geometry numerical readiness still needs its
separate convergence and contract checks.

## Current four-repository checkpoint — 10 October 2026

The [new dated collection](inventory/2026-10-10-four-repositories.json) records the
current standalone ContinuumKit, RoomCAD, BombCAD and Edgerton packages. The original
8 October snapshot above remains historical and unchanged. The collector retains
legacy nested-package mode and accepts explicit standalone --roomcad/--core paths.
Counts/imports/test annotations are lexical observations, not executed test results;
symlinks are excluded from the scoped file list, while their canonical test sources
are recorded. The collection is per-file and is not an atomic cross-repository snapshot.

Core at 0320015330d65e5a70ebca431657b7a9920d6971 has ten libraries, including both
released linear-wave backends. RoomCAD at 2bc11ed6a033e8642de4018e8e9ae9cfb4e1151c
has accepted both shared production defaults and retired duplicate masked CPU/GPU
implementations. Original controls, snapshots and independent benchmark provenance
remain available. Its 192-test and complete two-host output/packaging gates are linked
in the [retirement proof](https://github.com/emmettl/RoomCAD/blob/main/docs/benchmarks/RETIRED_ORIGINAL_METAL.md).
The optimized unmasked box CPU contract remains application-owned and distinct.

BombCAD at 4104864b63163e45810b5862c6e4057aa48c912d is clean in this collection.
Edgerton has active committed and uncommitted mechanics/rendering work; the snapshot
records its current hashes/status rather than presenting that work as a stable
extraction candidate. The mature scalar contact and GMRES candidates remain separate
from changing coupled material/contact/fracture systems. Their initial study evidence
does not establish readiness of all surrounding mechanics.

The next bounded candidate is BombCAD's Foundation-only IdealGasWallRiemann. Its
source at 0b4943def5ec50064d1e44b9ab0ab249c2689b15 has the recorded current hash
8008860fe21e94a5cc3cd2a1af1eea9d8457f91d6d341bc7a49de69c2a199064. Define normal
sign/wall frame, SI quantities, shock/rarefaction/vacuum and binary64 failure behavior,
then independently check jump/invariant/acoustic limits and a clean public consumer.
Its signalSpeed is an incident-state rate estimate, not an exact shock-front velocity
or a general downstream characteristic certificate. Bulk transport, moving-volume
integration and production blast GPU evolution remain separate gates.

Other gaps remain: heterogeneous fluids and Edgerton's different 2D forcing/damping
contract; finite-band FFT normalization references; conservative gas transport/coupled
geometry; fitting algorithms separated from measured-data policy; and bounded stable
mechanics primitives with explicit dimensional/ownership/failure contracts.

Following this inventory checkpoint, the ideal-gas wall candidate was released in
alpha.13 and adopted by [BombCAD #22](https://github.com/emmettl/bombcad/pull/22).
The source hashes above describe the pre-extraction collection. The
[next bounded gas plan](extraction/GAS_PACKET_PLAN.md) addresses prescribed packet
conservation first; no moving geometry or complete production flow model is implied.
