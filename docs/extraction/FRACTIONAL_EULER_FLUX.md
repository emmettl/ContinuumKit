# Prescribed fractional Euler flux candidate

`CompressibleFlow.FractionalEulerFlux` is a stateless CPU reference extracted from
BombCAD's separate fractional-gas experiments. It advances extensive mass, three
momentum components and total energy in caller-supplied gas cells. It uses the
released packet state and planar wall primitive. The caloric ratio is fixed at 1.4;
constructing a packet with another gamma does not change this operator's gas law.

## Physical and numerical contract

SI units: cell volume m³; density kg/m³; velocity m/s; pressure Pa; face area m²;
duration s; extensive mass kg, momentum kg m/s and total energy J. Faces carry a
unit normal from index `a` to `b`. Every face removes one extensive flux packet
from `a` and adds the same packet to `b`, using the frozen pre-step states.
Duplicate supplied interfaces are applied separately. There is no geometry audit
or requirement that the supplied normals/areas form a closed mesh.

The Euler physical flux uses normal velocity, pressure traction and total enthalpy.
The Rusanov dissipation coefficient is the maximum incident `|u.n| + sqrt(1.4 p/rho)`.
Optional left/right face states and wall states supply intensive traces; their
own positive volumes are used to recover density. Host cell volumes determine
the clock and receive the extensive changes. Reconstruction belongs to the caller.
The Euler equations, characteristic velocities and shock/isentropic relations are
specified in the primary [Clawpack Euler reference](https://www.clawpack.org/riemann_book/html/Euler.html).

Wall normals point outward from gas. Returned ordered impulses and work act ON
the prescribed wall, opposite to gas momentum and energy changes. Work is impulse
dot supplied wall velocity, including any tangential components of the vector;
traction itself is purely normal. The occupied cell volume changes by
`duration * area * wallVelocity.normal`. Zero-area walls return zero impulse/work.
Wall pressure comes from the released shock/rarefaction/vacuum reference.

`maximumStep` accepts `0 < cfl <= 0.5`, default 0.4. Each incident face contributes
area times its signal metric to both host cells. A wall contributes area times
its existing upstream wall metric plus absolute normal wall velocity. Each occupied
cell limits duration by `cfl * oldVolume / sumRates`; net contraction also limits
duration by `cfl * oldVolume / -volumeRate`. Isolated valid cells, including empty
dry cells, may return infinity. Rates with unrepresentable individual products
reject; an overflowing accumulated rate can produce a zero limit. This retains
source behavior rather than inventing a usable duration.

This clock is not an exact wall-front speed, a universal characteristic certificate
or a positivity guarantee for arbitrary supplied traces. A trace may remove more
mass than its host owns even below this bound. `advance` requires finite positive
duration no larger than the estimate, then validates the complete trial with the
packet primitive. Nonphysical outcomes throw transactionally; no density/pressure
floor, retry or timestep adaptation is supplied. Input arrays are immutable values.

Face/wall indices, finite nonnegative areas, finite unit normals (squared-length
error strictly below 1e-12), finite wall velocities and positive incident trace
volumes are checked even at zero area. Connected faces/walls require positive host
volumes. Packet and wall errors remain distinct from `invalidFace`, `invalidWall`,
`invalidStep` and `unstableStep`; earlier source validation order is preserved.

## Independent acceptance and complete source conformance

Thirteen focused tests cover literal oblique SI flux, a stationary discontinuity's
characteristic dissipation, intensive traces, volume/characteristic clocks, face
reversal, independent Mach-two wall shock and rarefaction/vacuum loads, extensive
wall ledgers, unsupported trace positivity, supplied wall trace ownership, invalid clocks/geometry, inactive dry
states and characteristic representability. The first oblique test run exposed an
incorrect hand-calculated momentum expectation; the expectation was corrected to
rho u (u.n) + p n, without changing source arithmetic or tolerances.

A sixth optimized public consumer imports only CompressibleFlow and system math.
It retains the immutable original with SHA/blob protection and compares complete
original/shared cell values and bits, inputs, CFL clocks, failures, ordered wall loads
and every native interval. Its declared tree has 486 paired-face trials, 243 moving
wall trials, ten failures and twelve complete wave histories (751 cases total).
The matrix varies density, pressure, velocity, normal, cell-volume scale and traces.
The scalar checker independently checks per-cell extensive balances, complete
external ledgers, EOS views, characteristic/geometric clocks and wall traction by
Hugoniot root bisection or isentropic relations. Source parity is a separate check.

Continuum references use cell-averaged periodic contact and small-amplitude acoustic
waves and a moving Mach-two normal shock with fixed external ghost reservoirs.
Grid sizes 32, 64 and 128 share fixed final times (0.15 s for periodic waves,
0.05 s for the shock). Every actual cell and interval is retained, including ghost
trial changes before prescribed reset. Refinement must reduce normalized mean
density error by factors above 1.6 per doubling for smooth waves and above 1.2 for
the shock; finest bounds are 0.06 and 0.12 respectively. The shock comparison uses
analytical cell averages of conserved mass, momentum and energy, normalized by the
corresponding jump. Acoustic amplitude is 1e-6; linearization error is distinct from
first-order spatial diffusion. Pressure/velocity phase checks also apply.
A separate fixed-64-cell small-amplitude acoustic history refines CFL 0.4, 0.2 and
0.1 at the same final time, against the exact Fourier evolution of the linearized
semidiscrete reference. Its right-acoustic eigenvalue is
`-(0.2 + sqrt(1.4)) / h * (1 - exp(-2 pi i h))`. This closed-form matrix exponential
does not step the production operator. Normalized mean density error must fall by
factors above 1.6 per halving and finish below 0.01. This isolates first-order time
error from the separately measured spatial diffusion; small nonlinear error remains
an explicit limitation of the 1e-6-amplitude reference.
Fourteen deliberate corruptions must reject even when both comparison reports are
changed together. Both physical Macs, existing Core suites and a clean fetched Git
consumer must pass before release. An exact-tag release gate then precedes any
separate BombCAD adoption and complete affected application comparison.

## Ownership and provenance

[Source manifest](euler-flux-source.json) pins BombCAD revision
`063d6fe818fd78ccbfe46c1c79e035f04de03800` and its MIT-authored implementation.
Access modifiers, immutable conformance and type names change; normalized numerical
source must remain identical. The scratch consumer prepends only an explicit CompressibleFlow import to its
compiled original copy, verifying the remaining bytes against the immutable oracle.
Original code is verification-only. The production
BombCAD copy remains until its own adoption gate.

Geometry, topology changes, remapping, reconstruction/limiting, higher-order time
integration, body response, reservoirs, scheduling and the production Metal air
solver remain application-owned. These numerical references do not establish
empirical blast accuracy or certify arbitrary reconstructed states.

Verified candidate, 10 October 2026: [complete acceptance](euler-flux-verification.json)
records two-host byte-identical raw reports, 751 cases, 105,149 returned native
cells and 1,974 intervals. Both full package gates pass 260 tests, actual Metal,
six optimized fetched consumers and all existing reference/topology checks.
Fourteen corruption controls reject per host. Separate temporal error halves at
fixed grid size. Exact-tag verification precedes publication; application adoption
remains a separate bounded task.
