# Exact scalar normal-contact flow

`SolidMechanics.NormalContactFlow` is Edgerton's `TargetNormalContactSolver`
with only its public enum renamed. App implementation, defaults, dependency pin
and integration tests remain unchanged; adoption is deliberately deferred.

This is exact frictionless unilateral quadratic penalty flow with fixed contact
direction and inverse effective mass. Gap is m, relative velocity m/s, stiffness
N/m, inverse effective mass kg⁻¹, duration s, returned impulse N s and energy J.
Positive gap is separated; negative velocity closes it. The solver resolves entry,
compressed harmonic evolution and release within a step. It is not a general 3D
collision solver, moving-normal contact, friction, restitution or multi-contact
integration policy. Application owners supply gradients and transfer impulses.

The original precondition API is retained, not converted to checked errors.
`advance` requires finite inputs, positive stiffness/inverse effective mass,
nonnegative duration and a finite positive derived frequency. Callers must bound
arithmetic so results are representable. `energy` is an arithmetic helper without
input validation. No arbitrary extreme-input robustness is claimed.

The immutable source/study SHA guard reconstructs the authored study and verifies
rename-only law parity. Core transfers the independent entry/release, maximum
compression, composition, no-attraction, compressed release, effective-mass impulse
and 45-state energy sweep. Additional analytic controls exercise a compressed
harmonic state, impulse composition, entry exactly at step end and zero duration.
A fetched optimized CPU-only consumer matches all four returned fields and energy
bits against frozen source on 135 states. These are numerical checks, not measured
collision validation.

No generated histories or large artifacts are committed. A separately verified
Core tag may later be adopted via a thin app alias and retained coupled contact
checks, preserving original evidence and app policy. Full package/release checks
wait for a resource window subordinate to orchestrated feature work.
