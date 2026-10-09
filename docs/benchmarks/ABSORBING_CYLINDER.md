# Coupled real-impedance cylinder candidate

One circular cylinder has radius R=0.09375 m, height H=0.125 m, centre (0.125,0.125) m
and a 0.25×0.25×0.125 m grid bounding box. Density is 1.25 kg/m³, sound speed 320 m/s,
pressure amplitude 1 Pa and real normalized side impedance ξ=3. End caps are rigid.
Inactive pressure is a 100 Pa sentinel excluded from norms and energy. The `geometry`
container reuses the rigid cylinder's occupancy/units; its Neumann radial root is not
the absorbing mode's root.

## Independent continuum solution

The reference is p=Re[J0(qr) cos(kz z) exp(s t)], kz=π/H, s=−i c sqrt(q²+kz²).
Particle velocity follows ρ s u=−∇p. With outward side velocity p/(ρcξ), z=qR solves
z J1(z) + i sqrt(z²+(kz R)²) J0(z)/ξ=0. Newton iteration uses analytic derivatives.
All four fields and the initial wall condition are nontrivial. One oscillation has
T=2π/|Im(s)|≈0.00041047560726976466 s and Re(s)≈−1201.7263732180904 s⁻¹.

The complex Bessel series and derivatives follow primary
[NIST DLMF 10.2.2](https://dlmf.nist.gov/10.2#E2) and
[10.6](https://dlmf.nist.gov/10.6). The local impedance convention is given in
[Okuzono and Yoshida, §2.1](https://www.frontiersin.org/journals/built-environment/articles/10.3389/fbuil.2022.1006365/full).
The cylinder mode, root equation, radial energy integrals and wall-work law here are
independently derived from the linear acoustic equations, not measured validation.

Lommel radial integrals give analytic total energy. Integrating the physical side
pressure squared gives D(t)=integral p²/(ρcξ) dA dt. E(t)+D(t)=E(0) throughout a cycle.
Offline [60-digit mpmath 1.3.0 goldens](reference/absorbing-cylinder-goldens.json)
use independent root finding and radial/time quadrature; regeneration is documented
in `Scripts/regenerate-absorbing-cylinder-goldens.py` and is not a CI dependency.
The power series is deliberately bounded to this benchmark, not a general Bessel API.

## Space, time and source work are separate gates

Space uses 16/32/64×same×half with one common timestep set by the finest grid at
multi-axis CFL≤0.2. Complete pressure and three native staggered velocities are
compared to the continuum mode at their own clocks. The staircase is expected to be
first order: require overall coarse-to-fine field orders 0.5–2.5, report both adjacent
orders, and bound finest relative L2 by 5%, normalized maximum error by 10%, physical
wall-work error by 3% of initial continuum energy, initial energy error by 3%, volume
error by 0.5%, and physical side-area error by 0.5%. These new declared limits are not
replacements for existing rigid-cylinder or wall-area gates.

Time fixes 32×32×16 and refines multi-axis CFL≤0.8/0.4/0.2. A continuous-time graph
operator independently assembles pressure fluxes, pressure-gradient velocity rates
and nonnegative diagonal wall loss λ=2 sum(β)/dt. Its scaled degree-20 exponential
has ||hA||∞≤0.5; the polynomial remainder bound is below 1.6e−26 per substep, with
Float64 roundoff the practical limit. Actual audited layout coefficients are held
fixed in physical rate under timestep rescaling. This isolates time integration;
it does not prove the spatial operator is a continuum model. Require adjacent
field orders 1.7–2.3, finest relative L2 below 1%, maxima below 3%, and cumulative
wall-work error below 0.2% of initial continuum energy. The fixed-grid volume and
initial-energy allowances are 2% and 6% respectively.

The initial source velocity is physical velocity at t=0 plus a discrete Taylor
backward half kick, matched to the native staggered clock. Every source wall-cell
pressure at every step is retained. An independent validator reconstructs midpoint
wall work and matches it to recorded capture ledgers and native pressure fields.
Modified leapfrog energy uses adjacent velocity half-step products; require
max |E(t)+D(t)−E(0)|/E(0)<1e−4 for every source run. Blocked-face velocities,
inactive preservation and exact initial-state preparation each have a 1e−6 normalized
bound. Full raw layout/scaled arrays and clocks, material impedance and masks are
retained and audited. Nearest polygon normals may differ from ideal circle normals
by at most 1% locally; aggregate area still has the stricter 0.5% gate.

Reference histories contain exact continuum/graph work and omit source step traces.
Their reported sampled modified-energy residual is not a source-conformance pass;
continuum energy/work correctness has separate independent tests. Source records
must include complete traces. No unsupported model receives a substitute solver.

Run `bash Scripts/check-absorbing-cylinder.sh [output]`. The suite extends
`BenchmarkSupport` and `continuumbench`; no production model module or release tag is
added. Complete application-derived source evidence must remain private in Edgerton.
