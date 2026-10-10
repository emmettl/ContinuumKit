# Pivoted QR: checked reusable small-matrix least squares

`Numerics.PivotedQR` factors a tall finite binary64 matrix once and reuses immutable
column-pivoted Householder reflectors for multiple RHS. It implements matrix
arithmetic only. Units, basis terms, row multipliers, coordinate transforms,
degree fallback, mean preservation, limiting, EOS and interpretation remain
caller-owned. Multiplying a row and RHS by `w` gives an objective weight of `w²`.

```swift
import Numerics
let factor = try PivotedQR(rows: [[1, -2], [1, -1], [1, 0], [1, 1], [1, 2]])
let solution = try factor.solve(rhs: [0, 0, 1, 4, 5])
// Original column order: intercept approximately 2, slope approximately 1.4.
let coefficients = solution.coefficients
```

## Supported contract

Matrices have `m >= n >= 1`, equal row widths, at most 64 columns and at most
1,048,576 entries. Dimensions, allocation, rank tolerance and finite input checks
precede internal allocation/factorization. Inputs already supplied by the caller
are not counted as library-owned allocation. No underdetermined or minimum-norm
rank-deficient solve, pseudoinverse, GPU execution or parallel reduction is supplied.

The finite relative rank tolerance is in `[Double.ulpOfOne, 1)`, default `1e-10`.
At each pivot, remaining column norms are recomputed safely. A pivot must have
`norm / initialLargestColumnNorm > relativeRankTolerance`; otherwise construction
throws `rankDeficient`. This is a numerical pivot policy, not exact mathematical
rank or a certified singular-value threshold. It need not preserve the original
Gram-Schmidt fitter's decisions arbitrarily close to a cutoff.

Global power-of-two scaling brings the largest input exponent to zero. Every
nonzero entry must round-trip exactly through that scaling, or construction/solve
throws `unrepresentableNormalization`. Native distinctions lost before the call
cannot be recovered. Norms use scaled squares; reflector projections use
compensated sums with fused product corrections. Pivot ties choose the first
remaining column in deterministic serial execution. Reflector signs are internal.

`matrixScaleExponent`, `permutation`, `scaledUpperTriangular` and
`orthogonalColumns()` expose complete diagnostic factors satisfying
`A * 2^(-matrixScaleExponent) * P ≈ Q * R`. Q is returned as n complete columns;
R uses pivoted column order. The physical unscaled R may be unrepresentable even
when a useful solution exists, so the API exposes the scaled factor explicitly.

`reciprocalConditionEstimate` computes a floating 1-norm reciprocal condition of
the scaled R via triangular inverse columns. Zero can represent underflow or an
unrepresentable estimate. It is not a certified bound, confidence interval or
promise of accurate coefficients. Near dependence can amplify small backward
errors, especially for inconsistent data. Rank acceptance alone is insufficient
to establish useful forward accuracy.

Each RHS must contain exactly m finite values. Solve independently scales that
RHS, applies Q transpose, back-substitutes and restores the coefficient scale
using exponent decomposition. Nonfinite or vanishing nonzero coefficients reject
as `unrepresentableSolution`; no physical scale ratio is formed independently.
The result's coefficients use original column order. Its
`scaledResidualNorm * 2^rhsScaleExponent` is a computed optimal-residual diagnostic;
the physical norm can overflow/underflow. It is not a certified residual bound.
Factor and solution construction are checked; callers cannot construct unchecked
results. Successful solves do not mutate the factor, and zero RHS returns zeros.

The public failure cases are `invalidDimensions`, `allocationLimit`,
`invalidRankTolerance`, `nonFiniteInput`, `unrepresentableNormalization`,
`rankDeficient` and `unrepresentableSolution`. No process preconditions substitute
for these input failures. Primitive code imports no app or rendering target and
links no Metal, UI or Accelerate framework.

## Independent references and complete native evidence

The committed optimized [public Git consumer](../../Fixtures/PivotedQRConsumer/README.md)
retains 741 factor cases, including all 624 original protected audit records,
extreme common scales through subnormal/greatest exponents, five widths, three
64-column boundaries (identity, dense Hadamard and noisy tall Hadamard), diagonal rank/tolerance boundaries and finite/dimension/
normalization/solution failures. Every accepted factor is reused for primary,
alternate and zero RHS, then repeats the primary solve. The consumer keeps
complete A/b/Q/R/permutation/coefficients/predictions and scaled diagnostics.

The reference uses exact fractions of actual native inputs, exact pivoted Schur
complements for independent rank-policy comparison, and exact Gram elimination for
least squares. No floating normal equations or production reflector code are used.
It independently checks factors, triangular condition diagnostics, coefficients,
normal-equation residuals, optimal-residual diagnostics, original column order,
all repeated RHS and every error. Original audit source/results remain protected;
their numerical failures stay findings rather than being edited into passing data.

For this cohort, factor orthogonality and relative reconstruction must be within
`256 ε max(m,n)`. The normalized coefficient L2 bound is
`64 ε max(m,n) κF (||x||₂ + κF ||r||₂ / ||A||F)`, with an eight-ULP floor.
Here κF is computed independently from exact-native A and its exact Gram inverse,
and r is the exact optimal residual. The normal-equation gradient uses
`256 ε max(m,n) ||A||F (||A||F ||xComputed||₂ + ||b||₂)`;
the residual diagnostic uses `128 ε max(m,n) (||b||₂ + ||A||F ||x||₂)`.
These are declared acceptance criteria for the selected cohort, not universal
forward/backward-error theorems. Large conditioning-dependent bounds must remain
visible in full findings rather than being summarized as uniformly accurate fits.

Committed optimized results accept 475 factors and 1,412 solves, with 266 factor
and 13 RHS failures. Maximum Q orthogonality defect is `1.23e-15`; relative matrix
reconstruction is `2.23e-15`. In the protected width-nine `δ=2^-33` exact-profile
case, coefficient L2 error is about `5.86e-8`, κF about `3.75e10`, and normal-equation
gradient about `3.98e-16`. This improves the original numerical failure while
retaining the poor conditioning explicitly. The committed M4 Max gate passes 24 deliberate corruption controls and linkage
checks. Complete two-host package evidence is required before tagging or application
adoption.

The algorithm follows the mathematical reflector/pivot representation documented
by [LAPACK DGEQP3](https://www.netlib.org/lapack/explore-html/d0/dea/group__geqp3_gae96659507d789266660af28c617ef87f.html)
and [DLARFG](https://www.netlib.org/lapack/explore-html/d8/d0d/group__larfg_gadc154fac2a92ae4c7405169a9d1f5ae9.html).
This is an independent small scalar Swift implementation, without copied LAPACK
source or its blocked BLAS execution. BombCAD adoption remains a separate bounded
reconstruction/model task under the [weighted QR plan](WEIGHTED_QR_PLAN.md).


## Accepted two-host candidate

Producer `24a17f086b58e9255bc1eb9f403fc55c9e07839f` passes both physical Macs'
complete 287-test/nine-consumer/actual-Metal package gates. The
[physical mini run](https://github.com/emmettl/ContinuumKit/actions/runs/38084667114)
completes successfully. Each complete native QR capture is 26,510,779 bytes; all
741 factor cases, repeated RHS/results and diagnostics are byte-identical across
hosts. Full independent findings and all 24 corruption receipts also match.
[The exact verification record](pivoted-qr-verification.json) retains producer,
source/fixture/script hashes, toolchain/hardware, completed run/job and scope.

The complete [private candidate archive](https://github.com/emmettl/edgerton/pull/70)
retains every output from seventeen suites
for each host, all pinned Core source, complete logs/receipts and lossless native
records. Portable replay checks source and payload identities and reruns all
retained numerical/reference/control gates; the full portable replay passes.
Exact-tag verification and publication
remain the next release gate; application reconstruction adoption is separate.
