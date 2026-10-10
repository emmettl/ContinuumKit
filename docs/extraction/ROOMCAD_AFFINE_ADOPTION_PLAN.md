# RoomCAD affine fitting adoption plan

Bounded follow-up to the independently verified `Numerics.AffineLeastSquares`
primitive. Application baseline is RoomCAD 37d7f8a0491dc4bc1908e71a8e8f63c0f4fd055b,
with verification-only extrusion repair #33 now merged at
`bf869284f29b7604a08d98cf66cf8a2c5619e525` before adoption. Production adoption uses the exact published alpha.18 tag; it remains a separate
application implementation task. This is an
intentional numerical improvement, with independent accuracy comparisons rather
than an assertion of native equality to inaccurate raw-moment coefficients.

## Production boundary

Update the exact package dependency and resolved pin; add Numerics only to
AcousticCore's dependencies. Replace the private raw-moment kernels in
`RoomParameters.swift` and `DecayAnalysis.swift`. Preserve their explicit coordinate
conversions: absolute sample/block indices in RoomParameters, sample times in
seconds in DecayAnalysis. Preserve selected ranges and caller units; do not fold
onset, integration, threshold selection, noise smoothing, five-step crossing
iteration, EDT/T20/T30 extrapolation or absorption-feedback policy into Core.

RoomParameters should use the origin-based fitted line for predictions and noise
crossings. Checked fitting/query failures must map to the existing optional
unavailable-result policy. Any conversion from a crossing to Int must first be
finite and within the application clamp range; no floating-point-to-integer trap
may replace a declared failure. Noise index/iteration differences from improved
arithmetic must be retained and explained, including changed subsequent windows.
DecayAnalysis keeps its negative-slope and unavailable-window rules.

## Complete numerical acceptance

Use one committed fixture with protected original production sources and current
production sources, resolving each exact Core pin. Retain every native input,
filtered response, squared energy, complete backward curve/dB conversion, selected
range/coordinate/value pairs, fitted fields and predictions, and final parameters.
Capture every noise iteration's selected blocks, floor, crossing, index and tail,
plus complete absorption-feedback steps and response metadata. Trace instrumentation
must have explicit source bindings to the actual production operations; a separately
reimplemented algorithm alone cannot establish adoption coverage.

The cohort includes clean analytic decays, deterministic noise and late bursts,
near-threshold/short and silent responses, delayed onsets/large coordinate offsets,
edge and measured octave bands, wave-rendered responses, response summaries and the
existing absorption calibration cases. Preserve measured fixture identities and
credits. High-rate/large-offset numerical probes do not become fabricated measured
room data.

An independent checker derives exact Fraction OLS from each actual selected native
window and checks slope and origin-based predictions. It independently checks
crossing rounding/clamps and complete parameter/noise/tail histories, accounting
for deliberate selection differences through the same documented policy. Retain
original inaccurate coefficients as findings. Fixed unaffected arrays/metadata
should remain byte-identical; changed fitted outputs need declared error criteria,
not loosened application assertions. Deliberately corrupt cases, coordinates,
coefficients, selected windows, iterations, parameter values and source/pins; each
must reject. Run on both physical Macs with complete records and portable replay.

## Application and frozen consumers

Run `make check` and both hosts' actual-Metal standalone CI, release packaging,
strict signature check and headless snapshot inspection. Existing numerical and
measured-case assertions stay unchanged. Heavy BRAS validation retains its separate
scope and is not implied by package/application checks.

Audit every verification consumer which copies AcousticCore into a frozen manifest.
Older pins lack Numerics just as they lacked SpectralTransforms. Use protected
original fitting source snapshots in temporary verification modules, with immutable
source/blob/hash identities and production-copy rejection. Preserve every old
reference pin, case and bound; retire only the current production duplicate.
Re-run every affected frozen consumer, including the extrusion layout benchmark,
before claiming the full CI is green.

Commit and merge the bounded RoomCAD change only after these gates. Public Core
release verification and app adoption evidence remain separate. Weighted spatial
QR, through-origin material projection, heterogeneous waves and changing coupled
mechanics are later contracts.
