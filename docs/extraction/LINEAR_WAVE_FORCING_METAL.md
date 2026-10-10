# Resident masked pressure forcing — Metal

Status: released in `0.1.0-alpha.7`. The earlier alpha.6 remains source-free;
CPU forcing and this separate device-backed tranche precede receiver/application
integration. The [CPU forcing contract](LINEAR_WAVE_FORCING_CPU.md) supplies the immutable
unique active-cell mapping, physical scaling ownership and independent references.

Call `MetalWaveStepper.prepareSource` once to upload a `PreparedPressureSource` into
opaque `PreparedMetalPressureSource` buffers. Preparation validates the exact grid
identity before allocation, checks resource lengths, copies UInt32 indices/Float
coefficients and binds them to the physical device registry identity. Plans can be
reused by steppers with the same prepared grid and device. Buffers remain read-only
and retained through synchronous completion; caller arrays and snapshots do not alias
field/source resources. No raw buffer or encoder callback is public.

`advance(source:amplitudes:)` validates the entire finite amplitude batch, source grid,
device and final clocks before encoding. Fields and mapping buffers stay resident.
The stepper lazily allocates one 128-Float staging buffer, fills only the current batch,
then serially encodes velocity → pressure/wall → injection per step. Injection uses
the exact [pinned original kernel](linear-wave-forcing-source.json), without changing
MSL compilation options, source coefficients or amplitude scaling. All velocity
bindings are restored on every step because injection reuses buffer indices 1–5.
Serial dispatch/tracked resources preserve dependencies; explicit barriers remain
redundant on this serial encoder. Wait for completion before overwriting staging.
Empty amplitude batches are identity; an empty mapping performs source-free evolution
without mapping/staging allocations or an injection dispatch.

The pressure clock acknowledges only completed command batches, including injection.
Encoding/submission failure invalidates state and retains the last acknowledged
batch clock, without rollback. Source allocation failure occurs before field work.
As in the existing Metal contract, computed output finiteness is certified on explicit
snapshot, not on command completion. Thus a completed source-overflow command can
advance the clock before snapshot rejects and invalidates it. No per-step host field
scan, implicit checkpoint restore or CPU fallback is introduced.

## Independent evidence and numerical scope

Nine new actual-device tests supplement the eleven existing Metal tests. A binary
two-cell reference checks source ABI/phase order and clocks. A 257-step multi-source
case crosses staging/command boundaries, compares arbitrary chunk composition and
checks resident identities, caller/snapshot ownership, plan switching and CPU continuity.
Whole-batch invalid input/grid/clock, empty mapping, numerical overflow and injected
completion-failure controls retain existing failure semantics. The failure seam runs
actual successful commands and then throws; it does not claim an actual driver fault.

The independent rigid forced-lattice mode, isolated damped affine solution and full
heterogeneous source/wall modified-energy ledger use the same independently derived
references and unchanged bounds as CPU. They read actual GPU snapshots and account
for the pressure–velocity source-work term. Backend rounding remains explicit: GPU
original MSL arithmetic need not match CPU operations bit-for-bit. The retained legacy
post-wall forcing order has first-order damped continuum error; the rigid forced
reference has second-order time refinement. Neither establishes measured room accuracy.

The packaged Grid, velocity and pressure blocks retain their original hashes; the
new injection block is guarded separately. The private source-comparison preparer
verifies the immutable RoomCAD whole file and all four kernel/ABI blocks, then binds
the original injection kernel beside the shared backend. Independently chosen control
cases retain 65 consecutive snapshots and a 257-step three-batch final state (66
captures each), in debug and release. Preserve source-free source comparisons too.
The optimized fetched Metal consumer must load the packaged injection resource and
exercise signed forcing plus three command batches. Merge requires the committed
candidate full physical-mini `Scripts/check.sh`, original references and complete
private source comparison evidence. No receiver, app loop or release tag is moved here.

## Verified candidate checkpoint

Candidate `e86fb0cd7acbc5f8b06b7d6bcd962b042a85d1a5` passes
[the full mini check](https://github.com/emmettl/ContinuumKit/actions/runs/38008507643):
189 tests, all three optimized fetched consumers, CPU-only linkage and actual
packaged resident forcing. Twenty actual-device tests pass, nine for forcing.
Independent Metal metrics match M4 Max and M4: rigid all-field time orders
1.989–2.234, finest relative L2 below 2.88e−6, full source/wall work residual
3.79e−7. Omitting the pressure–velocity term instead gives 5.01e−4 residual.
Preserved damped forcing measures orders 1.0017/1.0005 with finest absolute
continuum error 0.001507; that accuracy limit remains separate.

The [private source mini gate](https://github.com/emmettl/edgerton/actions/runs/38008752306)
and M4 Max counterpart pass all 2,088 captures each across CPU/GPU, forced/source-free
and debug/release (4,176 total). GPU forcing retains 65 consecutive clocks and a
257-step state crossing three command batches per control. Original/shared fields
have zero runtime Float32 bit mismatches; all corresponding complete reports are
byte-identical across hosts/configurations. The producer and separate postcondition
require full report/cardinality/dependency scope; seven adversarial controls reject
missing or corrupted evidence. [Aggregate verification](linear-wave-forcing-metal-verification.json)
records identities. Full raw reports/wrappers, environments, dependencies and all
logs are retained privately in Edgerton. The final checkpoint changes documentation only.

[Exact-tag publication](alpha7-release-verification.json) passed all 189 tests and
three optimized consumers resolving the exact version before publication.
