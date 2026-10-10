# Single-dispatch mixed receiver observations

A mixed pressure-only/directional receiver set previously encoded two sampling
kernels per timestep. This candidate maps the original ordered receiver set in one
kernel and keeps pressure-only and all-directional sets on their existing paths.
Public plans, native Float arithmetic, clocks, source evolution and owned output
histories retain their contracts.

The new kernel retains the exact pinned pressure reduction and velocity projection
statements. A UInt32.max marker denotes an absent probe; prepared grids' six face
blocks prevent any valid cell from using that address. The kernel exits that lane
before any velocity address/read, and decoding preserves nil. This marker is not a
physical sample or invented valid velocity cell. Converted directional axes are
validated before allocation; source/grid/device checks and receiver ordering remain.

Mixed plans now own one set of copied indices/weights/optional probe/axis buffers,
with stepper-owned pressure/velocity storage reused only after synchronous completion.
One post-sampling buffer barrier covers the combined dispatch. Every velocity,
pressure and injection barrier stays intact; no dependency is relaxed. Existing
separate kernels remain for homogeneous receiver sets and immutable source guards.

Independent affine pressure/face-velocity and absent-probe overflow/error-index
oracles supplement existing whole-history, plan/clock/resource/failure/concurrency
checks. The optimized public consumer checks mixed ordered pressure/nil/velocity
against the retained full kernel. Complete crossed source/model fields, all raw/mixed
readouts/clocks, numerical references and measured model/application cost precede
release or GPU default adoption. No physical accuracy or universal speedup is claimed.

## Verified candidate

Candidate `f9a35802d05a0d349e7500b2c2c89f269bbbd775` passes complete crossed
M4 Max and [physical-mini profiles](https://github.com/emmettl/ContinuumKit/actions/runs/38030041309):
27 runs/13,150,728 field words/27,648 native frames per host, eleven negatives and
independent forcing/final-readout/clock oracles. Every field, native/mixed receiver bit,
clock and input remains exact across hosts, split controls and prior alpha.11 output.

Full local and [mini package checks](https://github.com/emmettl/ContinuumKit/actions/runs/38029950398)
pass 222 tests (35 actual Metal, 46 CPU), three optimized fetched consumers, CPU-only
linkage, exact pinned arithmetic/absent-probe guard and unchanged complete numerical/
topology references. Package producer `6169f9f9dea007451c86357df18757f9531f177c`
has identical library/test/manifest/public-consumer/check sources; the subsequent
profile-only change corrects labels and adds a derived same-group timing summary.
The final evidence checkpoint changes docs only.

Candidate/same-field-group split-control wall ratios are Max 0.922/0.926/0.981
and mini 0.959/0.948/0.989 on 3,888/29,610/331,800 cells. Every repetition and
command interval is retained. These are live-host model measurements with private
timing instrumentation in the control, without isolation or universal speedup claims.
[Aggregate proof](metal-mixed-observation-verification.json) is public; complete
source/field/receiver profiles and package logs are retained privately in Edgerton.
Exact-tag publication and actual application/default acceptance remain separate.
