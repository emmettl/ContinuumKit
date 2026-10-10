# Real FFT verification and extraction plan

This is a bounded planning checkpoint. It adds no transform implementation, public
API, product or application migration. Complete BombCAD Euler adoption remains its
own gate; this candidate addresses a separate numerical-primitives gap.

## Implemented source and actual consumers

RoomCAD `2bc11ed6a033e8642de4018e8e9ae9cfb4e1151c`, path
`Sources/AcousticCore/RealFFT.swift`, Git blob
`6764b9fe1caafde501e30dac3bd94d74b88dfe39`, SHA-256
`63da5cb9c3ead610051a2b43faf3c345d4168d7e6580abd25ea202c18877b617`.
The file owns an Accelerate Float64 real-transform wrapper, packed weighted
accumulation, padded real filtering and Float32 linear convolution. Retain its
MIT attribution and immutable original before extracting any implementation.

Current callers include BandRenderer, DecayAnalysis, ResponseComparison,
RoomResponse, ValidationScene, WaveSolver and AuditionPreview. WaveSolverTests use
transforms/filtering through physical-mode checks; AuditionTests compare a small
direct convolution and check empty inputs. These are useful integration evidence,
not a dedicated packing, normalization, safety and spectral contract suite.

## Contract decisions and observed gaps

The source constructor and forward call trap on invalid lengths. Inverse currently
does not check that both arrays contain `length / 2` elements before handing their
storage to vDSP. Weighted accumulation assumes compatible, nonempty packed arrays.
Filtering/convolution select power-of-two storage by unchecked integer arithmetic.
Specify these failures and representability limits before exposing reusable APIs.
Do not silently change supported numerical cases or hide unsupported input behind
an application policy.

Declare length, DFT sign, real/imaginary ordering, DC/Nyquist handling, scaling and
frequency units explicitly. Apple's primary [data packing reference](https://developer.apple.com/documentation/accelerate/understanding-data-packing-for-fourier-transforms)
documents the distinct real forward/inverse scaling and packed endpoints. Decide
whether the public representation preserves the existing packed convention or
provides an explicit conversion; prove either boundary independently.

Define setup ownership/lifetime and supported reuse without assuming concurrent
setup access is safe. Specify finite data/coefficient handling, sample-rate and
padding validity, count overflow and Float32/Float64 conversion behavior. Result
construction must be usable by actual accumulation/convolution callers, with
clear checked versus unchecked ownership; audit those call sites before tagging.

A real frequency response and zero-phase operation do not imply causality or an
arbitrary finite impulse support. Describe padded circular filtering and trimming
precisely. Extra padding alone must not promise zero wrap error for an unbounded
impulse response. Room bands, absorption, decay fitting, measured response policy,
audition scheduling and sample-rate conversion remain application-owned.

## Independent acceptance

- DC, Nyquist, single-bin sine/cosine, phased modes, impulses and small deterministic
  mixed signals must match a separately authored scalar O(N²) DFT, including both
  packed endpoint slots. Test lengths from the smallest supported size upward.
- Direct inverse references, round trips, shift/sign symmetry and Parseval energy
  must use the declared normalization and complete native arrays. A round trip
  alone can conceal paired scale/sign errors.
- Accumulation must weight DC and Nyquist independently and match analytical
  single-mode gains, multiple input sums and declared response bin frequencies.
- Convolution must match scalar time-domain sums, including exact full length,
  impulse identity, endpoint/Nyquist-dominated cases, empty inputs and asymmetric
  signals. Padding/trimming checks must distinguish finite-support convolution
  from a general frequency response.
- Invalid lengths/dimensions, non-finite data/coefficient decisions, invalid rates,
  negative padding and overflow boundaries need direct failure contracts. Deliberate
  adaptation of the current trap/unsafe behavior requires explicit provenance.

Then enumerate complete original/shared transform/filter/convolution inputs and
outputs over a representable case tree. Retain values/bits, parameter identities,
Git pins, hardware/toolchain and independent error/energy bounds. Require corruption
controls beyond paired equality, both physical Macs and a clean optimized public
consumer without application, renderer or Metal linkage. Accelerate linkage is
part of this candidate's declared platform capability.

Only after those gates pass should a minimal implemented numerical module be
added/released. RoomCAD adoption separately verifies complete band rendering,
response comparison/decay, wave-validation and audition outputs plus full packaging.
Changing acoustic propagation, measured calibration and Edgerton's spectral model
remain independent contracts. Previous releases and reference identities stay intact.
