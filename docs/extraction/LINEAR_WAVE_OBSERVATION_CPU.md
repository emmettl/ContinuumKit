# Prepared CPU receiver observation and explicit lookahead

Status: implemented CPU candidate, unreleased. Alpha.7 remains the published pressure-
forcing release. Resident Metal sampling and production application adoption follow
separately; no app loop or microphone-pattern policy is moved by this tranche.

`PreparedWaveObservation` validates ordered eight-slot pressure stencils and optional
velocity probes, bound to the exact prepared grid. Repeated indices and signed/zero
weights remain legal; every address is checked even when its weight is zero. Read-only
inactive padding is not reinterpreted as geometry. A velocity probe requires all three
negative-face addresses to lie in the correct grid row/plane and a finite Double axis.
No weight/axis normalization, spatial clamping or material selection occurs in Core.

`CPUWaveStepper.observe` reads only prepared slots from resident fields and returns an
owned `WaveObservationFrame`. Pressure/density interpolation accumulates in Double in
source order. Velocity face pairs add in Float before Double conversion/averaging;
standard-library SIMD product/sum preserves the original Double projection operation.
Pressure-only receivers omit velocity work and return nil rather than a fabricated zero.
An observation overflow rejects the readout without invalidating otherwise finite model
fields. Field validity and sparse-read validity are different contracts.

The observation overloads of `advance` retain every post-update/post-injection readout,
at most 128 complete steps per call. This bounds temporary history; the application
chooses cancellation cadence and owns any longer history. Source/input/plan/step/final-
clock validation precedes mutation. A numerical model failure keeps its existing
invalidation/acknowledgement semantics. A derived readout failure can occur after a
completed model step: that clock remains acknowledged, the field state remains usable,
and no partial history or rollback is promised. Sampling changes no numerical update.

Frames retain pressure index, timestep, integer pressure clock and preceding half-step
velocity clock. Sampled frames also retain opaque observation-plan identity; lookahead
cannot silently mix receiver plans of the same shape. Public value construction is not
numerical certification; alignment validates clock/shape/finiteness before accepting it.

`WaveObservationAligner` uses one pending frame across arbitrary chunks. It returns the
prior pressure and average of the two adjacent projected velocities, preserving the
original Double addition then division. `finishUsingFinalHalfStep` explicitly chooses
the original final-sample fallback. That last frame is labelled and retains its earlier
half-step velocity clock rather than claiming a centred measurement. Rejected whole
chunks preserve pending state. Exact consecutive indices, fixed timestep/receiver shape,
velocity-presence mask and plan identity are required. Microphone mixing, pattern share,
sound-speed scaling, audio-rate conversion and end-of-stream policy remain caller-owned.

Independent tests cover affine physical pressure/velocity fields, a cancellation example
that distinguishes Double pressure reduction from Float, Float-before-Double velocity
rounding, invalid neighbours/shape/weights/axes, read-only failure, owned plan/frame values,
bounded/chunked forced history, a hand-derived velocity ramp, explicit terminal clocks,
rejected chunks and provenance. No source-free or forcing reference bound is weakened.

The [immutable source map](linear-wave-observation-source.json) records original masked
CPU sampling and microphone-timing blocks. The private preparer binds those statements
unchanged beside the candidate. Independently chosen controls retain every native field,
raw pressure/velocity readout, complete clock and final mixed output for 257 steps, in
debug/release. Compare one-step and bounded-history execution and arbitrary lookahead
chunks against the exact original loop. Final merge requires full committed-candidate
mini checks, the fetched CPU-only consumer/linkage guard and complete source evidence.
Resident Metal needs its own Float pressure/velocity rounding and encoded-history gate;
CPU success does not stand in for that implementation or empirical room accuracy.

## Verified CPU checkpoint

Implementation `552f7cf0dd1b969d98f30c0a38633f05ab1594ac` passes the
[full physical-mini check](https://github.com/emmettl/ContinuumKit/actions/runs/38011548981):
199 tests, all 38 CPU tests, fetched observation/lookahead and CPU-only linkage,
with all existing references and actual Metal regressions intact. Final source
candidate `d637788ebe771950b1ef1c43d3186060b0633c7e` changes only the independent
two-layer fixture anchor; production/test/consumer code is identical. Its optimized
fetched CPU consumer passes separately. No validation assertion was relaxed.

The [private receiver mini gate](https://github.com/emmettl/edgerton/actions/runs/38011890175)
and M4 Max counterpart pass 4,128 complete native-field/receiver captures and 12,336
mixed samples across hosts/debug/release, with zero runtime Float32/Float64 bit
mismatches and corresponding complete reports byte-identical. Every 257-step case
compares direct and 128-step observed batches, arbitrary 37-frame lookahead chunks
and exact original final microphone output. The producer and independent postcondition
require full field/receiver/clock/history/dependency scope; seven adversarial controls
reject altered or missing evidence. [Aggregate verification](linear-wave-observation-cpu-verification.json)
records identities. Complete raw outputs, pinned wrappers/controls, clean producer
environments, dependencies and logs are retained privately in Edgerton. The subsequent
checkpoint adds documentation only; encoded Metal observations remain the next tranche.
