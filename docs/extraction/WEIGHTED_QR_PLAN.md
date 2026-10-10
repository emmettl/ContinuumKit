# Weighted QR: source audit and bounded implementation plan

Checkpoint: 10 October 2026. RoomCAD's alpha.18 affine adoption is complete.
The next fitting contract is a reusable multi-column least-squares factorization.
Its numerical stabilization must precede any gas reconstruction migration.

## Current source and ownership

The fresh BombCAD remote checkpoint is
`5f2e50dcef5a5adcde3d3c4cb811426e6de2fe6c`. The pressure fit and conserved
reconstruction have the same blob identities as the earlier fitting inventory;
this is verified against the current source rather than assumed from the older
local checkout. [The protected audit](../../Fixtures/WeightedQRAudit/README.md)
records full source/blob/SHA-256 identities and compiles original arithmetic.

`FiniteVolumePressureFit.Stencil` constructs three linear and nine quadratic
mean-free polynomial columns, scales coordinates and covariance differences, then
multiplies both rows and mean-difference RHS by `h / distance`. Thus the objective
weights are the **squares of those row multipliers**. It factors each stencil once
and reuses factors for conserved components. A requested quadratic fit falls back
to linear, then to the preserved cell mean. The private QR uses column pivoting,
modified Gram-Schmidt and two projection passes onto remaining columns, with
relative pivot floor `1e-10 * initialNorm` and naive squared column norms.

Actual current callers include `ExperimentalVolumePressureFitStudy`,
`ConservedGasReconstruction`, `ConservedGroupedGasGeometry`,
`MovingConnectedGasGroups` and `ExperimentalWallReflectionStudy`. Optional
experimental gas paths already consume reconstructed conserved quantities; the
old pressure-fitter comment saying that no numerical gas stage uses it is not a
complete description of current callers. This audit does not change those paths.

| Potential shared contract | Remains with the reconstruction/model owner |
| --- | --- |
| Finite rectangular matrix factorization, rank policy, column permutation and repeated RHS solve | Geometry, units, cell moments, polynomial basis, scale and distance row multipliers |
| Dimension/finite/representation errors and conditioning diagnostics | Quadratic/linear/constant fallback and mean restoration |
| Stable norms, factor orthogonality and backward error | Velocity-frame transforms, sampled limiting and EOS admissibility |
| Independent complete native conformance | Face fluxes, wall interactions, moving geometry, conservation under transport and measured validation |

A bound enforced at supplied control points does not prove global positivity.
An independently accurate QR does not validate the chosen gas reconstruction.

## Findings and stabilization gates

The protected cohort contains 272 direct cases and 176 actual stencils, retaining
624 complete factor records. Exact rational references use actual binary64 A/b.
Twenty accepted solves exceed the chosen coefficient diagnostic; eight accepted
factors exceed the Q orthogonality diagnostic. Forty-eight otherwise full-rank
records reject at extreme scales where naive squared norms overflow/underflow.
Four direct short/long RHS probes silently truncate through `zip`; the actual
stencil's dimension precondition prevents that particular malformed call.
Ordinary selected geometric cases agree in this cohort. This does not imply that
all geometries or actual transport histories are verified.

Near dependence requires a conditioning contract, not a universal coefficient
accuracy promise. The exact-native forward coefficient findings must be retained
alongside orthogonality, reconstruction/backward error and rank-policy outcomes.
Do not adjust diagnostic bounds to hide accepted inaccuracies, or conflate the
existing relative rank cutoff with exact mathematical rank.

1. Implement a bounded deterministic CPU factorization in `Numerics`, using safe
   scaling/norms and a justified orthogonal factorization. Declare dimensions,
   finite inputs, allocation limits, relative rank tolerance, permutation,
   representability failures and result construction boundaries explicitly.
   Keep geometry and row-weight construction with callers. Prefer an immutable
   factor reusable for multiple RHS; solve must check the full RHS dimension.
2. Add independent exact-native/high-precision references across ordinary and
   ill-conditioned systems, common/column scaling, pivot/rank boundaries,
   reversed rows, malformed/nonfinite inputs and repeated distinct RHS. Check
   orthogonality, matrix reconstruction, residual/normal-equation/backward error
   and condition-dependent coefficients. Include coherent output corruption and
   all primitive error paths. Preserve the original audit unchanged.
3. Verify a committed optimized public consumer and the package on both physical
   Macs. Release only after the declared primitive contract passes. CPU QR has
   no application or Metal dependency, even when its CI host also serves Metal.
4. Bound BombCAD adoption separately against its then-current source. Retain
   complete original/shared factors, reconstruction means/coefficients/control
   values, degree fallback, conserved components, limiter/frame/EOS histories and
   affected wall/transport/moving-group references. Explain intentional accuracy
   and fallback changes. Existing app tests and compile checks do not replace
   those independent references.

Through-origin material projection, acoustic selection/calibration policy,
heterogeneous/2D waves and changing coupled mechanics remain distinct gaps.
This checkpoint changes no application dependency, numerical implementation or
release tag. Two-host accepted audit identities and complete retained evidence
will be added after the clean candidate finishes both gates.
