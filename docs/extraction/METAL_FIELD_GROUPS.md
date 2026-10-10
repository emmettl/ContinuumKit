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
