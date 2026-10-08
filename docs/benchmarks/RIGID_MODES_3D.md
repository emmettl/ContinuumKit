# Full three-dimensional rigid-box modes

This unreleased BenchmarkSupport addition checks a uniform rectangular acoustic box
without application imports. It complements the axial, mixed-axis and normal
impedance suites; their cases, pins and assertions remain independent.

## Contract and references

Lengths are 0.25×0.125×0.125 m, density 1.25 kg/m³, speed 320 m/s and amplitude 1 Pa.
For positive integer mode indices m, k_a=m_a π/L_a and
p=A cos(k_x x) cos(k_y y) cos(k_z z) cos(ωt), ω=c√Σk_a².
The x velocity is A/(ρc)·k_x/|k|·sin(k_x x) cos(k_y y) cos(k_z z) sin(ωt),
with cyclic y/z expressions. Every exterior normal flux is zero. Total continuum
energy is A²L_xL_yL_z/(16ρc²). These standing modes are superpositions of travelling
waves, not isolated oblique-incidence reflection or measured-room validation.

The body-diagonal case (2,1,1) has equal wave numbers along all three axes. The
second case (1,1,1) uses an anisotropic grid with dz=2dx=2dy. This tests independent
z indexing, gradient coefficients and velocity directions.

Space uses nx=16/32/64, ny=nx/2, and nz=nx/2 or nx/4, with a fixed finest-grid dt.
Time holds nx=32 fixed and refines the multidimensional Courant number
c dt √(1/dx²+1/dy²+1/dz²) through nominal 0.8/0.4/0.2, rounding steps to a
multiple of eight. Temporal reference uses the exact spatial eigenvalues
q_a=2sin(k_a d_a/2)/d_a and their matching velocity eigenvector; ω_h=c√Σq_a².
It holds spatial truncation fixed rather than comparing time refinement against a
continuum solution. Spatial reference uses continuum k and ω.

Pressure is sampled at cell centres and integer clocks; each velocity is sampled
at its own native faces and time t−dt/2. Application fields start from zero physical
velocity with the same Taylor half kick in all three directions. The reference
uses the exact negative half-clock velocity. Nine full-volume captures span one
continuum period. No plane, transverse average or scalar probe substitutes for
these complete fields.

## Gates and implementation bindings

Each of pressure, ux, uy and uz must independently refine at order 1.7–2.3 in
space and time. Finest relative L2 for every field <1%; maximum pressure and
normalized velocity errors <3%; exterior normal velocity <1e-6; initial energy
error <1%; modified leapfrog energy drift <1e-4. The quadratic energy pairs each
native interior velocity at t−dt/2 with the momentum-derived t+dt/2 velocity.
Roundoff/device differences are reported, not used as performance pass criteria.

Independent checks include quarter-period vector golden states, a discrete-frequency
golden oscillator, Simpson integration of continuum energy, native z-face coordinates,
Taylor initialization, missing-field/clock rejection and a pressure-correct but
reversed-z-velocity negative case. Malformed decoded refinement metrics and
case dimensions reject explicitly before indexing; negative budget metrics fail. The fetched Git consumer exercises the public
3D reference and native z faces.

RoomCAD adapters compile verbatim current CPU update blocks and the exact embedded
Metal kernel/Grid source using its existing source-binding script. Both run actual
nx×ny×nz domains. Physical pressure is converted at the adapter boundary; all three
velocity fields are mapped from their production positive-face storage into native
staggered arrays. Production solvers, materials and tagged dependencies stay with
the application. Edgerton's current production wave solver is two-dimensional;
both 3D cases are explicitly unsupported, without histories/errors or numerical passes.

JSON preserves full pressure/three velocity histories, exact clocks, dimensions,
spacing, errors and source/device provenance. CSV includes all four field errors.
The separate guard checks fields, captures, exact resolution/capability matrices,
recomputed refinement orders, finest bounds and JSON/CSV equality. Dense payloads
are retained losslessly in private Edgerton with decompression hashes.

Outside scope: masked/curved geometry, heterogeneous media, oblique impedance,
frequency-dependent boundaries, sources/receivers and physical validation. No solver
extraction or release is included.
