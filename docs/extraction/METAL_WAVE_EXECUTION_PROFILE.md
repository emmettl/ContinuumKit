# Controlled Metal wave execution profile

RoomCAD's optional shared backend preserves complete original output but showed
live-host overhead. This bounded model experiment separates setup, command encoding,
commit/wait, actual driver GPU timestamps, sparse-frame decode and host alignment/mixing.
It does not change production kernels or synchronization.

The optimized fetched consumer compares the released-style current public stepper
with two private profiling copies of exact alpha.10: the existing 32×1×1 field group
and RoomCAD's original 32×4×2 shape. The four source files, original and modified
hashes and exact instrumentation patches are retained. All kernels, barriers,
arithmetic, resource checks, plans, clocks and single-owner state stay unchanged.
The profiling class adds timing and an explicitly chosen private group only.

Three physical grids (3,888/29,610/331,800 cells) run the same initial field, complete
signed source sequence and mixed pressure/directional receivers. One whole-run
warmup precedes three rotating measured repetitions per mode/grid. All four native
fields are retained as complete little-endian Float32 bit payloads outside timing;
every raw and mixed receiver bit and clock is retained. A separate independent
signed-source two-cell recurrence guards against consistent zero or malformed work.

Strict gates require exact fields and histories across every variant/repetition,
all completed 128-step GPU command intervals, separate phase accounting and exact
retained source/patch provenance. Unmeasured released command/decode phases remain
absent, not recorded as zero duration. Eleven negative controls reject incomplete or
altered fields, readouts, clocks, timestamps and shader source.

Measurements are live-host evidence, with shader-cache and scheduling effects. They
are not isolated performance, empirical model accuracy or application default
acceptance. A production group-selection change follows only if both physical Macs
show useful cost reduction while complete numerical/reference/consumer gates pass.

## Verified profile checkpoint

Candidate `8624103ec5839329807357be12a1268a8f723be3` passes the
[physical-mini profile](https://github.com/emmettl/ContinuumKit/actions/runs/38026881647)
and M4 Max counterpart: 27 runs, 13,150,728 complete field words, 27,648 native
frames per host and eleven negative controls. Every field, raw/mixed receiver bit,
clock and model input agrees across hosts and modes. All barriers are retained.
The original failed report gate is preserved: Float32 JSON values need Float32 bit
comparison rather than exact Double decimal equality. The corrected gate also checks
every native frame clock and independent final pressure/terminal mixing.

Larger-group/public wall ratios are Max 0.981/0.839/0.763 and mini
1.066/0.981/0.992 on the three grids. Profiled GPU time falls by about 18% and 27%
on the two larger Max grids; the mini is approximately unchanged. Host decode/mixing
is about 0.4–0.5 ms on most measured runs, with a noisier 1.34 ms mini small-grid
measurement. GPU time explains the observed Max difference more directly than host
readback. These live-host figures do not establish universal optimality.

A capacity-bounded larger group for larger grids is the next production candidate.
Keep the current small-grid shape and every synchronization/ownership/clock rule.
Full independent model/consumer and actual application throughput gates precede
release/adoption. [Aggregate proof](metal-wave-execution-profile-verification.json)
is public; complete profiles, source provenance, failed/corrected logs and binary
fields are retained privately in Edgerton. This final checkpoint changes docs only.
