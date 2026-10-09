# Grid-aligned rigid masked domains

This independent candidate contract verifies two three-dimensional domains embedded in
an otherwise inactive 0.25 × 0.125 × 0.125 m grid: an off-origin interior box and two
closed disconnected chambers, with only the left chamber excited. Box bounds and modes
are declared by `MaskedModeCase`. Density is 1.25 kg/m³, sound speed 320 m/s and pressure
amplitude 1 Pa. Inactive pressure is a deliberate 100 Pa sentinel, not physical air.

For each driven box, local coordinates give p = A cos(kx x) cos(ky y) cos(kz z) cos(ωt),
k_a = m_a π/L_a, ω = c|k|. Velocity along axis a is A k_a/(ρc|k|) times the corresponding
sine in space and time. The fixed-grid time reference replaces each k_a with
q_a = 2 sin(k_a d_a/2)/d_a in ω and velocity amplitudes, retaining spatial phases.
Pressure is at cell centres at integer time; native face velocities are at t − dt/2.
Sources start with pressure at t=0 and a Taylor half kick, not an exact numerical answer.
Continuum initial energy is A² V/(16ρc²) per driven box.

Independent integer box bounds determine active cells and open interior faces. Actual
application mesh occupancy and all six active-cell face coefficients must match.
Full native p/u/v/w histories, actual masks and coefficients are retained at nine captures
across one period. Spatial grids 16/32/64 × half × half use a fixed fine step; time grids
32×16×16 use multi-axis CFL 0.8/0.4/0.2. Each of four fields must converge at order
1.7–2.3, with finest relative L2 <1%, normalized maxima <3%, modified leapfrog energy
change <1e-4 and initial energy error <1%. Only active cells/open faces contribute to
errors and energy. Closed-face velocity, inactive preservation and unexcited-chamber
leakage each have a separate 1e-6 normalized bound. The 100 Pa padding cannot dilute L2.

Run `bash Scripts/check-masked.sh [output]`; verify stored or losslessly compressed
reports using `python3 Scripts/verify-masked-output.py output --reference` (omit flag
for actual sources; `--unsupported` requires explicit capability records without passes).
Eight tests check coordinate/frequency goldens, integrated energy and deliberate defects.
The clean Git consumer also exercises occupancy and full native fields.

This checks exact grid-aligned rigid geometry and connectivity. Curved/staircase surfaces,
openings, absorbing masked walls, material selection and measured-room accuracy remain
separate gaps. No production wave implementation is extracted, and no release tag changes.
Complete application-derived evidence is retained in private Edgerton; public core owns
only independently authored references, contracts and guards.
