# Resident Metal wave update — unreleased candidate

`LinearAcousticsMetal` is the explicit GPU product for the source-free masked
complete-step contract. It depends on LinearAcoustics's checked grid/field types,
Foundation and Metal; the CPU product still has no framework/target dependencies.
No application source/receiver policy or release/adoption is included here.

The [pinned source map](linear-wave-source.json) identifies RoomCAD
`f2f6465d0d845af9adda596c004b18ca15a77edd`, its Swift/Metal scalar Grid ABI and
`waveVelocity`/`wavePressure`. The packaged `Shaders/WaveUpdate.metal` retains the
three Metal blocks byte-for-byte, with original MIT attribution. Run
`python3 Scripts/verify-wave-metal-port.py` to check their immutable block hashes.
The package loads the resource from its own bundle and compiles it on the caller's
explicit device with the source's default compiler options.

## State, phases and completion

Four independent, tracked shared buffers are initialized once and remain resident.
The mask and six wall-term blocks are also resident/read-only. Each complete step
encodes velocity before pressure on a serial encoder. The explicit buffer barriers
are redundant on a serial encoder (the SDK specifies they are ignored there); tracked
serial dispatch ordering provides phase visibility. Work is bounded to 128 complete
steps per command buffer. Advance waits for successful completion of each batch
before incrementing the acknowledged complete-step index. Split/batched calls have
the same clocks and fields. Only explicit snapshot copies fields back to Swift arrays.

Snapshots retain normalized pressure ψ = p/density at nΔt and native positive-face
velocities at (n−1/2)Δt. No implicit density conversion, initial half kick, forcing,
bulk damping or geometry/material interpretation occurs. `WaveInitialFields.validate`
now shares the existing CPU input checks with this backend; CPU update arithmetic
is unchanged. WaveSnapshot has a public value constructor for backend results;
constructing a value directly does not validate it or change any stepper state.

Negative counts, index overflow and nonfinite derived clocks are rejected before
GPU encoding. Zero steps submits no work. Construction validates initial state,
scalar ABI and per-buffer device limits and reports resource/pipeline failures.
A submission/command error invalidates the backend; previously acknowledged batches
retain their index. Partly modified fields are not returned or rolled back, and no
CPU fallback is performed. Rebuild from a caller checkpoint after failure.

GPU completion is **not a finite-output certificate**. Unlike the CPU's resident
per-step scan, this backend checks finite fields and zero closed slots when snapshot
is requested. A nonfinite/invalid field snapshot throws and permanently invalidates
state; the index may already count a completed GPU batch. No hidden O(N) host scan
or readback is added to advance. This timing difference is explicit in tests/docs.

## Verification and consumer

Eleven actual-device tests check:

- Nine scalar offsets, 36-byte size/stride and 4-byte alignment, including an
  independently authored GPU ABI probe of the actual packaged Grid definition.
- A hand-derived full-field step, half clocks, immutable inputs/snapshots and stable
  unique buffer identities over zero, split and 257-step multi-batch evolution.
- Whole fields against CPU across many thread groups, with inactive preservation;
  invalid input/count/clock paths and nonfinite output rejection.
- Controlled submission failure after real GPU completion of two batches, proving
  invalidation and acknowledged clock behavior without provoking a device fault.
- The unchanged independent rigid 3D, off-origin/disconnected masked mode,
  heterogeneous dissipative graph and complete wall-work/modified-energy gates used
  for CPU. Every field must meet the same time-refinement/error/budget bounds.

A missing device fails required tests. `Scripts/check-metal-wave-consumer.sh` fetches
committed Git source and builds/runs an optimized consumer depending only on the
wave products. It exercises resource loading, both kernels, full fields/clocks and
multiple command batches on the actual device. The separate CPU-only consumer still
checks absence of Metal/UI binary links. Both, the all-product consumer and the exact
kernel hash guard run in `Scripts/check.sh`; final candidate checks run on the mini.

`Scripts/prepare-metal-wave-source-parity.py` binds the original scalar ABI and two
actual kernels from immutable Git objects into a private temporary consumer. Independent
controls compare all four native fields and complete clocks at all 65 captures in
four rigid/lossy/masked/disconnected cases. Use identical build options and retain
complete raw histories privately; public Core records aggregate proofs only. This
source comparison is distinct from the independent reference/error/work tests.

## Remaining gates

Bind exact shared CPU/Metal candidates beside the original RoomCAD benchmark paths
and run actual curved/dissipative/tilted geometry and all-step wall-work contracts.
Safe source writes, receiver encoding, cancellation and application lifetimes need
separate integration contracts before replacing production loops. Preserve the
optimized box CPU path and Edgerton's forced/damped 2D assumptions. Release and
application pins follow verified adoption/readiness gates; existing tags are immutable.
