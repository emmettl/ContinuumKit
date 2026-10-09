# Source-free CPU/Metal wave release readiness

The [CPU](LINEAR_WAVE_CPU.md) and [resident Metal](LINEAR_WAVE_METAL.md) products
now have independently specified all-field/time/work contracts, exact pinned source
provenance, device/resource/ABI and failure-clock tests, and three optimized fetched
Git consumers. The physical mini passes 169 tests and all unchanged reference/report
guards. M4 Max and M4 source comparisons have zero bit mismatches over 1040 captures.
CPU continuity after shared validation/snapshot changes is also byte-identical.

[Actual RoomCAD original/shared conformance](https://github.com/emmettl/RoomCAD/actions/runs/38001607985)
passes on producer `9aaa91410e82d63ee9e7ceb73afc701bd3e7f068`, using shared Core
`12eb14f5b9aea798bac33a35a506a4c429a21369`: masked 24, cylinder 12, admittance 24,
absorbing cylinder 12 and tilted plan/mesh 24 — 96 complete exact numerical/schema
pairs. Original and shared paths both pass each suite's original immutable oracle.
The producer and an independent postcondition enforce full scope; twelve tilted
plan/mesh pairs retain physical wall identities and zero fallback. The [aggregate
proof](shared-wave-adoption-verification.json) records identities and counts.
Complete reports/fields/clocks/layouts/wall work/errors and lossless reconstruction
remain private in Edgerton; no data is replaced by summary metrics.

This supports a prerelease of the **source-free** checked initial-value steppers.
A public snapshot value constructor and shared field validation are included; CPU
has no framework/target dependencies, and Metal explicitly requires a device.
GPU finiteness is checked on requested snapshots; command completion alone is not
a finite-output certificate. Observer mirrors add cost and do not establish a
production performance claim. Numerical verification/source equivalence does not
establish empirical material/room accuracy.

Production source writes, receiver encoding, cancellation, app lifetime and any
zero-copy interfaces remain separate integration contracts. No production app loop
or existing dependency pin is changed by this release preparation. The optimized
box CPU path, Edgerton's 2D force/damping model, variable fluids and nonlinear gas
flow remain distinct assumptions/gates. Releasing an independently useful component
does not require extracting every surrounding application policy.

The next prerelease candidate is `0.1.0-alpha.6`. Create its immutable annotated tag
only from the reviewed candidate; the manual Release workflow must pass all exact
version consumers and actual mini work before publication. Previous releases remain
available and unchanged.
