# Deferred Edgerton adoption handoff

This extraction phase does not authorize an Edgerton dependency update, retirement
of its local implementations, changed defaults or new application numerical runs.
Core release verification and application adoption are separate gates. Schedule
adoption when the feature orchestrator has a bounded integration window.

## Public boundaries

| Existing Edgerton primitive | Core API | Application checks retained |
| --- | --- | --- |
| TargetVeneerCompression | SolidMechanics.VeneerCompression | Parameter/domain forwarding, immutable trial/history handling, P2 unloading/permanent-strain/work and affected P3 specimens |
| TargetVeneerDamage | SolidMechanics.VeneerDamage | Mode/characteristic-length assignment, both mesh/orientation coupons, fracture-work and wrong-length rejection; crack selection remains local |
| TargetNormalContactSolver | SolidMechanics.NormalContactFlow | Gap/velocity/effective-mass forwarding, impulse transfer, changing-normal/multi-contact/coupled trajectories; original precondition API retained |
| TargetKrylov | Numerics.RestartedGMRES | Operator/RHS preconditioning and units, input/allocation limits, error mapping, restarted solves and affected Newton/rollback/refinement fixtures |
| TargetIsotropicTet | SolidMechanics.IsotropicTetrahedron | All selected laws/parameters, ElementError mapping, array and inline Corners paths, exposed rest gradients and affected coupled forces/work/stress/tangent/dynamics |

GMRES preserves its frozen engine and iteration arithmetic but performs one extra
final operator evaluation with robust residual validation. The action must be
linear and deterministic, and the RHS must belong to the same preconditioned
system. Preserve the inherited fivefold residual acceptance; map source breakdown
and nonconvergence deliberately and account for the extra callback in diagnostics.
Do not promise byte-identical callback counters or accept underflow-driven false
convergence. Geometry/helper errors in the isotropic API are Core-owned; preserve
application error handling with a small explicit adapter if a typealias cannot.

## Bounded adoption procedure

1. Use a successfully published immutable Core tag, its full acceptance receipt and
   exact-tag workflow. No candidate branch or moving main reference is an app pin.
2. Compare current app kernels with the frozen source manifests. An intervening
   feature fix is not silently overwritten: reconcile it through a new bounded
   Core change/evidence version or defer that primitive's adoption.
3. Coordinate Package.swift/Package.resolved ownership. Pin the exact version and
   add only the needed existing products; adopt one bounded primitive at a time.
4. Replace production duplication with a thin alias/adapter. Keep protected
   originals in evidence/verification fixtures. Direct-source study runners must
   actually import/link the released module rather than bypass the pin locally.
5. Run small public forwarding, trial acceptance/rollback and error tests plus the
   affected application-owned specimens/trajectories. Preserve original inputs,
   fixture identities, independent references, bounds and recorded failures.
6. Record source/pin/commands/status and any intentional diagnostic change. Do not
   remove local study exports or regenerate original oracles through Core.

Core owns exhaustive primitive laws and independent numerical tests. Edgerton owns
assembly, geometry, supports, contact/fracture policy, time integration, recording,
rendering/export and coupled resource/mesh/time checks. Stable library tests need
not be rerun for every unrelated app edit; required app checks are not waived.
These extractions do not establish measured impact/material accuracy or a build
speedup. Broader steel, cohesive-interface and changing coupled-system proposals
remain separately bounded research decisions, not bundled adoption requirements.

Large raw verification fields and archives belong on StudioData. Git records small
source/reference checkpoints and acceptance receipts; release evidence may stage
on the verification host only until externally copied and hash-verified.
