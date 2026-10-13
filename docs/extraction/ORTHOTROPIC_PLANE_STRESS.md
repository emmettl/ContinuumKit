# Bounded orthotropic plane-stress elasticity

The `SolidMechanics` product exposes `OrthotropicPlaneStress` and its nested
immutable `Frame` and `Result`. This is the P1 Edgerton elastic kernel, with only
the public type name changed. It imports Foundation and simd; no application,
renderer, Metal, Accelerate or UI dependency is required.

## Contract

Moduli/stress use Pa and energy density uses J/m³. Strain is dimensionless
`(epsilon_xx, epsilon_yy, engineering gamma_xy)`; stress is
`(sigma_xx, sigma_yy, tau_xy)` in the supplied sheet frame. Grain angle is radians,
from frame x toward y. The orthonormal world frame uses tolerance 1e-10;
its normal is x cross y. World stress is a symmetric infinitesimal Cauchy tensor
with zero normal traction. A common rigid world rotation rotates this tensor
and leaves sheet stress/energy unchanged. This is frame covariance of a
small-strain law, not a finite-strain constitutive update.

Positive finite E1/E2/G12, reciprocal nu21 = nu12 E2/E1, and compliance
denominator greater than 1e-12 are required. Negative Poisson ratios are allowed
when compliance is positive definite. Overflowing stiffness is rejected.
The declared principal-strain limit must be in (0, 0.01], defaults to 0.001,
and is checked inclusively against both principal strains. The 0.01 ceiling
is a caller-selected domain bound, not measured validity at one percent strain.
Nonfinite strain/angle, out-of-domain strain and nonrepresentable stress/energy
reject with `MaterialError.invalidTrial`. Constructor/frame errors have distinct
`invalidParameters`/`invalidFrame` cases. Zero/underflow values retain the original
binary64 arithmetic; this is not an exact-real arithmetic guarantee.

Trial evaluation owns no mutable history. A thrown result cannot replace a
caller-held accepted result. Dissipation is identically zero. No plasticity,
damage, thermal/rate response, glue, laminate assembler or panel solver is included.

## Provenance and verification

[Source identity](orthotropic-plane-stress-source.json) records the original kernel
commit and exact file hashes. P1 input, constitutive, bending and rotated oracle
bytes are retained unchanged under `Tests/SolidMechanicsTests/Fixtures`; the Python
closed-form rotated-Q reference remains independent of the tensor-transform kernel.
The original P1 material harness travels as a SwiftPM test: 1,620 checks cover
21 loading/unloading/compression/shear samples, 20 off-axis oracle samples,
energy gradients and tangent symmetry, rigid rotations, isotropic/auxetic limits,
parameter/frame/domain/overflow rejection, immutable accepted results and signed
shear endpoints. Its 122 through-ply stress/energy integrations are verification
code only and introduce no laminate API. Edgerton retains its assembly and static
fixture acceptance, ply-frame assignment, reactions/work and both layups.

`Scripts/check-orthotropic-consumer.sh` builds an isolated committed Git consumer
in release mode, optionally pinned to an exact tag. It checks the public product
against all 41 independent constitutive/off-axis samples, exact original public-call
strain/stress/world-stress/energy/dissipation bit parity, plus world-frame and
typed rejection checks, and excludes Metal/UI/Accelerate framework linkage.
`Scripts/check.sh` includes this consumer and the full package suite. Publication
requires the existing exact-tag physical-host release workflow. No release or
Edgerton adoption is implied by this candidate.

## Adoption gate

After a reviewed, fully verified published release exists, Edgerton can replace
its original type with a forwarding typealias to this public law and pin the exact
version. It must verify parameter/frame/error/result parity against the frozen
original, then rerun P1 constitutive, assembled/static fixtures without changing
inputs or acceptance bounds. Edgerton's exhaustive kernel ownership then moves to
Core; ordinary adapter checks can remain small. This candidate makes no test-speed,
impact, general panel or empirical plywood accuracy claim.

## Candidate acceptance checkpoint

The [verification receipt](orthotropic-plane-stress-verification.json) records
294 passing physical-mini Swift tests, including the transferred1,620checks,
and the passing optimized41sample public/original parity consumer. Full
`Scripts/check.sh` nevertheless fails the unchanged inherited Euler identity
checker on current main; that failure is retained. [The adoption handoff](ORTHOTROPIC_ADOPTION_GATE.md)
identifies the separate Core repair, release and application gates. No tag or
Edgerton pin was changed by this checkpoint.
