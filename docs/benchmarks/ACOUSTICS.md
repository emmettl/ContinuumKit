# Axial acoustic conformance, version 1

This tranche benchmarks existing application calculations. It does not move an
acoustic solver into core or create a speculative `LinearAcoustics` product.
`BenchmarkSupport` owns the cases, references, evaluation and result contract.
Applications own their source adapters and actual finite-difference/Metal updates.

## Physical case and independent references

Both cases are a one-dimensional pressure perturbation uniform across transverse
axes, extruded through the application's actual 2D/3D grid. The matched domain is
0 ≤ x ≤ 0.25 m, density 1.25 kg/m³ and sound speed 320 m/s, with no damping, moving
source, audio conditioning or diffuse-decay correction. These are declared chosen
parameters, not water/air calibration. The initial right-going pulse is
F(x)=cos⁴(π(x−0.075)/0.05) Pa within |x−0.075|<0.025 m, zero outside.
At t=0 the normal velocity is F(x)/(ρc). Both ends are rigid. The travelling case
ends at cT=0.1 m, before reaching the right wall; reflection ends at cT=0.275 m,
after a right-wall bounce and before returning to the left wall.

The continuum reference is p=F(x−ct)+F(2L−x−ct),
u=[F(x−ct)−F(2L−x−ct)]/(ρc). The right-wall pressure image has positive sign;
normal velocity cancels at the wall. It gives 2 Pa at the wall at (L−0.075)/c,
and a 1 Pa returned peak with reversed velocity. The supported duration makes
additional left-wall images zero. The method follows the even extension for a
Neumann boundary in [Cambridge's wave-equation notes](https://www.damtp.cam.ac.uk/user/examples/B8Ld.pdf);
the acoustic hard-wall condition is described in its
[wave-scattering notes](https://www.damtp.cam.ac.uk/user/examples/3C8La.pdf).
Golden states, the first-order acoustic equations and independently integrated
energy check the reference. Exact continuum energy per unit transverse area is
A²·35r/(64ρc²) J/m², from the cos⁸ integral.

Pressure is sampled at cell centres and integer times; normal velocity is sampled
on faces at time t−dt/2. This clock distinction is essential for staggered schemes,
also documented by [k-Wave](https://www.k-wave.org/documentation/example_ivp_recording_particle_velocity.php).
Initialization uses the fixed physical p(0),u(0) with a Taylor half kick
u(−dt/2)=u(0)+dt·∇p(0)/(2ρ). It does not retune initial velocity using numerical
phase speed to manufacture accurate propagation.

## Independent spatial and temporal refinement

Space uses 96/192/384 axial cells with dt held fixed at the finest grid's nominal
Courant number 0.3. It compares every captured pressure/velocity field with the
continuum translation/image solution.

Time holds 192 cells fixed and halves dt twice (nominal Courant 0.6/0.3/0.15).
Its oracle is the exact continuous-time solution of that fixed spatial lattice,
using cosine pressure and sine velocity eigenmodes, frequencies
ωₖ=2c/dx·sin(kπ/(2N)), and projections of the same p(0),u(0).
This removes the spatial-error floor and avoids interpreting mixed space/time
error or cancellation as temporal convergence. A separate two-cell oscillator
provides an independent golden check. The temporal reference is not the continuum
solution and is named explicitly in each report.

Both series require pressure L2 error to refine at order 1.7–2.3 at each halving.
At the finest level: pressure relative L2 <1%; maximum pressure and velocity errors
(normalized by A and A/ρc) <3%; Fourier amplitude error <1%, phase error <0.01 rad,
and pre-reflection phase-derived speed error <1%. The first spatial Fourier
component is measured against its reference at every capture, without arrival-window
or peak-picking choices. Reflection requires wall pressure ratio within 0.02 of 2
and returned pulse amplitude within 1% of 1. Wall pressure uses a quadratic
Neumann extrapolation of the last two cell centres at the prescribed hit capture.

The leapfrog quadratic energy, with u⁻·u⁺ rather than u² at the pressure clock,
must drift less than 1e-4; initial error versus continuum energy <1%; normalized
mean-pressure drift <1e-5; boundary normal velocity <1e-6. Small invariant residuals
cannot substitute for accuracy: a wrong-speed pulse and missing/unsupported cases
are explicit negative tests. Native Float32 fields are evaluated in Float64.
Performance under concurrent mini load is diagnostic, not a pass criterion.

## Application boundaries and reports

Edgerton's adapter compiles the unchanged production `WaveSolver.swift` and
`Waves.metal`, copied into a temporary consumer with the actual resource bundle.
It loads matched fields through the existing public buffers/parameters and advances
through the actual `advance` method. No application lifecycle or rendering is needed.

RoomCAD's adapter binds the verbatim unmasked CPU velocity/pressure update blocks
and coefficient declarations from its current source; the serial slab wrapper does
not alter arithmetic. Its Metal adapter compiles the exact production embedded
kernel source and Grid layout, supplying a fully inside rigid box. RoomCAD stores
pressure divided by density; adapters convert to physical Pa at the input/output
boundary. Source injection and audio receiver normalization are deliberately absent.
The suite verifies these updates, not the complete room-response generator,
masked geometry, material-to-impedance mapping, microphone or hybrid crossover.

This is axial conformance only. Oblique incidence/grid orientation, absorbing or
finite-impedance walls, box modes, arbitrary masks and broadband 3D monopoles remain
separate cases. BombCAD's nonlinear gas solver is not silently treated as an
acoustic backend; it needs a separately matched small-disturbance adapter.

Each required case has six runs, at least 25 complete spatial field captures,
resolved spacing/dt, source/dependency revisions and hashes, native precision,
hardware/OS/toolchain, runtime, named reference, errors and invariants in JSON.
CSVs retain both spatial/time staggers and units. A separate guard requires every
field, clock, case and conformance result and exact agreement between JSON and CSV.
Unavailable Metal fails; CPU fallback cannot claim GPU conformance. Unsupported
capabilities are retained and fail required-case checks.

```sh
bash Scripts/check-acoustics.sh /private/tmp/core-acoustic-reference
# Application adapters: bash Scripts/check-acoustics.sh OUTPUT_DIRECTORY
python3 Scripts/compare-acoustics.py --output /private/tmp/acoustic-comparison \
  /private/tmp/edgerton-acoustic/metal \
  /private/tmp/roomcad-acoustic/cpu /private/tmp/roomcad-acoustic/metal
```

The core command generates analytic artifacts with status `reference`, not a fake
numerical solver pass. Application source consumers pin the reviewed core candidate;
a new tagged release or production solver extraction is a subsequent decision.
Complete application-derived raw evidence remains in private Edgerton.
