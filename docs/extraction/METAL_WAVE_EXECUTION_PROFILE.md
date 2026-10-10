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
