# Prepared masked pressure forcing — CPU candidate

Status: implemented CPU candidate, unreleased. `0.1.0-alpha.6` remains the source-free
release. Metal forcing, receiver encoding and production loop adoption are separate
tranches in [the integration outline](WAVE_FORCING_AND_OBSERVATION.md).

`PreparedPressureSource` contains immutable ordered cell indices and Float coefficients.
Destinations must be unique active cells; coefficients are finite and may be signed.
The plan binds to the exact prepared grid identity. Value copies retain compatibility;
a separately prepared grid needs a new plan, even if its numerical parameters agree.
This avoids rescanning the grid or accepting a plan prepared for another topology.

`CPUWaveStepper.advance(source:amplitudes:)` consumes one already evaluated finite Float
amplitude per complete step. It checks the entire batch, grid identity and final clock
before mutation. Each step runs the existing velocity update, pressure/wall update,
then `psi[cell] += amplitude * coefficient`, using the pinned masked operation order.
Finiteness is checked after injection; only then is the complete-step clock acknowledged.
Computed overflow invalidates state and retains only preceding completed steps; no
rollback is promised. Empty batches are identity, and an empty source plan preserves
the source-free path bit-for-bit. No mutable buffers or half-step callbacks are exposed.

The application owns pulse evaluation at (n + 1/2) dt and all coefficient scaling.
For RoomCAD's volume source, its Float(c² dt / cellVolume) scaling is already in the
prepared weights. Core applies no extra density, volume or timestep factor. More
generally amplitude × coefficient has units of psi (m²/s²); the separate factor units
are specified by the caller. Resulting pressure clock is (n + 1) dt; velocity clock
is (n + 1/2) dt. Microphone interpolation, lookahead and audio mixing remain app-owned.

## Independent references and limits

Eleven new tests supplement the seventeen existing CPU tests. A binary two-cell
reference checks phase order and complete fields. A signed isolated-cell affine
recurrence checks wall loss and source work. An anisotropic three-dimensional rigid
lattice uses manufactured pressure psi = sin(Omega t) times the cell-centred cosine
mode and native-face velocities proportional to (1 − cos(Omega t)). Its forcing is
[Omega cos(Omega t) + omegaGrid²/Omega (1 − cos(Omega t))] times the same mode,
where omegaGrid² = c² sum_axis [2 sin(theta_axis/2)/h_axis]². The reference uses the
fixed spatial lattice, independently derived staggered clocks and all four fields.
Temporal refinement checks second-order error without substituting a production
update as the numerical reference.

The connected heterogeneous-wall test uses the independently derived modified energy

E = rho V [sum_cells psi²/(2 c²) + sum_live_faces u²/2
            − dt/2 sum_live_faces u (psi_plus − psi_minus)/h].

At fixed native velocity, the exact source jump is

Wsource = rho V [sum_cells deltaPsi (psi_after + psi_before)/(2 c²)
                 − dt/2 sum_live_faces u (deltaPsi_plus − deltaPsi_minus)/h].

The test observes the actual pressure phase through the independently verified
source-free stepper, computes source jumps from actual before/after fields, and
accounts for every closed-face wall term using the pre-injection pressure. Omitting
the cross term fails the budget. This reference ledger is not a new production energy
API or a claim that pulse amplitude itself measures injected work.

Preserving the original post-wall source operation also preserves its accuracy limit:
for constant forcing in an isolated damped cell, the continuous equation is
psi' = −lambda psi + f, while the chosen update is
psi_next = (1 − lambda dt/2)/(1 + lambda dt/2) psi + dt f.
This forcing split has first-order continuum time error despite the source-free wall
update's trapezoidal decay. The test verifies the exact discrete affine solution and
measures that first-order refinement separately. A second-order damped forcing scheme
would be a deliberate model change with its own source/benchmark adoption gate.

Input, aliasing, empty-plan, chunk-composition, invalid-grid, final-clock and arithmetic
failure controls are part of the API contract. None of these references establishes
measured room or material accuracy.

## Pinned source comparison and verification gate

The [masked injection source map](linear-wave-forcing-source.json) identifies the
original RoomCAD MIT operation. `prepare-forced-wave-source-parity.py` first verifies
the original whole source file and all three source-free blocks, then binds the exact
injection statement. The generated wrapper/results belong outside this public repo.
The public fixture independently chooses four control grids, original Float-scaled
weights and signed midpoint amplitudes; retain all native fields and clocks at every
capture, in both debug and optimized configurations. Existing source-free comparisons
and the fetched CPU consumer's no-Metal/UI linkage check must also remain intact.

Final merge requires the committed candidate's full `Scripts/check.sh` gate on the
physical mini, its optimized fetched consumers, and complete pinned-source comparison
reports. No package tag or application migration is implied by this CPU tranche.
