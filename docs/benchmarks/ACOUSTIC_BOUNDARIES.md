# Mixed-axis modes and real impedance boundaries

This is an additional, unreleased BenchmarkSupport contract. Existing axial cases,
application sources, tagged dependencies and their assertions are unchanged.

## Two-dimensional modes

A 0.25×0.125 m rigid rectangle, ρ=1.25 kg/m³, c=320 m/s and A=1 Pa uses
p=A cos(kx x) cos(ky y) cos(ωt), with kx=mxπ/Lx, ky=myπ/Ly and
ω=c√(kx²+ky²). Both staggered velocity components follow the acoustic momentum
law: ux=A/(ρc)·kx/k·sin(kx x)cos(ky y)sin(ωt), and the corresponding y component.
Modes (4,2) and (4,1) represent 45° and 26.565° superpositions of travelling waves.
They exercise both gradients and rigid faces without introducing periodic boundaries.
These are standing-mode tests, not isolated oblique pulse or oblique impedance tests.

Space uses 48/96/192 x cells, half as many y cells, and a fixed finest-grid dt.
Time holds 96×48 cells fixed and varies the nominal axial Courant number
0.6/0.3/0.15. Its independent exact spatial eigenfrequency uses
qx=2sin(kx dx/2)/dx, qy=2sin(ky dy/2)/dy, ωh=c√(qx²+qy²), and the matching
velocity eigenvectors. Integer pressure clocks and face velocities at −dt/2 are
retained; Taylor half kicks initialize a common physical state.

Every complete 2D field is scored at nine captures over one period. The full-history
relative pressure L2 error must refine at order 1.7–2.3 in each series. Finest
pressure L2 <1%, maximum pressure/velocity errors <3% of their amplitude scales,
closed-face normal velocity <1e-6, modified leapfrog energy budget <1e-4 and
initial continuum energy error <1%. A pressure-correct/reversed-y-velocity negative
case checks that scalar pressure agreement cannot conceal a wrong vector field.

## Normal real-impedance reflection

A compact right-going cos⁴ pulse from the axial suite encounters the east wall.
The normalized real impedance ξ=Z/(ρc) is 1, 3 or 0.5, giving pressure reflection
R=(ξ−1)/(ξ+1): zero, +1/2 or −1/3. The continuum image is multiplied by R;
wall velocity has the opposite reflected sign. Returned energy is R² of initial
energy and passive dissipation is 1−R². Pressure/velocity matching and the sign
convention follow [University of Washington's acoustic notes](https://staff.washington.edu/mbruce/pres/Waves.html).
An independent cos⁸ antiderivative supplies cumulative reference loss.

RoomCAD's existing law is β=c dt/(2ξ dx), applied to the boundary cell pressure.
Its implicit face flux is reconstructed from the actual old/new pressure average,
u_wall=(p_old+p_new)/(2ρcξ). Each step accumulates the actual nonnegative work
p_average·u_wall·dt, including the transverse measure. This is the solver's boundary
flux representation, not a separately stored exterior velocity or a sampled pressure
at a different time. The leapfrog quadratic energy uses interior u⁻·u⁺ and checks
energy plus accumulated boundary loss. Material absorption-to-impedance mapping,
openings and microphone/response processing are outside this fixture.

Space uses 128/256/512 x cells at one fixed dt. A boundary-cell impedance law has
first-order spatial boundary error; the interior has second-order error. Full-field
orders can therefore lie between one and two in this range. Require at least
first-order refinement (0.8–2.3 including tolerance), with all actual orders recorded,
and independent finest L2 <2%, maximum pressure/velocity <3%, reflected signed
coefficient within 0.01, returned energy fraction within 0.01, work-budget residual
<1e-4 and initial energy error <1%. The original fixed-first-order-only draft expectation
was corrected because it incorrectly penalized mixed interior/boundary error;
no application or existing-suite tolerance was weakened.

A second 512-cell run halves dt. It must meet the same accuracy bounds, with
changes in L2 error and reflected coefficient below 1e-3. This is bounded timestep
sensitivity, **not independent temporal-order verification of the impedance law**.

## Independent dissipative time refinement

An additional series holds 192×4 cells fixed and uses nominal Courant numbers
0.6/0.3/0.15. The reference solves the continuous-time spatial operator, with
state y=[p, w] and w=ρc·u on interior faces:

- ṗ_i = (c/dx)(w_i − w_{i+1}), with the west flux zero;
- ẇ_i = (c/dx)(p_{i−1} − p_i);
- the east pressure cell additionally loses (c/(ξdx))p_last.

Thus d||y||²/dt = −2c p_last²/(ξdx). Reference cumulative dissipation is the
loss of synchronous lattice energy, dx·Ly·||y||²/(2ρc²), and is independent of
the application's stepwise wall-work sum. Monotonic loss is enforced; only
energy-subtraction jitter below 1e-11 of initial lattice energy is clamped. Initial pressure and face velocity
sample the same physical pulse; reference velocity is evaluated at t−dt/2,
including the negative initial half clock. The application retains its Taylor
half kick. The east reference flux is p_last(t−dt/2)/(ρcξ).

Matrix-exponential action uses scaled degree-20 Taylor polynomials with
||A h||∞≤1/2, not a leapfrog or trapezoidal update. The per-subdivision truncation
bound exp(1/2)(1/2)^21/21! <1.6e-26 leaves Float64 roundoff as the practical limit.
The general scaling/Taylor approach is described by
[Al-Mohy and Higham (2011)](https://epubs.siam.org/doi/10.1137/100788860);
this implementation uses conservative fixed degree/scaling, without their adaptive
norm estimation. Independent tests cover scalar exponential decay, a closed
two-cell oscillator, integrated wall work, composition and the operator derivative.

Require pressure-history and cumulative-loss refinement at order 1.7–2.3.
Finest loss error must be <1e-3 of initial continuum energy; the existing field,
closed-face and modified energy-budget bounds still apply. Continuum reflected
coefficient and returned-energy accuracy remain gates of the spatial series,
not of this fixed-grid time series. The old 512-cell half-dt sensitivity check
also remains. This verifies temporal accuracy of the normal real-impedance law;
it does not remove that law's first-order spatial boundary error.

## Capabilities, reporting and limits

Edgerton's current production solver has rigid walls only. It passes the mixed-axis
cases and records all three impedance cases as **unsupported**, with reasons and
no fields/errors; those entries are never reported as numerical passes. RoomCAD's
CPU and Metal source adapters must pass both families. Its unchanged raw updates
run on N×Ny×4 grids, capturing the z-mean plane and bounding z-pressure variation
by 1e-4 of amplitude. Stored normalized pressure is converted to physical Pa.
No production kernel, initialization method or boundary code is rewritten.

JSON retains full native staggered 2D pressure and both velocity arrays, actual
spacing/dt, cases, errors, cumulative loss, precision and source/device provenance.
CSV summarizes every supported/unsupported run with units/normalization in column
names. A separate guard checks every case, resolution, capture, field shape and
summary value. Complete dense JSON fields are retained as lossless gzip payloads
in private Edgerton; raw outputs remain in temporary directories and CI artifacts.
Analytic core artifacts are labelled reference, not backend passes.

Separate suites now verify [full 3D rigid modes](RIGID_MODES_3D.md) and
[damped oblique impedance modes](OBLIQUE_IMPEDANCE.md). Still outside scope here:
isolated oblique pulses,
masked/curved boundaries, frequency-dependent impedance and measured validation.
No new release or acoustic solver extraction is included.
