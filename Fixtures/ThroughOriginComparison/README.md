# Single-column projection comparison

This is an optimized external Git consumer of the already published exact
ContinuumKit alpha.19 tag and its `Numerics.PivotedQR`, with no new numerical API.
It consumes all 90 frozen through-origin source-audit input pairs as exact native
binary64 bit patterns. The source minimum count and sign policy remain separate:
a generic projection supports two rows and negative or zero coefficients.

Every QR factor's scale, rank floor, permutation, condition diagnostic, complete
thin Q and R, coefficient, scaled residual norm and RHS exponent are retained.
The independent verifier checks exact-native projection/residual orthogonality,
full factor reconstruction and Q orthogonality. For these selected one-column
inputs, the declared absolute coefficient diagnostic budget is
`128 * m * epsilon * ||y|| / ||x||`; the squared comparison is exact rational.
Factor and residual diagnostics have explicit scaled roundoff budgets. These are
selected-input gates, not certified general relative accuracy bounds. Cancellation
can make the absolute budget large despite a small exact coefficient.

A standard-library Python prototype uses separately lossless power-of-two-scaled
inputs, `math.fsum` of normalized squared/cross products and checked coefficient
rescaling. All its native normalized inputs/products/sums/results are recorded
and judged against the same independent exact reference. It is a comparison
prototype, not a new production primitive or an Edgerton calibration rewrite.

`bash Scripts/check-through-origin-comparison.sh OUTPUT` requires a clean committed
candidate. It builds the separate exact-Git consumer with release optimization and
warnings as errors; it checks the exact dependency revision and absence of Metal,
UI and Accelerate linkage, then evaluates all cases and rejecting controls.
