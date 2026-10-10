# BombCAD pivoted QR adoption: bounded reconstruction contract

Checkpoint: 10 October 2026. Core alpha.19 is published after complete two-host
exact-tag gates. The fresh BombCAD remote checkpoint is
`b7d86c445d7aa40ed63bab1562e9c956b1c5c31e`, still consuming exact alpha.16.
Its pressure fit, conserved reconstruction and pressure-fit test blobs/SHA-256
match the protected [weighted QR audit](../../Fixtures/WeightedQRAudit/source.json).
The older local checkout is not the application migration baseline. Recheck remote
state and source identities before implementing this bounded adoption.

## Numerical change and ownership

Add the `Numerics` product and pin all shared products to exact alpha.19. Replace
only the private three/nine-column QR factors and solves in
`FiniteVolumePressureFit.Stencil` with checked `PivotedQR`; retain the existing
relative rank floor explicitly. Shared factor reuse must remain actual reuse of
the same geometry for all nonconstant conserved-component RHS. Do not create an
application-specific solver wrapper merely to reproduce inaccurate arithmetic.

The chosen matrix basis, covariance differences, h/d row multipliers, preserved
cell mean, quadratic/linear/constant fallback, polynomial/control evaluation and
sampled component bounds remain app-owned. `ConservedGasReconstruction` retains
its local velocity frame, original-data roundoff threshold, five component fits,
common factor, sampled density/internal-energy floors, 48-step bisection, 0.99
backoff and final lab-frame admissibility check. No global positivity or measured
pressure claim follows from this adoption.

Safe factorization can intentionally change coefficients and cutoff decisions
near degeneracy. Match unchanged geometry/policy, then judge numerical outcomes
against independent references. Preserve old findings rather than weakening the
original audit to force old/new parity. Explicitly explain how dimension/finite/
representation failures map to the existing application fallback contract.

## Complete required evidence

1. Capture the exact original/shared application sources, dependency pins, fixture
   identities, reversible observation bindings and both physical-host toolchains.
   Original arithmetic must come from protected production source, with only
   visibility and trace hooks adapted. Restore source bytes to verify that scope.
2. Retain every actual weighted row, distance multiplier, both factorizations,
   permutation, complete RHS/coefficient/prediction tree, chosen degree and
   control/volume values. Include ordinary translated/rotated volume-aware
   stencils, sparse/rank fallback, near dependence and extreme scales. Reuse the
   actual Stencil for distinct conserved components and repeat a solve after them.
3. Record lab/frame densities, chosen velocity, all five original-data scales and
   constant-component decisions, per-component polynomials/bounds, every control
   delta, component factor, density/internal floors, all 48 backoff decisions when
   used, selected factor and all final lab-frame states/EOS values. Include the
   existing quadratic densities, boosted pressure, positivity and invalid-input
   controls plus independent rank/conditioning probes. Sampled constraints remain
   distinct from global admissibility.
4. Independently reconstruct native geometry, mean-free volume averages,
   weighted least squares, frame transforms, constant thresholds, sampled bounds,
   backoff/admissibility and lab-frame EOS. Use exact/high-precision references
   where needed and declared scale/conditioning-dependent tolerances. Check
   volume-mean mass, momentum and energy; neither shared arithmetic agreement nor
   passing compile/tests alone proves this reconstruction contract.
5. Exercise affected `ExperimentalVolumePressureFitStudy`,
   `ExperimentalWallReflectionStudy`, `ConservedGroupedGasGeometry`,
   `MovingConnectedGasGroups` and limited/grouped moving reconstruction paths.
   Retain complete selected source histories and affected wall/flux/conservation
   references with frozen original pins. Time/space/reflection or moving-body
   policy changes require a separate task, not an incidental solver replacement.
6. Apply coherent corruption controls to inputs, source/pins, matrices/factors,
   RHS reuse, coefficients with all derived values, fallback, mean restoration,
   frame transforms, component threshold/factors, every backoff step and EOS.
   Retain all native evidence in a durable archive with full portable replay.
7. Pass appropriate fresh application/package checks on both Macs: lint, script
   tests, full build/tests, actual Metal and packaged application/signature checks.
   Existing current/frozen wall/packet/Euler benchmark contracts remain protected.
   Commit/push and merge only after this bounded numerical and application scope
   succeeds. The shared tag remains immutable; app adoption needs no new Core tag.

Relevant existing tests include `FiniteVolumePressureFitTests`,
`ConservedGasReconstructionTests`, `LimitedGroupedGasFluxTests`,
`LimitedMovingReconstructionTests`, `ConservedMovingGasTests`,
`MovingConnectedGasGroupsTests`, `MovingShockReflectionTests`,
`MovingPressureQuadratureTests` and `WallStencilSensitivityTests`. Read actual
current commands/fixtures when implementing; this outline does not invent CLI
flags or claim those tests cover all independent gates above.
