# Equivalent plan and extruded mesh geometry audit

This version-1 contract isolates geometry assignment before wave evolution. Eighteen
independently authored convex rooms combine aligned/tilted walls, a single xi=3 east
wall or four distinct impedances, two lateral grid resolutions (32/64 x cells), and
three heights (0.00390625, 0.031, 0.123 metres). Bounding lengths are 0.5 by 0.37 m,
so x/y/z spacings differ. Floor and ceiling are rigid; source speed is 320 m/s.
`Fixtures/ExtrudedLayout/cases.json` is the exact case matrix. Null xi means infinite
normalized specific impedance. Wall identities follow counterclockwise polygon
edges; identities 4/5 are floor/ceiling.

`Scripts/extruded_layout.py` uses convex half-spaces for cell-centre occupancy and
finds the first outward plane crossing of the segment from an active centre to an
inactive neighbour centre. This is independent of app nearest-face and polygon
queries. For each closed grid face it expects beta = c dt / (2 xi d) times
1/(|nx|+|ny|+|nz|). It models documented Float32 coefficient storage and multiplication
order; it does not supply or duplicate a production wave solver.

The full native occupancy array, six coefficient arrays, selected physical-face IDs,
spacing and actual layout clock are retained for both representations. Source face
IDs are explanatory diagnostics repeating the current query; coefficients must come
from actual gridLayout. Complete topology is required. Coefficient or identity
mismatches are explicit `conformance-gap` results, with indices and a central east
wall patch (0.10 < y < 0.27 m) away from polygon junctions. Admittance-sum ratios
compare the same finite Cartesian grid, not continuum wall areas or acoustic energy.
Equivalent plan/mesh inputs must have identical occupancy, spacing and clock.

A successful audit command means the matrix is complete and well formed. It never
turns an assignment gap into a geometry conformance pass. Malformed/nonfinite output,
wrong occupancy, wrong interior/inactive flags or incomplete cases fail. Eight
independent Python controls include hand-counted aligned occupancy/coefficients,
tilted crossings, thickness invariance, cap-substitution mutation, rigid-face identity,
bad topology, nonfinite rejection and clock scaling. Run:

```sh
bash Scripts/check-extruded-layout.sh /tmp/independent-extrusion
python3 Scripts/extruded_layout.py verify /path/to/app-output
```

The RoomCAD adapter owns source conformance and hashes its actual AcousticCore files.
There is no CPU/Metal time stepping, reflected-wave claim, measured validation,
production code extraction or release in this audit. Nonconvex rooms, openings,
sloping caps, arbitrary imported meshes and multi-face corner policy remain separate
contracts. A production selection change needs its own bounded fix and regression
checks against the existing physical-Metal acoustic suites.

## Actual-source audit, 9 October 2026

RoomCAD's focused physical-mini run [37932031460](https://github.com/emmettl/RoomCAD/actions/runs/37932031460) reproduces 36 complete native layouts. All 18 floor plans and 13 extruded meshes conform. Five thin meshes select rigid caps in place of absorbing side walls. For the aligned nx=64 case, all 96 absorbing east faces become rigid. Tilted nx=32/64 cases retain 69.58%/66.17% of expected finite-grid admittance; mixed-wall cases retain 85.99%/84.46% overall. All thicker controls pass. Source masks, spacing and clocks agree exactly between the representations.

The bounded follow-up is directed wall selection in actual gridLayout, preserving
occupancy and local area weights, followed by strict regression checks here and the
existing actual CPU/Metal wave, reflection and work suites. AcousticCore extraction
is still gated; raw app-derived layouts are retained in private Edgerton evidence.
