# Exact through-origin least squares candidate

This candidate adds `Numerics.OriginLeastSquares`, not a material law. Its paired
finite binary64 inputs define `sum(x*y) / sum(x*x)` with no intercept. Units,
minimum material sample count, signs, specimen meaning and uncertainty stay with
the caller. One sample and zero/negative coefficients are mathematically valid.

Every input is decomposed into its exact signed integer significand and power of
two. Full-width integer multiplication accumulates denominator and positive/negative
dot products on the common 2^-2148 lattice, retaining cancellation and contributions
which no floating product could represent. The million-sample cap needs at most
4,216 accumulator bits. Exact subtraction determines the dot-product sign.
Integer quotient/remainder and a comparison with half the denominator implement
one final nearest-even rounding, including subnormal/normal carries and overflow.
This replaces the plan's provisional lossless floating normalization: no native
component or product is discarded, and no normalization failure is necessary.

A nonunique zero x vector, invalid dimensions, more than 1,048,576 samples and
nonfinite inputs fail explicitly. Nonzero coefficients rounding to zero or infinity
fail as unrepresentable. Exactly zero dot product returns canonical positive zero.
`Result` construction stays private. Its count/coefficient describe the rounded
line; `value(at:)` checks query finiteness and finite nonzero product representation.
Predictions use the returned coefficient, not the unrounded rational optimum.
Residual statistics, material positivity and confidence intervals remain caller-owned.

The current 450-case source probe includes all 90 protected original material audit
inputs, ordinary/signed/zero/tie cases, full native exponent spans, native-coordinate
conversion loss, 300 deterministic arbitrary-bit vector cases, long cancellation,
subnormal/normal and finite/overflow rounding boundaries, the actual cap and one
past it. Native inputs are retained as complete little-endian binary64 arrays.
Passive source bindings record every final exact accumulator, signed difference,
ratio exponent, aligned quotient/remainder and rounding decision; the bindings
restore the original source bytes exactly. This is a complete replay witness rather
than an application-layer observer. Exact rational checks verify every native input,
full product sum, quotient/tie, coefficient, query, projection orthogonality and
both optimum/rounded-line residuals. Nine controls include coherently changed input
and denominator/output/trace trees; original source findings remain protected.

The preliminary optimized probe passes 426 correctly rounded coefficients and all
24 declared input/rank/output rejections. These findings do not complete publication.
A fresh clean committed Git consumer must reproduce all probe outputs, and the full
package/previous suites and both physical Macs must pass. Complete source/runtime/
native/reference/control receipts and network-free replay precede any release.
Edgerton's Python calibration requires a separate adoption decision and frozen
CSV/policy checks; active mechanics and empirical material validation are separate.

## Completed candidate checkpoint

At exact producer `2832182191b66d9a6685df1a57512eae275871b7`, both physical
M4 Max and M4 mini pass the full package checks, actual Metal, ten optimized clean
Git consumers and all previous model suites. The [mini workflow](https://github.com/emmettl/ContinuumKit/actions/runs/38103567270)
completes successfully. All 901 actual native input/arithmetic/output payloads and
all public/reference/control/binding files match across hosts. The implementation
is merged through [Core #74](https://github.com/emmettl/ContinuumKit/pull/74).

The complete private archive in [Edgerton #77](https://github.com/emmettl/edgerton/pull/77)
retains 1,865 payloads and full source/runtime/run receipts. Its network-free
production/probe/public/rational/query/residual replay passes both captures,
including nine numerical, four source/producer/pin/coverage and two run rejection
controls. All 94 existing source/test blobs are unchanged from alpha.19.
This closes the candidate gate. Publishing alpha.20 still requires immutable
annotated-tag and exact-tag physical-mini verification; no application calibration
adoption or empirical material accuracy follows from these numerical checks.


## Publication

[Alpha.20](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.20) is now public after the complete exact-tag gate.
The [immutable tag/run/publication proof](alpha20-release-verification.json) and
[private full release replay](https://github.com/emmettl/edgerton/pull/78) retain
both physical-host exact-version consumers and every candidate/native/reference
identity. Edgerton calibration remains a separate application task.
