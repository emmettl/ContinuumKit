# Resident Metal receiver sampling and bounded histories

Status: implemented candidate, unreleased. Alpha.7 remains the published forcing
release. Receiver/application geometry, patterns, mixing, cancellation and longer
history remain caller-owned. This tranche extends the verified CPU observation plan
and neutral lookahead with the original GPU arithmetic and explicit device resources.

`prepareObservation` validates the exact grid, physical device, address capacity and
Float axis representation before uploading immutable mappings. Directional receivers
use the exact original `waveSample` kernel. Pressure-only receivers use its unchanged
ordered Float pressure statements in a velocity-free kernel, avoiding dummy addresses
and unused velocity overflow. Two compact groups retain original receiver order via
an immutable index mapping. Pressure weights remain caller-supplied Float values;
Double axes convert once to Float as in the original app. Nonfinite conversion rejects
rather than clamps. No interpolation, position or axis normalization policy is inferred.

Each stepper owns reusable receiver output storage, bounded to 128 steps per observed
call. Pressure uses R×steps indexing; original native velocity uses R×(steps+1) with
slot zero unused. Size/UInt32 address/resource limits are checked before field work.
Mapped resources stay resident and synchronous completion precedes copying/reuse.
Returned frames own only sampled values; no N-sized field readback occurs per step.
Empty/zero-step observations avoid output allocation or dispatch where appropriate.

`observe` samples the current complete state without advancing its clock. The observed
advance overloads encode velocity → pressure → optional injection → sampling, restoring
all reused bindings on every step. Sampling is read-only. Source/input/grid/device/final-
clock/batch checks precede mutation. Completed model batches remain acknowledged if
readout conversion later rejects a nonfinite sampled value; no partial history or
rollback is promised. Encoding/submission failure invalidates the backend with only
its last confirmed clock. Finite sparse observations do not certify unsampled fields;
full-field certification remains the explicit snapshot contract.

GPU pressure interpolation, native face averaging and Float-axis projection preserve
the original Float operations. Values convert to Double only for owned result frames.
`WaveObservationFrame.arithmetic` distinguishes CPU Double pressure/Float face pairs,
Metal Float sampling and caller-provided data; lookahead rejects mixed arithmetic even
when grid/receiver shape/clock agree. The common aligner preserves one-frame lookahead
and the explicitly labelled final-half-step fallback. Microphone mixing stays outside
Core. No CPU fallback or automatic backend substitution occurs.

Eight new actual-device tests cover affine fields, deliberate CPU/GPU precision
differences, pressure-only minimal grids and unused velocity overflow, Float-axis/input/
clock/size rejection, source/field/output residency and read-only trajectory equality,
257-step owned/chunked histories, plan switching, sparse readout failures and actual
sampled command failure clocks. Existing CPU, forcing, source-free, ABI and independent
reference bounds stay unchanged. The failure seam completes actual commands then
throws; it is not a claim that a driver fault was provoked.

The [observation source map](linear-wave-observation-source.json) pins original full
sampling and microphone timing, plus the retained pressure-only statement identity.
The package verifier checks all old Grid/update/injection blocks and sampling hashes.
The private source preparer binds exact original kernels and mixing beside the candidate;
independent controls retain every native field, receiver clock/value and mixed sample
for 257 steps, including 128-step observation batches and arbitrary lookahead chunks.
Final merge requires the committed-candidate full mini check, fetched packaged consumer,
complete source evidence on both Macs/configurations and strict report postconditions.
Application loop replacement and empirical acoustic validation remain separate gates.
