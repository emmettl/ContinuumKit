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
- Complete: BombCAD and RoomCAD adopt the exact `0.1.0-alpha.1` release, including
  resolved dependencies and packaged shader-resource checks; the local copy is retired.
- Complete: response interchange extracted with twelve independent tests and a fetched
  public consumer, released as `0.1.0-alpha.2` and adopted by standalone RoomCAD.
- Complete: RoomCAD repository split, relevant history/old tag preserved and dedicated
  physical Mac mini CI with packaged rendering verification.
- Complete: first numerical tranche — a checked adiabatic potential, analytic/reference
  conformance, versioned reports and source-based Edgerton/BombCAD comparison.
- Complete: `0.1.0-alpha.3` numerical release, verified from its exact tag on the Mac mini.
- Pending: application adoption of the reservoir and subsequent individual model extractions.

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
| `LinearAcoustics` | Wave evolution, source/probe contracts and supported boundary laws | Edgerton waves and RoomCAD CPU/Metal wave solvers |
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
