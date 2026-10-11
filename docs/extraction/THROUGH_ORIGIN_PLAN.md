# Through-origin projection: bounded arithmetic audit and next gate

Checkpoint: 11 October 2026. This audit changes no public numerical product,
package dependency, material importer, calibration script or application policy.
The original [source arithmetic and fixtures](../../Fixtures/ThroughOriginAudit/README.md)
are protected; the existing affine and pivoted-QR releases remain immutable.

Edgerton's shear/bulk `fit()` uses `sum(strain * stress) / sum(strain²)` with a
zero intercept. Its minimum three measurements, positive modulus, hydrostatic
bulk interpretation, specimen metadata and measurement applicability are study
policy. Relaxation additionally uses a constrained affine fit inside a 601-point
time search, loading-ramp correction and boundary diagnostics; it is separate.
A Python caller does not become a SwiftPM consumer by sharing mathematics.

The local Python 3.9.6 source audit retains 90 native cases: 38 correctly rounded
coefficients, four finite coefficient differences, eighteen rejections of a
representable positive projection, eighteen returned nonfinite coefficients,
eight expected source-policy rejections and four unrepresentable coefficients.
Finite differences are exact-native diagnostics, not assertions of material
inaccuracy. Complete ordered terms, scalar outcomes, exact projection/residual
references and five rejecting corruption controls are retained. Two-host replay
and exact runtime evidence remain the audit publication gate.

For example, three finite strains of 1e200 with proportional finite stresses of
3e200 have a representable positive projection near three. The raw squared-strain
and cross-product sums both overflow, returning a nonfinite modulus. Strains of
1e-200 with proportional stresses underflow the squared-strain denominator and
reject despite a representable modulus. Native-coordinate exact references are
required; decimal intended values and empirical calibration are different claims.

The next bounded numerical task must first compare the already released
`Numerics.PivotedQR` single-column operation against a directly scaled dot/norm
projection. Avoid adding a second public primitive without an independently
specified benefit and supported-range contract. Use the actual source audit
inputs plus lossless power-of-two scales, signed cancellation, subnormal values,
finite output/residual requirements and coherent source/native corruption controls.
Declare nonunique zero strain and nonrepresentable coefficient/prediction behavior.
Do not floor a denominator or silently turn failed arithmetic into a modulus.

A chosen shared implementation needs a clean exact-Git consumer and full complete
native/reference gates on both physical Macs before release. Any later Edgerton
adoption requires its own bounded calibration task and frozen full CSV/result
comparison, retaining signs, minimum counts, specimen meanings, positivity and
relaxation search policy. Active contact/fracture studies remain app-owned.


## Existing released primitive comparison candidate

The [single-column comparison](../../Fixtures/ThroughOriginComparison/README.md)
builds an external exact-alpha.19 Git consumer. Its first local optimized run
passes 84 representable/nondegenerate generic projections; two zero-strain cases
reject as rank deficient and four unrepresentable coefficients reject explicitly.
A separately scaled dot/norm prototype agrees with the selected exact-reference
budgets. Complete QR/public diagnostics and prototype intermediate terms remain
visible. Generic negative/zero coefficients and two-row solves intentionally stay
separate from the source material policy. The local result alone is not a two-host
publication gate, and no extra API, release or calibration adoption is added.
