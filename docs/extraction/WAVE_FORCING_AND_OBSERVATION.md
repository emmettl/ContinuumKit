# Wave forcing and observation: next bounded contracts

Status: source audit and implementation outline. These interfaces are **not implemented**
in `0.1.0-alpha.6`; its source-free steppers and numerical evidence remain unchanged.
The next implementation slice is prepared sparse pressure forcing on CPU, followed
by a separate resident Metal slice. Receiver encoding and application adoption follow
independent gates rather than being bundled into a new general simulation framework.

## Audited application behavior

The audited source is RoomCAD `f2f6465d0d845af9adda596c004b18ca15a77edd`, already
identified by [the immutable source map](linear-wave-source.json). The current
RoomCAD CPU/Metal solver files are byte-identical to those pinned files at this audit.

A masked application step updates velocities, completes pressure/wall evolution,
adds the source, then observes the fields. For step index n, pulse evaluation is at
(n + 1/2) dt; resulting pressure has clock (n + 1) dt and velocity (n + 1/2) dt.
The prepared source weights already contain Float(c² dt / cellVolume), multiplied
by the app's normalized interpolation weights. Injection uses Float(pulse) times
that prepared Float weight. Core must not apply density, volume or timestep again.
ψ remains pressure divided by density. Pulse generation, geometry, weight construction
and physical source interpretation belong to the application.

The masked CPU source operation is in [WaveSolver.swift](https://github.com/emmettl/RoomCAD/blob/f2f6465d0d845af9adda596c004b18ca15a77edd/Sources/AcousticCore/WaveSolver.swift#L658);
GPU injection and sampling are in [MetalWaveSolver.swift](https://github.com/emmettl/RoomCAD/blob/f2f6465d0d845af9adda596c004b18ca15a77edd/Sources/AcousticCore/MetalWaveSolver.swift#L220).
The optimized unmasked CPU box path rounds its source expression differently and
remains outside this first forcing extraction.

## First slice: prepared sparse pressure forcing

A prepared plan must be immutable, tied to the exact prepared grid, and hold finite
Float coefficients at unique active cell indices. Reject out-of-range or inactive
cells and duplicates before allocating backend resources. Uniqueness is an ownership
contract: the existing Metal source kernel performs ordinary additions, without
atomic accumulation. Multiple entries writing one cell would race. Multiple physical
sources must be combined deliberately before this plan; changing accumulation order
is not an implicit feature of extraction.

A synchronous batch receives already evaluated finite Float amplitudes, one per
complete update. The backend performs velocity → pressure/wall → injection for
each amplitude, and publishes only complete-step clocks. Prevalidate the whole
requested input batch and its final clock before mutation. An empty batch is identity.
Keep the existing source-free advance behavior and packaged kernels intact; do not
expose a mutable field pointer, arbitrary encoder callback or publicly observable
half-step to make forcing possible.

The CPU implementation can initially consume one amplitude per call. Input rejection
preserves the prior snapshot and clock. Nonfinite computed output invalidates the
state under the existing failure contract; rollback is not promised. The public clock
must not acknowledge a CPU step until injection and the finite-field check finish.

The separate GPU implementation keeps fields resident and stages bounded amplitude
batches with explicit resource lifetime. Serialize velocity, pressure and injection,
including transitions across command buffers. Preserve the existing distinction
between acknowledged command completion and snapshot finiteness certification.
Encoding/submission failure invalidates the state; the clock retains only acknowledged
complete batches. No host field copy per source step and no silent CPU fallback.

Source work needs an independent ledger. A pressure jump at fixed native velocity
changes compressive energy, but that alone is not the full staggered modified-energy
change used by the existing wall-work tests. Include the velocity/pressure cross term
and use the actual before/after injection fields, with density and cell volume made
explicit in the reference. Do not label pulse amplitude or its norm as injected energy.

Acceptance requires an independently specified isolated-cell recurrence with signed
forcing and wall loss, a small connected-grid complete energy/work audit, forced
modal/time refinement against an independent reference, and finite-input/overflow,
unique-cell, empty-batch, ownership and failure-clock controls. A source-wrapper
comparison must retain every native field at every declared clock, separately for
CPU and actual GPU, using pinned original injection operations. Source parity alone
is not the independent numerical reference. Preserve all current source-free gates.

## Second boundary: observations and receiver output

CPU pressure interpolation sums Double(field) × Double(weight), in source order.
GPU pressure interpolation sums Float products in its kernel. CPU velocity components
sum their two Float faces before Double conversion and average by two, then project
onto the Double microphone axis. GPU performs Float averaging and Float-axis projection.
These are existing backend contracts; a new generic reduction must not silently unify
precision, reorder terms or reinterpret pressure as Pa.

Pressure interpolation can repeat indices (including zero-weight placeholders).
Unlike source injection, read-only receiver interpolation must preserve its ordered
entries rather than imposing source-plan uniqueness. Validate every index, finite
weight and velocity-neighbour access before work. The first encoded velocity receiver
must have valid minus-face addresses on all three axes; a clamp from the app does not
replace this Core validation, especially for minimal dimensions or inactive regions.
Core should accept a prepared observation, without constructing trilinear weights,
clamping microphone positions or choosing a spatial interpolation policy.

Directional microphone output has an additional temporal contract. Pressure sample
n corresponds to completed step n + 1. Its velocity is averaged from slots n + 1 and
n + 2 when the later slot exists; the final output uses slot n + 1 alone. Therefore
one chunk's last pressure sample may need the next chunk's velocity before it can be
finalized. Keep the completed native observation clock separate from finalized audio
output. Do not pad with zero, duplicate a boundary sample or use a trailing average
implicitly. Microphone mixing, terminal policy and audio-rate conversion stay app-owned.

Receiver acceptance needs affine spatial-field oracles, pressure/velocity clock checks,
backend-specific rounding controls, invalid-neighbour cases and chunked-versus-whole
history equality with one-step lookahead and final-sample treatment. Returned histories
are owned copies; any later zero-copy facility needs a separate lifetime contract.

## Application adoption gate

After independently verified CPU and resident Metal forcing/observation slices, bind
them beside RoomCAD's original forced masked loop. Retain source preparation, pulse
scaling, microphone patterns, complete histories and cancellation decisions. CPU
cancellation is checked every 64 steps in the current loop; GPU cancellation and
abandonment occur at command-buffer boundaries. Core's batching must permit the app
policy without changing when partial results are accepted or discarded.

Only then replace a production loop in a separate app change and run the full mini
application, package/resource and rendering checks. Keep the optimized CPU box path,
Edgerton's forced/damped 2D model and empirical acoustic validation as distinct gates.
A forcing or observation contract is not authorization to claim those migrations done.
