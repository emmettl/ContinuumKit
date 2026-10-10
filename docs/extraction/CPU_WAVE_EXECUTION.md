# Synchronous CPU execution and finite certification

Candidate: 10 October 2026, unreleased. RoomCAD's complete CPU binding found a
large-grid serial throughput gap. This tranche adds explicit `CPUWaveExecution`
(serial by default, or a caller-chosen parallel slab count) without changing the
wave equations, Float operations, source/receiver arithmetic or completion clocks.
No application default, release tag or frozen numerical reference is changed here.

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
