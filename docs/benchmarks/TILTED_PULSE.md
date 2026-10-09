# Isolated tilted-plan pulse candidate

A thin z-invariant channel occupies 0≤y≤0.5 m, 0≤x<0.45−y/2 m and height
H=0.00390625 m inside a 0.5×0.5×H grid. Its tilted wall has outward unit normal
n=(2,1,0)/sqrt(5) and normalized real impedance ξ=3. Other walls/caps are rigid.
The incident direction is (1,0,0); reflected direction is (−0.6,−0.8,0).
Density is 1.25 kg/m³, sound speed 320 m/s and pressure amplitude 1 Pa.

The pulse F(s)=cos⁴(πs/(2a)) for |s|<a, otherwise zero, has a=0.04 m and starts at
x0=0.075 m. Incident pressure is F(x−x0−ct). Reflected pressure is
R F(d_ref·x+2 n_x²·0.45−x0−ct), where R=(ξ n_x−1)/(ξ n_x+1)
≈0.4570059441936298. Velocities are the respective propagation directions times
pressure/(ρc). This is an exact plane-wave solution of linear acoustics and its
local real-impedance boundary. The oblique coefficient convention is described in
[Sgard, Atalla and Robin (2024), equation 5](https://www.frontiersin.org/journals/acoustics/articles/10.3389/facou.2024.1414356/full).
The benchmark fields, compact-pulse integral and geometry are independently derived;
this is numerical verification, not measured material validation.

## A causal region, not an infinite finite-room claim

Run until cT=0.31 m (T=0.00096875 s). Score pressure and open native x/y velocities
only in x∈[0.05,0.35], y∈[0.235,0.265] and at least 0.015 m inside the tilted wall.
The earliest top-corner disturbance starts at c t=0.2−x0−a=0.085 m; its vertical
distance to this region is at least 0.235 m. Thus the first possible corner return
has c t≥0.32 m, beyond T. The bottom-corner event begins after T, and west-wall
returns are later. The complete reflected pulse lies in the observation region at T,
with zero incident pulse there. A bounded shifted-template least-squares fit reports
echo amplitude and arrival shift separately.

All full native fields are retained. Spatial reference values outside the scored
region are analytic extensions, not a solution satisfying the finite plan's later
corner boundary conditions. They receive no global source-energy conformance claim.
Inactive pressure is a 100 Pa sentinel; it is excluded from physical norms/energy
and must remain unchanged. Closed-face velocity and all z velocity have independent
global zero-motion gates.

## Work and refinement

Measure the central wall patch with smooth weight cos⁴(π(y−0.25)/(2b)), b=0.018 m.
This is a measurement window, not an envelope applied to the wave. Analytic pulse
squared integration in time and 512-interval Simpson integration in y gives physical
patch work. After the pulse passes, work/weighted incident energy equals 1−R².
Every source wall pressure at every complete step is retained. Total and patch
midpoint work are independently reconstructed from the original/scaled face arrays.
The global modified leapfrog energy plus **total** wall work must close below 1e−4.
The smooth patch is compared separately to the physical plane solution.

Space uses 64/128/256×same×2 at one common timestep, finest multi-axis CFL≤0.2.
Require overall field orders 0.5–2.5, finest causal-region relative L2 below 10%,
normalized maxima below 20%, patch-work error below 5% of weighted incident energy,
echo coefficient error below 0.03 and arrival shift below 10% of pulse half-width.
Finest aggregate wall-area error must be below 0.5%, volume and initial-energy errors
below 1%. These new declared thresholds do not change earlier normal-pulse gates.

Time fixes 64×64×2 and refines multi-axis CFL≤0.8/0.4/0.2. An independent continuous
finite-plan graph holds actual audited wall rates fixed. Its z-invariant reduction is
verified against a full graph. Degree-20 scaled Taylor action uses the actual sparse
row-sum bound so ||hA||∞≤0.5. Squaring its pressure polynomial and integrating every
term analytically gives patch work independently of midpoint source stepping.
Time requires adjacent field orders 1.7–2.3, finest relative L2 below 1%, maxima below
3%, global and patch work errors below 0.2%, coefficient error below 0.005 and shift
error below 0.5% of half-width, all relative to the fixed graph. Its coarse wall-area
allowance is 3%; it is not a separate continuum-geometry pass.

Source initial preparation, inactive preservation, closed-face velocities and z
motion each have 1e−6 normalized gates. Original layout coefficients must match the
independent segment/normal rule within 2e−6 relative error; timestep rescaling is
audited. A spatial gate failure is reported as **gap**, never physical conformance.
CI may pass report integrity and time/energy contracts with a spatial gap. Numerical
or time failures fail CI. Production code, old pins/gates and release tags are unchanged.

Twelve independent tests cover coefficient/energy goldens, the wall condition, pulse
quadrature, causality, patch loss, echo fitting, exact scalar/graph work, z reduction,
padding, missing fields/traces/clocks and invalid cases. The clean consumer exercises
reflection and patch-energy identities. Run `bash Scripts/check-tilted-pulse.sh [output]`.
Actual source adapters own CPU/Metal conformance; complete raw source evidence stays
private in Edgerton. General meshes, other angles/materials and measured acoustics
remain separate verification/validation work.
