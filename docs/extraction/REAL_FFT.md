# Checked real FFT candidate

`SpectralTransforms` is an implemented macOS 15+ Accelerate primitive. It has no
application, UI, renderer or Metal dependency. Alpha.17 now releases this primitive; RoomCAD adoption remains
a separate application gate. Release and complete
application adoption remain separate gates.

## Provenance and unchanged supported arithmetic

RoomCAD revision `2bc11ed6a033e8642de4018e8e9ae9cfb4e1151c`,
`Sources/AcousticCore/RealFFT.swift`, Git blob
`6764b9fe1caafde501e30dac3bd94d74b88dfe39`, SHA-256
`63da5cb9c3ead610051a2b43faf3c345d4168d7e6580abd25ea202c18877b617`.
Its MIT source is retained byte-for-byte in
`Fixtures/RealFFTConsumer/Sources/RealFFTConsumer/OriginalFFT.swift`; that file
compiles directly in the consumer. Attribution follows the existing RoomCAD and
ContinuumKit MIT licences.

The extraction keeps vDSP packing, transform calls, scaling, response callback
order, right padding, prefix trimming and convolution products. It adds public
access and checked throwing boundaries. Accumulation works on a temporary copy
and commits only after all checks. Additional finite scans and copies are not a
throughput claim. No existing acoustic policy or FFT caller is migrated here.

## Public numerical contract

`RealFFT(length:)` owns one radix-2 Double setup and destroys it at deinitialization.
A valid length is a power of two >= 2 with `2 * length` representable as an Int.
On 64-bit hosts the largest arithmetic-valid length is `2^61`. This arithmetic
bound is not a memory availability promise: large allocations can fail outside
Swift's recoverable error model. A failed vDSP setup reports `setupUnavailable`.
Reuse one instance serially. The class is deliberately not Sendable; concurrent
sharing of its setup is not part of the contract. Separate owners can create
separate setups. No global cache or scheduling policy is introduced.

For real samples x[j], `forward` returns **twice** the usual negative-exponent DFT:
`X[k] = 2 sum_j x[j] exp(-2 pi i j k / N)`. Each array has N/2 elements.
`real[0]` stores X[0], `imag[0]` stores the real Nyquist value X[N/2], and
remaining real/imag entries represent positive bins 1..<N/2. The redundant
negative half follows conjugate symmetry. `inverse` accepts this packed convention
and normalizes the vDSP result by `1/(2N)`; it can be called with independently
constructed packed arrays. Parseval uses packed endpoint squares plus twice the
interior squared magnitudes, divided by 4N.

The public `Spectrum` is a labelled tuple of mutable Double arrays. Callers can
construct zero sums and edited transfer spectra without internal initializers.
Construction is unchecked; every transform/accumulation operation checks its
own input dimensions and finite values before accessing vDSP pointers.

`accumulate` adds a real response-weighted packed spectrum to a compatible sum.
The sample rate is finite positive samples/second; response arguments are Hz.
Responses are called in the original order: 0 Hz, rate/2, then ascending interior
bins k * (rate/N). DC and Nyquist receive separate real gains. Negative gains are
supported. There are no acoustic band, amplitude or passivity constraints.
Finite coefficients and finite results are required. A rejected operation leaves
the entire sum unchanged; side effects already performed by a response closure
are caller-owned and cannot be rolled back.

`paddedLength(count:padding:)` checks nonnegative counts/padding, their sum and
next power-of-two rounding without allocating. It returns at least 2.
`zeroPhaseFilter` pads **on the right** to that length (count + padding, not count
+ twice padding), applies the sampled real gain by circular filtering, and
converts the original prefix back to Float. Default padding is 16384. An empty
input still constructs the planned transform and evaluates its response bins,
matching the original. Rates, padding and coefficients are still validated.
This is a sampled circular operation; general response padding does not guarantee
zero wrap error, causality or a finite impulse support.

`Convolution.convolve` returns the full Float linear convolution, count a+b-1,
using Double spectra, one factor-of-two compensation in the packed product, and
sufficient zero padding. Either empty input returns [] immediately, including
when the other input contains nonfinite samples. Nonempty inputs must be finite.
The returned Float conversion uses Swift's ordinary rounding; finite values
which become infinity report `floatOverflow`. Float underflow/subnormal rounding
is retained. No clipping, saturation, normalization or resampling is applied.

## Deliberate safety adaptations

The original constructor/forward dimension traps become `invalidLength` and
`invalidDimensions` errors. The original unchecked inverse/accumulation dimensions
are rejected before pointers or indices are accessed. Storage overflow and invalid
padding are checked separately. Nonfinite inputs, response coefficients, Double
outputs and Float conversion overflow have declared errors. These unsupported
cases are new safety contracts, not an assertion that the unsafe original had
matching behavior. Invalid requests return no partial output. Error categories
are public; detailed ordering when multiple input requirements fail is not
promised. Allocation exhaustion is not caught.

## Independent acceptance and complete native conformance

Ten focused Swift tests independently implement a scalar DFT and direct inverse,
check every positive bin, DC/Nyquist/sign/phase, Parseval, serial round trips,
weighted sums and callback frequencies, time-domain centred circular filtering,
full direct linear convolution, dimensions, rate/data/coefficient failures,
no-allocation overflow planning, accumulation rollback and Float overflow.

`Scripts/check-real-fft-consumer.sh` requires a clean committed source and builds
an optimized Git-fetched public consumer. It compiles the protected original and
shared implementation, with complete native values/bits and inputs for:

- lengths 2/4/8/16/32, DC/Nyquist/mixed samples, distinct impulse positions and
  all positive-bin phased cosines/sines;
- four independent packed inverse spectra per length;
- seeded two-input weighted sums, three sample rates and four gain functions;
- five filter input counts, four padding counts and four gain functions;
- eight asymmetric convolution lengths per side and three input families,
  including empty, endpoint impulses and Nyquist-dominated samples.

`verify-real-fft-output.py` independently enumerates the full case tree, verifies
native bit identities, scalar O(N²) DFT/inverse, Parseval and normalization,
response bins, seeded sums, padded circular filtering and direct convolution.
Transform tolerances are 256 Double epsilon * N * max(1,L1 reference scale).
Float output tolerances are 4 Float epsilon * max(1,L1 input/product scale);
these are declared bounded small-case reference checks, not global FFT error
bounds. Complete original/shared native values/bits must also agree exactly.
This bounded case tree contains 437 complete cases and 4953 returned output
values per variant. Twenty public checked-failure cases are separate from original unsafe behavior.
Thirteen deliberate corruptions challenge independent references/completeness,
including changes applied to both native variants. Environment, source hashes,
resolved Git pins and linkage are retained. Both physical Macs and the full
package/existing consumers are required before release.

Next, RoomCAD adoption must retain complete band rendering, response comparison,
decay, wave-validation and audition outputs, plus full application packaging.
Its acoustic bands, absorption, fitting, measured fixtures, preview scheduling
and sample-rate conversion remain application-owned. Edgerton's spectral model
is not changed by this primitive.

## Accepted candidate checkpoint

Measured source `fe910ed874c57d662d5b49753bd3b34eb35c93dd` passes full
`Scripts/check.sh` on M4 Max and [physical Mac mini](https://github.com/emmettl/ContinuumKit/actions/runs/38064739019):
271 tests, seven optimized Git consumers, actual Metal and all existing reference
and topology gates. All 437 original/shared FFT cases and 20 checked failures
are byte-identical across the hosts; 13 corruption controls reject.
[Verification identity](real-fft-verification.json) records scope. The complete
private evidence archive retains 59 hashed payloads, both producer/checker source
phases and a portable reconstruction/reference replay. The initial signed JSON
zero reporting failure is retained; its correction changed no transform arithmetic.
This documentation checkpoint adds no numerical or consumer changes. Next are
an exact-tag release gate and separate RoomCAD adoption.

## Released alpha.17

The candidate is now published as [alpha.17](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.17)
from immutable commit `e94d329c55495ca561306174d624eadf5c8e7da0`, after its
[exact-tag physical-mini verification](https://github.com/emmettl/ContinuumKit/actions/runs/38065611335)
passes all 271 tests, seven optimized exact-version consumers and actual Metal.
Complete original/shared FFT arrays remain byte-identical to the accepted two-host
candidate, with all independent references and corruption controls passing.
[Publication proof](alpha17-release-verification.json) and the complete private
24-payload replay archive retain source/version and numerical evidence. The
standalone primitive is released; RoomCAD adoption remains separate.
