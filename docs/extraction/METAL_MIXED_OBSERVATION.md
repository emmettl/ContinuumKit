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
