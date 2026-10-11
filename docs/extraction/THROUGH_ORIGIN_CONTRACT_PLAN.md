# Direct through-origin projection: bounded next numerical task

Checkpoint: 11 October 2026. The protected source audit and existing-alpha.19
comparison are complete in [Core #71](https://github.com/emmettl/ContinuumKit/pull/71)
and [Core #72](https://github.com/emmettl/ContinuumKit/pull/72), with complete
native/source/reference archives in private Edgerton #74/#75. This document
specifies the next investigation; it adds no API, target, release or app migration.

## Reason for a distinct investigation

The original material formula loses range in raw squared/cross products. Released
single-column QR recovers the selected range cases, but returns negative zero for
both orderings of `[2^53,1,-2^53]` projected onto `[1,1,1]`, whose exact-native
coefficient is 1/3. Its absolute diagnostic budget permits this cancellation loss.
The scaled compensated prototype preserves that particular coefficient. Neither
result establishes a general direct-projection accuracy or support guarantee.
The full findings, including original rejections, remain protected.

The mathematical operation is `c = sum(x*y) / sum(x*x)` for explicit paired
coordinates/values, with no intercept. Caller units determine the coefficient's
units. Count, sign, specimen interpretation and physical applicability are
separate policies; a generic projection can have one sample or a zero/negative
coefficient. A zero strain vector is nonunique and must fail explicitly.

## Candidate boundaries to settle before implementation

- Use the existing `Numerics` module only if a distinct checked operation earns its
  place. A possible type name is provisional until the contract and evidence exist.
- Require matching, nonempty finite arrays; choose and test an allocation cap,
  starting from the existing one-column QR limit of 1,048,576 samples. No hidden
  material minimum count, positivity rule, rank floor or regularization is added.
- Normalize each vector with independently chosen lossless power-of-two scaling.
  Explicitly reject unsupported native dynamic range rather than erase nonzero
  inputs. Zero response is valid; normalization and final rescaling are separate.
- Investigate corrected products and accumulation before choosing an algorithm.
  Positive denominator products and signed numerator cancellation need separate
  analysis. Do not infer reliable multiplication from a good summation routine.
- Define overflow, product/correction underflow, cancellation-dominated output,
  final coefficient underflow and unrepresentable residual/prediction behavior.
  An uncertainty diagnostic is not a certified error enclosure unless its bound
  is derived and independently checked. Never silently replace arithmetic failure
  with a zero or positive modulus.
- Decide whether the result needs scaled residual diagnostics, usable predictions,
  a proven absolute enclosure or an explicit unsupported-accuracy outcome. Do not
  promise universal correct/faithful rounding from the 90-case comparison alone.
  Expose only independently useful fields with checked construction boundaries.

Ogita, Rump and Oishi's [Accurate Sum and Dot Product](https://ogilab.w.waseda.jp/ogita/math/doc/2005_OgRuOi.pdf)
(2005, sections 3 and 5) is a primary algorithm/error-analysis reference. It treats
compensated products/sums and FMA product correction, with explicit underflow
terms and assumptions. Those results do not automatically transfer to a Swift
implementation, normalization scheme or coefficient quotient. Any chosen bound
must account for those additional operations and the actual compiler/runtime.

## Independent completion gates

1. Preserve the complete 90-case source audit and comparison, their exact native
   inputs and original findings. Add ordinary/noisy/signed/zero projections;
   reversed and permuted orders; positive/negative coefficient cases; powers of
   two; disparate component exponents; subnormal products/corrections; nearly
   cancelling numerators; long vectors and limit/one-past-limit controls.
2. Generate exact rational projections from native binary64 values. Retain every
   native normalized input, product/correction, accumulation state or complete
   replay witness, selected output/failure, residual and scale conversion. Include
   cases where intended decimal input was already lost during native conversion.
3. Independently verify normalization round trips, denominator/rank classification,
   exact projection orthogonality, coefficient/prediction/residual representations
   and the declared supported-range/error decisions. Separate absolute error from
   relative/sign recovery. A loose absolute pass must not conceal another lost 1/3.
4. Apply coherent corruptions to source/pins, products and corrections, accumulated
   terms, rescaling, outputs and derived residuals, failure decisions and any claimed
   error bounds. Mutate the data and all its dependent fields together; reject
   against independent input/reference contracts.
5. Run the complete standalone suite and optimized clean exact-Git consumer on
   both physical Macs. Retain full source/flags/runtime/native/reference/control
   receipts and a network-free portable replay before release. Existing affine,
   QR and other primitive contracts remain protected and their tags immutable.

After these gates, decide whether to publish a new Numerics operation. Edgerton's
Python calibration needs a separate integration decision and complete frozen
CSV/result checks; it is not already a SwiftPM consumer. Preserve its three-sample
and positive-modulus policy, hydrostatic bulk semantics, specimen metadata and
separate relaxation search. Active coupled/contact/fracture mechanics and measured
impact validation remain outside this task.
