# Rigid cylinder and staircase boundary verification

This independent candidate uses a cylinder centred at (0.125,0.125) m, radius
0.09375 m and height 0.125 m, inside a 0.25×0.25×0.125 m grid. Density is 1.25 kg/m³,
sound speed 320 m/s, amplitude 1 Pa, and inactive pressure a deliberate 100 Pa sentinel.
The radial/axial standing mode excites pressure and all three velocity components.

p = A J0(κr) cos(kz z) cos(ωt), κ = α/R, kz = π/H, ω = c sqrt(κ²+kz²),
where α is the first positive zero of J1, 3.8317059702075123. Radial velocity is
Aκ J1(κr) cos(kz z) sin(ωt)/(ρc sqrt(κ²+kz²)), projected into x/y; axial velocity
is A kz J0(κr) sin(kz z) sin(ωt)/(ρc sqrt(κ²+kz²)). The continuum energy is
A²πR²H J0(α)²/(4ρc²). Derivation uses the cylindrical Helmholtz equation and
J0' = −J1: [NIST applications](https://dlmf.nist.gov/10.73),
[derivatives](https://dlmf.nist.gov/10.6#E3), [zeros](https://dlmf.nist.gov/10.21),
and [integrals](https://dlmf.nist.gov/10.22). Independent 60-digit mpmath 1.3.0
values and Simpson volume integration check the Float64 reference.

Spatial grids are 16/32/64 × same × half, using a fixed fine timestep (multi-axis
CFL 0.25 at 64). Nine captures span one continuum period. Independent cell-centre
circle membership and six active-cell face coefficients must match actual app geometry.
Scores and energy exclude padding. All raw native p/u/v/w and actual layout arrays
are retained, including blocked/inactive stored values.

The staircase wall changes its physical domain with resolution. Spatial verification
requires each field's overall coarse-to-fine order in 0.5–2.5 and finest L2 <3%,
normalized maxima <10%, volume error <0.5%, initial energy error <1%, modified
leapfrog energy change <1e-4, and blocked velocity/padding preservation <1e-6.
Adjacent orders are reported individually; this contract makes no second-order spatial
claim for staircases. These new limits are declared separately from unchanged box gates.

Fixed-grid time refinement uses 32×32×16 and CFL 0.8/0.4/0.2. An independently assembled
continuous-time graph operator uses state [active pressure, ρc open-face velocity]. Each
edge contributes equal/opposite cell fluxes and a pressure-gradient rate. Degree-20
Taylor exponential action is scaled to ||hA||∞ ≤1/2; roundoff limits practical accuracy.
It removes curved geometry and spatial truncation from time comparison. Pressure is at
integer time; velocity is at t−dt/2, obtained by backwards exponential action. The source
starts with sampled continuum pressure and Taylor half kick. Time orders must be 1.7–2.3
for all fields, finest L2 <1%, maxima <3%, and initial energy error <2%; fixed-grid volume
error <2% is recorded separately, with the same energy and inactive/blocked gates.

Eight tests include independent Bessel/field goldens, volume integration, a golden two-cell
oscillator, a disconnected graph, energy/composition/reversal, agreement with an independent
rectangular masked eigenmode, incorrect masks/z velocity and invalid states/cases.
Run `bash Scripts/check-cylinder.sh [output]` and `python3 Scripts/verify-cylinder-output.py
output --reference`; omit the flag for source results, use `--unsupported` for capability
records. The clean Git consumer exercises the cylinder and graph reference.

This is bounded numerical verification of an ideal rigid cylinder. It does not establish
arbitrary curved mesh, absorbing-wall, source/probe policy or measured-room accuracy.
Complete app-derived vectors remain private in Edgerton. Production solvers and release
tags are unchanged; numerical contracts remain candidates before extraction.
