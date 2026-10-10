# Reusable Metal wave pipelines

`MetalWaveContext(device:)` compiles the five packaged update/injection/sampling
pipelines once for an explicitly supplied physical device. The context is immutable
and checked `Sendable`; it can be shared by independent simulations. It exposes
device name and registry identity without choosing hardware or keeping a global cache.
There is no equation, unit, precision, kernel, dispatch or clock change.

`MetalWaveStepper(context:grid:initialFields:)` allocates a new command queue and
resident fields/mask/walls for every run. Mutable amplitude staging, observation
storage, complete-step index, invalidation and completion handling remain owned by
the non-Sendable single-owner stepper. Immutable prepared source/observation mappings
retain their existing same-grid/same-physical-device checks. Sharing a context grants
no concurrent access to a stepper. Command submission remains synchronous; a failed
command invalidates only that run, and a context can prepare a fresh run afterwards.

The existing `MetalWaveStepper(device:grid:initialFields:)` initializer remains
available, creating a fresh context. Its internal deterministic completion seam
also remains for failure tests. Callers requiring repeated simulations deliberately
retain a context; no automatic hardware-selection, cancellation or fallback policy
is moved into the model.

Three actual-device tests verify reused pipeline identities with disjoint queues,
fields/staging/output, an independent hand-calculated forced two-cell recurrence,
failed completed-command isolation and four concurrent independent simulations.
Each concurrent run retains every field bit and all 257 three-receiver frames across
irregular 7/120/128/2-step boundaries, compared with independent convenience-created
pipelines. The optimized fetched Metal consumer now exercises context reuse, the
existing hand references, forcing, observation, snapshots/clocks and compatible API.
Existing independent modal/forced/damped/masked references and pinned kernel/source
hashes remain active. These are numerical and ownership checks, not empirical accuracy
or production throughput acceptance.

RoomCAD retains its original production Metal path until a separate application
binding passes complete original/shared outputs, cancellation at 128-step boundaries,
nonterminal abandonment, fresh CPU restart and device timing. Measure context
compilation and per-run setup separately; reuse itself does not prove a speedup.

## Verified checkpoint

Candidate `c38cba59358f0ba5c9bd84ae08218122412f34d4` passes full local and
[physical-mini package checks](https://github.com/emmettl/ContinuumKit/actions/runs/38024135039):
218 tests, including 31 actual-Metal and 46 CPU tests; three optimized fetched Git
consumers; CPU-only no-Metal/UI linkage; unchanged complete numerical/topology
reference reports and exact kernel hashes. The entire evolution/injection/sampling/
snapshot implementation remains byte-identical. The final evidence checkpoint changes
documentation only. [Aggregate identity/ownership proof](metal-wave-context-verification.json)
is public; complete logs and checks are retained privately in Edgerton. Exact-tag
publication and application Metal/timing acceptance remain separate gates.
