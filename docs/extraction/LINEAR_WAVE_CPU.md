# Serial masked CPU wave update — unreleased candidate

`LinearAcoustics` implements the first tranche of the [wave-update design](LINEAR_WAVE_UPDATE.md).
It is a framework-free Swift product with a checked immutable `PreparedWaveGrid`,
caller-supplied `WaveInitialFields`, owned serial `CPUWaveStepper` and copied
`WaveSnapshot`. No Metal product, application refactor, release or dependency
adoption is included. The existing `alpha.5` release remains immutable.

## Numerical/source boundary

The source-free complete step ports the three CPU blocks in
[the pinned source map](linear-wave-source.json): RoomCAD
`f2f6465d0d845af9adda596c004b18ca15a77edd`,
`Sources/AcousticCore/WaveSolver.swift` lines 613–657. MIT attribution is retained.
Velocity precedes pressure; Double coefficient preparation and Float accumulation
order are preserved. Adaptations are explicit:

- Collapse the slab traversal to serial full-k loops and use binary bytes directly.
- Read the six face blocks directly rather than allocating six subarrays.
- Own and reuse four independent Float buffers; snapshots copy on demand.
- Validate all dimensions/counts, CFL and rounded coefficients, topology, wall
  terms and initial state before allocating solver buffers.
- Scan the resident CPU fields for nonfinite values after each complete update.
  Failure invalidates state before incrementing its logical index; no rollback is
  promised. This additional O(N) scan is deliberate. CPU allocation failure follows
  Swift's native allocation behavior; no recoverable out-of-memory guarantee is made.

Pressure is ψ = pressure/density, m²/s²; velocities are m/s at each cell's positive
face. Relative pressure time is nΔt; velocity time is (n−1/2)Δt. Initial half-step
preparation, absolute epoch, source injection and physical-pressure conversion stay
with the caller. Density is metadata and does not alter normalized arithmetic.
Zero steps is identity; negative counts, index overflow and nonfinite derived clocks
fail before mutation.
Steppers are synchronous single-owner objects without concurrent access support.

Topology accepts fixed masks with active-neighbour links marked reciprocally −1;
closed active faces have finite β≥0; unused inactive entries are −1. All closed or
unused stored velocity slots must start at zero. Two adjacent active cells cannot
be disconnected merely by changing a coefficient: the original velocity update
uses the mask. Represent separation with inactive cells until a separate link-mask
contract is implemented. The conservative strict CFL check includes rounded Float
coefficients. Changing dt requires a new grid and newly prepared β.

## Independent verification

Seventeen tests verify hand-derived steps, all native fields/clocks, construction
rejection, isolation, snapshot ownership, zero/split-step composition, coefficient
rounding/density independence, overflow/failure semantics and wall-work accounting.
The independent numerical gates use existing BenchmarkSupport oracles without
changing them:

- All-active isotropic/anisotropic 3D modes through the masked path: time steps
  64/128/256, all four field errors refine at order 1.7–2.3 and finest L2 <0.001.
- Off-origin rigid box and disconnected chambers: every native field is checked
  against the fixed-lattice mode reference, finest L2 <0.001; padding is preserved.
- An anisotropic masked graph with heterogeneous dissipative faces: independent
  matrix-exponential pressure/half-clock velocities, steps 32/64/128, all four
  errors refine at order 1.7–2.3 and finest L2 <0.0003.
- Isolated decay has a hand-derived trapezoidal ratio. Complete heterogeneous wall
  work plus staggered modified energy has a separate 2e-6 normalized budget bound.

These are numerical verification gates, not measured acoustic accuracy or a
performance claim. Independent graph evolution is linked only by the test target;
production LinearAcoustics has no target or framework dependencies.

## Exact source comparison and package gate

`Scripts/prepare-wave-source-parity.py --roomcad /path/to/RoomCAD --output /private/tmp/new-parity-consumer`
reads the pinned Git object and checks whole-file/block hashes before creating a
throwaway consumer. It binds the original three blocks without changing their text.
`Fixtures/WaveSourceParity.swift` supplies independent control inputs and compares
all four native fields by Float32 bit pattern and complete-step indices at all 65 captures for four cases:
all-active rigid, all-active lossy, irregular masked lossy and split chambers.
Both implementations receive identical masks, wall terms, parameters and fields.
Compile this consumer against a cloned **committed** candidate using the same
configuration as the source wrapper. Runtime app-derived histories stay private;
public Core may retain the aggregate proof and source/candidate identities only.

`Scripts/check-linear-wave-consumer.sh` clones committed Git source, fetches the
exact revision and builds/runs an optimized consumer depending only on LinearAcoustics.
It checks fields/clocks/ownership/composition and rejects accidental Metal/UI binary
links. It is included in `Scripts/check.sh`; the existing all-product consumer also
exercises LinearAcoustics. Run the required full package check from the committed
candidate. The physical mini additionally verifies real GPU access and the existing
package's rendering/resource contracts, although this CPU product requires no GPU.

## Next gates

Add the separately verified resident-buffer Metal backend, then bind exact candidates
beside the retained RoomCAD benchmark adapters. Actual curved/dissipative/tilted
application conformance, safe source/receiver interfaces and full application checks
precede production adoption. Keep RoomCAD's optimized box path and Edgerton's forced,
damped 2D solver under their existing contracts. No source is retired by this tranche.

## Verified candidate checkpoint

Candidate `cb206cb2ae6ffd2198b6ad204564314716829cca` passes [physical-mini full checks](https://github.com/emmettl/ContinuumKit/actions/runs/37988973765):
158 tests, actual M4 Metal compute, all-product/CPU-only optimized Git consumers and
all unchanged independent reference suites. Debug and optimized pinned source
comparison has zero Float32 bit mismatches at all 260 complete captures in each
configuration. The [aggregate proof](linear-wave-cpu-verification.json) records
identities/counts; complete application-derived histories and source binding remain
in private Edgerton. This is an unreleased CPU candidate, not application adoption.
