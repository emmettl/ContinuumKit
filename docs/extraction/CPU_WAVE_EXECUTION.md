# Synchronous CPU execution and finite certification

Published in `0.1.0-alpha.9` after the verified checkpoint below and
[exact-tag mini publication](alpha9-release-verification.json). RoomCAD's complete CPU binding found a
large-grid serial throughput gap. This tranche adds explicit `CPUWaveExecution`
(serial by default, or a caller-chosen parallel slab count) without changing the
wave equations, Float operations, source/receiver arithmetic or completion clocks.
Application defaults and frozen numerical references remain outside this library contract.

Counts must be positive and no larger than the grid's z dimension; invalid counts
reject before field allocation. Each slab owns a disjoint integer z-plane interval.
Velocity reads the unchanged pressure field and writes only its own positive-face
slots. Synchronous Dispatch completion precedes pressure's reads of all velocities.
Pressure writes only its own cell slots; completion precedes serial sparse injection,
clock acknowledgement and observations. One slab invokes the same phase directly.
Core does not infer hardware, thresholds, application cancellation or scheduling.
CPU consumers now link system Dispatch and retain the no-Metal/UI framework guard.
The mutable stepper remains single-owner and does not become Sendable or concurrently
callable. The private Sendable pointer borrow never escapes the synchronous phase.

## Complete-field finite certificate

Initialization validates every native slot. Each velocity phase checks all active
velocity slots; each pressure phase checks all active pressure results; injection
checks every sparse destination. All inactive pressure and closed/unused velocities
remain unchanged and finite by construction. Finite source inputs cannot repair a
nonfinite pressure: a finite product leaves infinity/NaN nonfinite, and an overflowing
opposite product produces NaN. Flags retain any phase failure until all phases and
injection complete. Reject/invalidate before acknowledging that step, as before.

This inductive certificate replaces the separate four-field scan, retaining coverage
of every value that can change. Two bytes per slab are allocated with the owned CPU
buffers and reused. Workers write distinct flags; the caller reads them only after
completion. No whole-field copy or per-step field allocation is added. Readout overflow
still differs from field failure and retains an already acknowledged finite step.
Input/plan/batch/final-clock checks still precede work, and failed state has no rollback
promise. Serial traversal also uses the fused certificate.

## Verification and measured readiness

Eight new tests cover explicit/invalid counts, a hand-derived ramp across uneven
slabs, 257 complete field/forced receiver captures at 1/2/3/5 slabs, unchanged inactive
padding, velocity/pressure/source failures, acknowledged clocks, sparse readout overflow,
whole-batch rejection and owned histories. Existing independent rigid/masked/dissipative
and manufactured forcing references now run serial and parallel, with unchanged error
bounds and work contracts. The fetched CPU-only consumer executes packaged parallel
forcing/observations and preserves its linkage guard. Focused CPU tests and Thread
Sanitizer are required before merge, followed by the full committed mini check.

`Scripts/check-cpu-wave-throughput.sh` fetches the committed candidate and the exact
alpha.8 CPU class body (only its class name changes). Both use the same public prepared
value types. Three representative grids compare alpha.8, current serial and current
parallel over rotating warmed repeated source/observation batches. Retain every native
field/bit, raw receiver value/bit and complete clock, plus wall/process-CPU timings.
Initialization and snapshot/encoding are outside the timed model batches. Live-host
measurements do not certify isolation or RoomCAD throughput acceptance.

A separately gated application candidate must bind the eventual released execution
API using the original app's slab/cancellation policy and repeat complete outputs,
full wave-enabled generation/save and two-host timing. Only then may its default
change. The legacy damped forcing accuracy limit and empirical room validation stay
separate; accelerating an existing model does not improve its physical assumptions.

## Verified execution checkpoint

Implementation `60e4f0a529e6bb6bb333876418c17c5d7abb1e99` passes the
[full mini check](https://github.com/emmettl/ContinuumKit/actions/runs/38018425652):
215 tests, including all 46 CPU and 28 actual-Metal tests, all optimized fetched
consumers, packaged parallel CPU and no-Metal/UI linkage. The eight new execution
tests also pass Thread Sanitizer. Independent serial/parallel numerical bounds and
source/receiver failure contracts remain unchanged.

[Mini complete comparison](https://github.com/emmettl/ContinuumKit/actions/runs/38018534701)
and M4 Max counterpart retain 27 native field/receiver captures and 27,648 complete
receiver frames per host, with zero runtime bit mismatches. Every complete report is
byte-identical across hosts. Both strict postconditions and seven negative controls
pass. The mini comparison's intervening commit changes workflow routing only;
subsequent changes add report controls and documentation, not production/test/fixture code.

Largest-grid (331,800-cell) median parallel/alpha.8 wall ratios are 0.210 on M4 Max
and 0.323 on M4. The 3,888-cell parallel mode is slower on the mini (1.568), so callers
must retain a measured small-grid serial policy. Parallel work can consume more total
process CPU; complete wall/CPU measurements remain available. These live-host model
measurements do not prove RoomCAD's throughput/default gate. [Aggregate verification](cpu-wave-execution-verification.json)
records identities; complete losslessly compressed raw fields/reports, baseline source,
provenance, metadata, dependencies, sanitizer and job logs are retained privately.
