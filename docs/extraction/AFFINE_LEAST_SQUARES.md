# Stabilized affine least squares

`Numerics` is a new implemented Swift-only numerical product. It adds
unweighted affine least squares over explicit paired Double coordinates/values.
It imports no application, Foundation, Accelerate, UI or Metal module. It is a
numerical improvement, not a byte-preserving extraction. Alpha.18 releases this
contract after the separate exact-tag gate; no application has adopted it yet.

The [original fitting audit](FITTING_PLAN.md) and both complete RoomCAD snapshots
remain immutable. Original raw-moment arithmetic loses variance/covariance through
subtraction of large sums. The candidate shifts first, scales, centers normalized
data and sums variance/covariance with serial Neumaier compensation. When finite
opposite extremes overflow the initial difference, normalization uses coordinate
zero and maximum magnitude instead. The complete slope uses significand/exponent
multiply/divide, avoiding an overflowing intermediate scale ratio. The library
never floors variance or fabricates a unique fit for constant native coordinates.

## Contract and owned results

`AffineLeastSquares.fit(x:y:)` requires equal counts >= 2 and finite native inputs.
Coordinate and value units belong to the caller; slope units are value/coordinate.
Repeated coordinates are allowed when there is remaining spread. Constant values
with varying coordinates give a constant line. Already-identical Double coordinates
cannot recover lost integer detail and return `rankDeficient`.

`Result` is immutable, Equatable and Sendable, with count, a finite origin, value
at that origin and slope. Only `fit` constructs it; no unchecked public constructor
allows inconsistent line fields. Normalized variance and covariance-cancellation
ratio are exposed as diagnostics. The latter is sum(abs(centered products)) /
abs(covariance); it is infinity for zero covariance with nonzero centered products,
and 1 for an exactly constant response. It is not statistical uncertainty or a
numerical accuracy certificate. Severe covariance cancellation can limit relative
slope accuracy even when the result is finite; callers own acceptance policy.

`value(at:)` evaluates the returned origin-based line with fused multiply-add.
If opposite finite extremes overflow their difference, it uses a halved difference
and a fused final sum. `intercept()` is checked evaluation at zero: extrapolation
can overflow and amplified coefficient rounding can make relative intercept error
large near zero. Use the origin-based line near supplied samples. `coordinate(at:)`
inverts that same rounded line; constant slope reports `constantFit`. Its centered
formula and halved fallback handle finite extreme queries without materializing an
unnecessarily overflowing difference/shift. This is algebraic inversion, not a
noise/decay-window decision.

Nonfinite inputs/queries, invalid dimensions, rank loss and output representations
have explicit failures with no partial Result. A nonzero native shifted/global
normalization term that becomes zero is rejected as `unrepresentableNormalization`;
it is not silently discarded. A nonzero computed normalized slope which overflows
or rounds to zero in output units is rejected as `unrepresentableCoefficient`.
Predictions and crossings reject nonfinite outputs. Allocation exhaustion remains
outside recoverable Swift errors. Ordinary binary64 rounding, including subnormals,
and possible cancellation short of vanished terms remain explicit limitations.
No universal relative-error guarantee, passivity law or measured accuracy claim is
implied for arbitrary finite data.

The fitter allocates normalized arrays and accumulates deterministically in serial
order. It adds no parallel scheduler, global state, sample weighting, robust-loss
estimator, regularization, rank-tolerance floor or hidden acoustic interpretation.

## Independent verification

Ten focused Swift tests check translated exact lines, an independent rational noisy
fit, constant values/repeated coordinates, reversed data, subnormal/huge scales,
zero covariance with an overflowing scale ratio, vanished normalization rejection,
native dimension/finite/rank failures, coefficient and query representations, and
extreme translated predictions/inverse crossings.

`Fixtures/AffineFitConsumer` builds from a clean committed Git dependency using only
public `Numerics` APIs. Its complete 300-case tree includes all 188 protected audit
inputs, 98 affine power-of-two scale/reversal cases, seven additional extreme cases
and seven invalid-input cases. It emits complete native x/y, coefficient/origin,
diagnostics, every prediction, intercept and inverse queries, including explicit
failures. The original audit's nonfinite/inaccurate coefficients remain findings
and are never rewritten to make the new primitive agree with them.

`verify-affine-fit-output.py` derives exact rational affine OLS from every actual
native input. It independently checks input/case identity, rank and representation
categories, slope/origin/predictions, intercept extrapolation and inversion of the
public rounded line. Its bounded chosen-case checks use 128 Double eps relative
to slope and 256 eps relative to relevant ordinate/coordinate magnitude, with
four output ulps as a minimum. These are declared reference-suite limits, not a
global theorem. For exact zero covariance the suite requires zero slope. Extreme
unrepresentable coefficients, normalization and queries have explicit outcomes.
Thirteen coherent-bit/input/coefficient/query/case-scope corruption controls
must reject. Dynamic linkage rejects Accelerate, UI and Metal frameworks.

Committed two-host results are 264 supported fits, 36 declared failures and 50,409
complete predictions. Every nondegenerate original audit input is now independently
accurate; the three already-degenerate native coordinate cases correctly reject.
Maximum measured relative slope error in the complete cohort is about 2.28e-16.
Both physical Macs pass 281 tests, eight optimized fetched consumers, actual Metal
and all previous numerical/topology gates. The full native fitting and original-audit
records are byte-identical across hosts. The [physical-mini run](https://github.com/emmettl/ContinuumKit/actions/runs/38073509760)
verifies committed producer `a4fb9fe263dd059d2040f1719f4d68e8853ea5dd`;
[verification identity](stable-affine-fit-verification.json) records the complete scope.
The separate [exact-tag release](https://github.com/emmettl/ContinuumKit/actions/runs/38074459965)
now passes 281 tests, eight exact-version optimized consumers, actual Metal and all
previous references on the physical mini. Local Max exact-tag verification also
passes; all 300 raw fit and original-audit records remain byte-identical to the
accepted candidate. [Publication identity](alpha18-release-verification.json) records
alpha.18's immutable tag/commit and successful release. No original audit identity changes.

## Application ownership and adoption

RoomCAD's selected sample windows, dB conversion, onset/noise detection and noise
crossing/tail iteration, EDT/T20/T30 extrapolation, absorption-feedback search and
all measured fixture policy remain application-owned. The [separate adoption plan](ROOMCAD_AFFINE_ADOPTION_PLAN.md) must capture
complete selected coordinates, coefficients, predictions and output parameters/
noise histories; intentional arithmetic changes need accuracy criteria instead of
old/native byte-equality claims. Through-origin projection, Edgerton's constrained
material/relaxation search and BombCAD's weighted polynomial QR/limiting are distinct
contracts. This candidate does not migrate or generalize those models.
