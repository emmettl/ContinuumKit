# ContinuumKit roadmap

Planning baseline: 8 October 2026. This is an outline of ownership, sequencing and
readiness gates, not authorization to extract code or publish releases now.
Application development continues while candidates mature.

## Current position

- Complete: independent GitHub repository, SwiftPM bootstrap, MIT licence, contribution
  and ownership guidance, clean Git-consumer check and manual tagged-release workflow.
- Complete: dedicated Mac mini runner and an actual Metal compute smoke check in CI.
- Complete: [initial extraction inventory](docs/INVENTORY.md), source hashes and fresh
  CAD-package/selected primitive baselines taken while other work is paused.
- Complete: Edgerton's initial source commit, private GitHub remote and authored-code
  MIT licence; inventoried source hashes remain unchanged.
- Complete: the five existing CAD foundation products are imported with their
  original tests and an external release consumer; see [provenance](docs/extraction/CAD_FOUNDATIONS.md).
- Complete: public `0.1.0-alpha.1` CAD foundations release, verified on the mini.
- Complete: closed-box ray/segment query contract and independent verification,
  released as `0.1.0-alpha.4` after exact-tag Mac mini checks; see
  [geometry provenance](docs/extraction/BOX_QUERIES.md).
- Complete: BombCAD and RoomCAD adopt the exact `0.1.0-alpha.1` release, including
  resolved dependencies and packaged shader-resource checks; the local copy is retired.
- Complete: response interchange extracted with twelve independent tests and a fetched
  public consumer, released as `0.1.0-alpha.2` and adopted by standalone RoomCAD.
- Complete: RoomCAD repository split, relevant history/old tag preserved and dedicated
  physical Mac mini CI with packaged rendering verification.
- Complete: first numerical tranche — a checked adiabatic potential, analytic/reference
  conformance, versioned reports and source-based Edgerton/BombCAD comparison.
- Complete: `0.1.0-alpha.3` numerical release, verified from its exact tag on the Mac mini.
- Complete: Edgerton adopts the exact `0.1.0-alpha.3` uniform reservoir law, with
  application-owned coupled integration/parity checks on the physical Mac mini.
- Complete: bounded axial travelling-pulse and rigid-wall source comparison, with
  independent spatial/temporal references and actual Edgerton Metal / RoomCAD CPU/Metal
  adapters. The axial reference/conformance API is included in `0.1.0-alpha.4`;
  no acoustic solver has moved.
- Complete: mixed-axis rigid modes and normal real-impedance source checks, with
  explicit unsupported capabilities and independent accuracy/work references.
  This additional boundary API remains an unreleased candidate.
- Complete: independent fixed-lattice dissipative temporal reference and normal
  impedance time-refinement gates (unreleased benchmark candidate).
- Complete: full 3D rigid-box modes with individual pressure/x/y/z velocity
  spatial and temporal gates, including anisotropic grids (unreleased candidate).
- Complete: damped oblique impedance box modes with independent complex roots,
  reflection fits, work and spatial/temporal gates (unreleased candidate).
- Complete: independent masked/curved/dissipative and tilted-pulse source contracts,
  directed wall-selection correction and exact thin plan/mesh history comparisons.
- Complete: [proposed wave-update API and pinned source map](docs/extraction/LINEAR_WAVE_UPDATE.md).
- Candidate: [serial source-free masked CPU update](docs/extraction/LINEAR_WAVE_CPU.md)
  with independent Core tests and a committed CPU-only Git consumer. Metal,
  source/receiver integration and application adoption remain separate gates;
  heterogeneous fluids remain open.

Follow the MotionStudies pattern: the shared repository owns reusable contracts,
implementations and their independent verification; applications own their use and
integration. A synthetic consumer checks the released package boundary.

## Intended contents

Names below are provisional except for the existing SimulationKit products. Create
targets only when their implementation and tests are ready. Products share a package
version but can be adopted independently by an application's targets.

| Area / possible product | What could belong here | Candidate and initial consumers |
| --- | --- | --- |
| `SceneModel` | Bounds, grids and scene-independent spatial contracts | Existing SimulationKit; BombCAD and RoomCAD |
| `SceneView` | Orbit camera, framing, view rays and picking | Existing SimulationKit; BombCAD and RoomCAD |
| `SceneRender` | Generic Metal scene geometry, resource loading and rendering helpers | Existing SimulationKit; CAD apps, possibly Edgerton later |
| `GeometryImport` | Model readers, import validation and unit handling | Existing SimulationKit mesh reader; more loaders after a separate audit |
| `DocumentKit` | Generic archive/container integrity and bounded readers | Existing SimulationKit; application schemas remain in app repos |
| `Numerics` | Integration, interpolation, linear operators and error estimation | Stable routines from solver work; avoid assuming identical algorithms |
| `Thermodynamics` | Independently specified equations of state and adiabatic reservoir laws | Edgerton cavity reservoirs and BombCAD gas models |
| `LinearAcoustics`, later `LinearAcousticsMetal` | Initially the checked source-free masked complete-step update; explicit GPU backend later | RoomCAD masked path first; Edgerton needs a separate 2D/force/damping adapter |
| `CompressibleFlow` | Conservative gas transport, wall fluxes and moving-volume operations | BombCAD reference experiments, then fuller flow solvers if ready |
| `SolidMechanics` | Independently verified material, contact or fracture components | Edgerton/BombCAD candidates; specialized laws may stay separate |
| `BenchmarkSupport` and benchmark executables | Case descriptions, reference solutions, conformance, convergence and result reporting | Shared suite infrastructure plus model-owned cases |

RoomCAD's image-source/ray acoustics may also qualify as standalone models. They do
not have to use the wave solver's API. Audio response representation/analysis is a
later candidate when the library/application boundary is clear. A specialized model
can live in core with one application consumer if it is independently useful and
verifiable; universal reuse is not required.

Numerics, model contracts and geometry must not depend on UI targets. Metal-specific
backends and view helpers have explicit dependencies and device requirements.
Document policy, source/material preset interpretation, simulation scenarios, authored
presentation and application replay/export orchestration remain application-owned.

## Stage 1 — Inventory at a natural development checkpoint

When a component stops changing rapidly, record its source repository/revision,
dependencies, consumers, tests, resources, licence and known limits. Distinguish
implemented behavior from experiments and speculative generalization.

Start with `bombcad/Packages/SimulationKit`, whose five products are already consumed
by BombCAD and RoomCAD. Its renderer has Metal-dependent tests, despite the older
README describing a smaller CPU-only package: audit actual code and tests together.
Record units, coordinate frames, normals, precision and existing compatibility aliases.

**Exit:** a bounded first extraction is selected, with reproducible current consumer
results and an attribution/provenance record. No solver rewrite is bundled with it.

## Stage 2 — First useful package release

Move the selected SimulationKit products with their tests and resources. Preserve
existing module names where practical to limit consumer churn. Prove that the
external package loads shaders and other resources from its own bundle and that CAD
behavior is preserved. Extend the clean consumer beyond the bootstrap import to
exercise every released product.

The first extraction explicitly raises the package minimum to Swift 6.4, matching
the original package and its applications.

Release a reviewed prerelease only when authorized, then pin and verify each adopting
app. RoomCAD can consume the external package while still nested in BombCAD; creating
its independent app repository is a separate step, not a blocker for package reuse.

**Exit:** at least one substantive product is tested from tagged Git source and used
by an application, with documented parity. Complete both CAD adoptions for products
that currently have both consumers before retiring the original shared copy.

## Stage 3 — Establish numerical comparison infrastructure

This can proceed independently of scene-helper extraction when useful cases exist.
Define explicit case capabilities and versioned result conventions; use thin adapters
to exercise existing solvers without moving them first.

| Initial case | Primary evidence | Applicable implementations |
| --- | --- | --- |
| Travelling pulse | Speed, amplitude, phase and space/time refinement | Linear wave solvers; small-disturbance gas solver under matched assumptions |
| Rigid-wall reflection | Boundary amplitude, sign, timing and oblique-grid behavior | Applicable acoustic and gas solvers |
| Adiabatic expansion | Pressure/volume relation, boundary work and energy balance | Reservoir law and applicable gas reference |
| Prescribed piston, subsequently free piston | Wall impulse, work and coupled trajectory refinement | Applicable moving-boundary gas/mechanics models |

Include closed-box modes and impedance reflection when the relevant boundary contracts
are ready. Publish independent references, errors and limits; agreement between two
solvers or a small conservation residual alone is not an accuracy proof. Match
dimensionality, parameters and physical assumptions when comparing implementations.

**Exit:** reproducible cases, an independent oracle and at least one real adapter.
Unsupported capabilities are explicit; no implementation gets a false passing result.

## Stage 4 — Extract models individually as they become ready

Begin with bounded thermodynamic laws or numerical operations when their contracts
and independent checks are stable. Then consider linear acoustics and gas/boundary
components. Preserve distinct reservoir, linear-wave and nonlinear-flow assumptions;
do not turn Edgerton's energy diffusion or venting sinks into a mass/momentum model
by renaming them.

Each model brings its own conformance suite, reference cases and convergence evidence.
Factor reusable numerical code only when its required behavior is understood; large
solvers may move intact first if that produces a cleaner, independently testable unit.

**Exit per component:** the readiness checklist below passes, the package release is
verified, and its application adapter passes integration checks. Other models may
remain in flux; their status does not block this component.

## Stage 5 — Broader mechanics and mature benchmarking

Consider contact, deformation, fracture, moving cut cells and larger solver backends
as their independent evidence matures. Key gates include spatial/contact convergence,
consistent boundary geometry, mass/momentum inheritance on separation and correctly
accounted work. Keep calibrated gel, peel and concrete laws distinct where necessary.

Add scheduled convergence suites and measured validation when real benchmarks exist.
Coordinate sustained GPU work with the mini's other repositories before enabling
heavy schedules. Record hardware/load metadata and separate numerical failures from
performance variation. Fast CI remains bounded and missing required GPU access fails.

**Exit:** useful model modules have reproducible evidence and clear supported regimes;
applications still own end-to-end measured scenes and presentation acceptance.

## Readiness checklist and adoption

Track candidates as **application experiment → stabilizing → core-ready → released →
adopted**. These are per-component states, not a requirement to finish the entire plan.

- A documented contract covers units, coordinates, state, assumptions and limitations.
- Construction and verification require no application target or application lifecycle.
- Independent references and meaningful error tolerances accompany the implementation.
- Relevant space/time refinement is checked; physical validation claims are separate.
- Dependencies, shader/assets packaging, licence and extraction provenance are explicit.
- A clean Git consumer exercises the actual public products, including required GPU work.
- An exact tagged release passes application integration/parity checks before adoption.

Keep architecture changes, numerical changes and application adoption reviewable as
separate steps. Treat published tags as immutable; retain previous versions and evidence.
Do not set calendar deadlines until a particular extraction is scheduled. The
[inventory](docs/INVENTORY.md) recommends the existing five SimulationKit products as
the first bounded move, with compatibility, toolchain and dependency-access gates.

Masked-domain candidate: exact aligned boxes and disconnected chambers now have independent
contracts; real application source conformance is required before extraction. Curved/staircase
geometry, absorbing masked walls and isolated oblique pulse reflection remain separate gaps.

Curved-boundary candidate: rigid cylinder geometry and all-field spatial/time contracts
are bounded separately; absorbing masked walls and isolated oblique pulses remain gaps.

Absorbing curved-wall gate: audit prescribed-load physical admittance separately from
isolated numerical wall flow. Full Cartesian stair-face area predicts a persistent 4/π
bias for the cylindrical side; geometry-aware admittance and coupled transient continuum
verification must precede production extraction. Diagnostic gap reports are not passes.


Local wall-area correction candidate: [RoomCAD #10](https://github.com/emmettl/RoomCAD/pull/10)
normalizes mesh/plan admittance using local normals against the unchanged core area
contract. Coupled absorbing-cylinder continuum convergence is the next independent
gate; area/substep conformance alone does not make the solver ready for extraction.


Coupled absorbing-cylinder candidate: [independent continuum Bessel and damped-graph
contracts](docs/benchmarks/ABSORBING_CYLINDER.md) separate geometry, timestep and full
wall-work histories. Actual source conformance is required; this adds no production
solver extraction or release tag.


Tilted pulse candidate: [causally isolated plane reflection and central patch work](docs/benchmarks/TILTED_PULSE.md)
separate angular coefficient/arrival, spatial geometry and fixed-graph time checks.
Spatial failures remain explicit gaps; actual source evidence is required before
shared production extraction.

The [equivalent floor-plan and mesh extrusion audit](docs/benchmarks/EXTRUDED_LAYOUT.md)
isolated five thin-mesh wall-selection gaps under anisotropic spacing. The directed
material-selection fix in [RoomCAD #14](https://github.com/emmettl/RoomCAD/pull/14)
closes them with strict geometry regression and the established extrusion area
quadrature. Full application and actual CPU/Metal regressions pass on the mini.
The matching thin-mesh tilted pulse in [RoomCAD #15](https://github.com/emmettl/RoomCAD/pull/15)
passes under the unchanged independent case with exact full plan/mesh field/work
parity. The [wave-update design](docs/extraction/LINEAR_WAVE_UPDATE.md) now records
units, clocks, owned state, source blocks and staged acceptance gates. It authorizes
no move or release by itself. Geometry, source/receiver and band/response policy
remain app-owned; AcousticCore remains app-owned.

Resident Metal candidate: [two exact pinned kernels and owned GPU state](docs/extraction/LINEAR_WAVE_METAL.md)
now have actual-device ABI, complete-field/reference, residency and failure-clock tests.
The next gap is exact candidate RoomCAD benchmark binding across its real geometry
and wall-work suites; source/receiver application integration and release follow.

Source-free wave release readiness: [the audited component boundary](docs/extraction/SHARED_WAVE_READINESS.md)
now has all 96 actual RoomCAD original/shared records passing unchanged frozen
oracles with exact whole histories/work/errors. CPU-only and explicit Metal products
are ready for a reviewed prerelease and exact-tag verification. Production source,
receiver and lifetime integration remain the next application/model-interface gap.

Published: `0.1.0-alpha.6` includes source-free LinearAcoustics and its explicit
resident Metal backend, verified from its exact tag on the mini. The next model
interface gap is safe forcing/source-write and receiver/clock/lifetime integration;
application adoption should preserve existing source scaling and energy ledgers.
