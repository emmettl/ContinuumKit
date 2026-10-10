# Capacity-bounded field threadgroups

The crossed [execution profile](METAL_WAVE_EXECUTION_PROFILE.md) identifies a useful
GPU cost reduction on M4 Max by using more rows/planes per field group. Larger M4
mini grids are approximately unchanged. Host sparse decoding/mixing accounts for
little of that difference. This production candidate changes dispatch shape only;
all kernels, barriers, injection/sampling arithmetic, bounds, completion semantics
and owned field/output/clock state remain unchanged.

Grids below 4,096 cells retain the existing width-at-most-32, height/depth-one shape.
For larger grids, height is at most four and depth at most two. Width, product and
every axis obey both field-pipeline capacity and the physical device's declared
threadgroup limits. Smaller capacities reduce the shape deterministically; invalid
limits reject before encoding field work. This is a bounded backend heuristic,
not a universal optimal group or a new application engine/budget policy.

Two actual-device tests cover threshold/uneven capacities/axis limits, rejected
limits, and a 4,437-cell irregular masked field with exact batch composition and
independent CPU agreement. Full unchanged numerical/reference/three-consumer gates
and complete crossed alpha.10/current field/observation profiles precede release.
RoomCAD's representative original/shared generator/save/timing and lifetime gates
remain required before application default adoption. Published tags stay immutable.

## Verified candidate

Candidate `060933a64968a4bd61a1eb1009e50c5b15d015f9` passes full local and
[physical-mini package checks](https://github.com/emmettl/ContinuumKit/actions/runs/38027312050):
220 tests (33 actual Metal, 46 CPU), all three optimized fetched consumers, CPU-only
linkage and unchanged full numerical/topology references. The
[mini complete profile](https://github.com/emmettl/ContinuumKit/actions/runs/38027428389)
and Max counterpart retain 27 runs/13,150,728 field words/27,648 native frames per
host, eleven negative controls, independent oracles and every field/readout/mixed bit
and clock exactly matching both hosts and alpha.10. Kernels and barriers stay exact.

The Max candidate/profiled-alpha.10-narrow wall ratios are 0.942/0.832/0.771; mini
ratios are 0.786/0.968/1.025. These are live-host comparisons with private timing
instrumentation in the control; small-grid dispatch is unchanged and its apparent
speedup is not attributed to this policy. Larger Max-grid improvements agree with
the controlled GPU profile; mini differences remain small and noisy. The chosen
policy claims no universal optimum or application timing acceptance.

[Aggregate proof](metal-field-groups-verification.json) is public. Full field/receiver
profiles, exact source provenance and lossless package/consumer logs are retained
privately in Edgerton. The final checkpoint changes docs only; exact-tag release
and RoomCAD adoption remain separate gates.
