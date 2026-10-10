# Fitting arithmetic: inventory, conditioning and ownership

Checkpoint: 10 October 2026. No numerical product, release or application migration
is added by this audit. The next bounded implementation is an unweighted affine
least-squares primitive; multiple different operations named “fit” do not become
one interchangeable model.

## Implemented source and actual callers

RoomCAD `37d7f8a0491dc4bc1908e71a8e8f63c0f4fd055b`:

| Source | Git blob | SHA-256 | Numerical operation and policy boundary |
| --- | --- | --- | --- |
| `Sources/AcousticCore/RoomParameters.swift` | `3b5c0e8761ee54b63e0a19b51596673bd702a780` | `ad897708b1e654796786cc7745a68ed88817343df3589f66ff011bc57c6996da` | Private affine line fit of levels against absolute sample/block indices; `slopePerSecond` multiplies the fitted slope by sample rate. Onset, EDT/T20/T30 windows, noise-floor search, tail compensation and crossing iterations remain room policy. |
| `Sources/AcousticCore/DecayAnalysis.swift` | `63fc6c90bb524f50b1b18adddcdd55496d6581c0` | `931363a156f4b52d6c390385ba5cce3f733f9a9742281ffc2063e50f575922b1` | Affine slope against explicitly converted sample times in seconds. Backward integration, dB conversion, first threshold crossings, minimum selected samples, negative-slope acceptance and −60/slope extrapolation remain app policy. |
| `Sources/AcousticCore/AbsorptionCalibration.swift` | `78b785127c33df619e67db32a901b4ce494157a9` | `2ac1cef01e65fc1d55f2b1fe8b7debeba9f8d3f8a8435f3ec6491e3d50011248` | Simulation/measurement feedback, Sabine-inspired area response, optional empirical sensitivity, per-band bounds and best-step selection. This is not a generic linear regression routine. |

Actual users include `RoomDocument/ResponseSummary`, `acousticbench/MeasuredRoom`,
wave response/decay normalization, absorption calibration and their existing room,
noise, edge-band and calibration tests. The two raw-moment kernels are similar but
convert coordinates and units differently; replacing one by the other does not
promise identical native outputs.

Edgerton `ace0b9f1ed2dd8ce63c07577aad9e0ce46f03ec6`,
`Scripts/calibrate-material.py`, blob `9d963dc0b30bb6672da1055d375a887da0d2e8a0`,
SHA `a6b8bf26cb1279b43234b04679e24e957c14317902b17ed5f0a3c0835b43d837`:
zero-intercept shear/bulk projection and a two-coefficient affine solve inside a
601-point relaxation-time search. Constant strain, positivity, time ordering,
loading-ramp correction, search bounds and specimen/measurement semantics are
application/study policy. A Python numerical formula is a mathematical comparison
candidate, not automatically a SwiftPM caller. Active coupled mechanics stay separate.

BombCAD `930bc0116f53f82b7baba8bcadb2a19f94419715`:
`FiniteVolumePressureFit.swift`, blob `31e58a31f681d81b8379fc7e81a000f75ba8df8d`,
SHA `8120e41b29cd28d68c731a96b637bd8db56f6b08c3871241a3f51e5c9c95f7f2`,
uses weighted three/nine-column polynomial QR, reorthogonalization, pivoting and
rank fallback. `ConservedGasReconstruction.swift`, blob
`3e2b5dffd343f26dd0957ac76fdbe3841fcc444a`, SHA
`55ccef8419142735965d7b19b7f961f903546f3bc1d4a0684893b6fd6df59d72`,
adds mean-preserving coordinates, velocity-frame transformation, EOS admissibility
and sampled limiting. These are separate weighted reconstruction/model contracts.
Do not move them merely because they also solve least-squares systems.

Core `c96fb189cf505546200e1f8d0b1fccef5dec4cc9` already owns distinct model-specific
fits: `TiltedPulse.reflectionFit` projects a shifted pulse and searches a bounded
shift, while `ObliqueModeCommand.fitReflection` fits four real incident/reflected
coefficients with a small normal-equation solve and model-specific rank/amplitude
checks. Their independent echo/reflection references remain intact.

## Measured conditioning gap

[The protected original arithmetic audit](../../Fixtures/AffineFitAudit/README.md)
compiles both RoomCAD numerical loops directly and compares complete native inputs
with exact rational OLS. Its 188 cases distinguish already-degenerate native
coordinates from loss in raw sums. The measured M4 Max outcome is 108 reference
agreements, 50 finite coefficient inaccuracies, 27 nonfinite nondegenerate fits
and three native-coordinate rank failures. These are findings, not passing models.

For eight samples at index offset 10^9 with values −10 − j/16, exact native OLS
has slope −1/16 and determinant 336; the original returns −infinity/+infinity.
For a three-sample time fit at sample 480000 and 48 kHz, the measured slope is
−2999.8025580583203 against exact-native −3000.000000028308. The wider 4800-sample,
10-second-start decay-window case has relative slope error about 1.10e−10 and
agrees with this diagnostic bound. These probes do not establish failures in
all existing measured-room use; typical policy windows are a separate integration
cohort. At offset 2^53, two consecutive integers already become identical Double
coordinates, so no fitting algorithm can recover their lost distinction.

## Bounded primitive contract to implement next

Implement only the actual affine least-squares operation over explicit paired
finite coordinates/values. Do not create empty targets for future fitting families.
The operation must declare coordinate/value units as caller-owned, equal dimensions,
minimum count, duplicate/rank handling and coefficient/prediction representability.
A constant response with varying coordinates is valid; constant coordinates are
nonunique and require an explicit failure rather than a fabricated coefficient.

Choose centered/scaled accumulation and result representation only after independent
references establish their error/conditioning behavior. Consider an origin-based
prediction representation to avoid unnecessary intercept cancellation; callers which
need slope/intercept or inverse level crossing must receive usable, clearly checked
fields. Preserve source/result construction boundaries explicitly before tagging.
Nonfinite inputs, arithmetic/output overflow, vanishing native spread and allocation
limits need declared behavior. Do not silently floor variance, accept unsupported
conditioning or claim that high-precision references restore information lost in
native input conversion. Deterministic serial accumulation is the first scope.

Stable arithmetic changes are a numerical change, separate from behavior-preserving
extraction. The original loops and audit identities remain immutable. Any update
must explain where native results intentionally differ and why, instead of weakening
old conformance assertions to force agreement.

## Independent gates and application adoption

1. Exact rational/native references for arbitrary and uniformly sampled coordinates,
   affine/constant/noisy data, translated/reversed/scaled inputs, powers of two,
   tiny/large magnitude and narrow/large-offset windows. A paired old/new match alone
   cannot validate a fitter which shares the same cancellation error.
2. Coefficients, origin-based predictions, residual/normal-equation properties and
   rank/finite/representability failures. Include any centered/scaled conversions
   explicitly, plus deliberate coefficient/input/dimension/source corruption.
3. A committed optimized public CPU consumer, source/version pins and both physical
   Macs' complete inputs/results. No application, UI or Metal dependency is needed
   for the primitive. Release only after its independent contract succeeds.
4. Separate RoomCAD integration with complete selected windows, fitted coefficients,
   EDT/T20/T30, noise cut/crossing/tail histories, rendered/measured bands, response
   metadata and absorption-feedback histories. Retain measured fixture identities,
   source/assumption labels and full application/package checks. Numerical changes
   need bounded accuracy criteria; they cannot be presented as byte-preserving moves.

Keep onset/noise detection, decay integration/windows/extrapolation, material laws,
calibration targets, positivity/ramp correction, search/limiting policy and measured
validation with their owners. Through-origin projection, weighted multi-column QR
and physical reconstruction are later independently bounded contracts. Heterogeneous
fluids, Edgerton's 2D forcing/damping and changing mechanics remain separate gaps.
