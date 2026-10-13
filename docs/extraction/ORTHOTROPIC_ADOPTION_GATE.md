# P1 extraction release/adoption handoff

Library PR: https://github.com/emmettl/ContinuumKit/pull/80
Candidate code: 65f46fd0450f09b8948a0c8e3ae07add5a83e173
Base: b7c1e015c53e5fc17b03a8a746900424d640ea06

1. Core portability owner resolves PR79's existing Euler immutable-source checker
   incompatibility in a separately reviewed change. Preserve the original evidence
   and numerical guard; justify only the exact import portability transformation.
   This extraction task does not change that code or checker.
2. Rebase PR80 onto the reviewed fix, commit, and rerun complete Scripts/check.sh
   through normal physical-host CI. Original P1 SHA guard, all1,620law checks and
   optimized public consumer must pass; the consumer additionally checks exact
   original stress/strain/world stress/energy/dissipation bits on41frozen samples.
3. Review/merge the bounded extraction and publish a fresh immutable semantic tag
   using docs/RELEASING.md and successful exact-tag Release workflow. Current
   published alpha21 does not contain SolidMechanics; it is not an adoption pin.
4. Coordinate Edgerton shared Package.swift ownership; use an isolated adoption
   branch. Add the released SolidMechanics product to EdgertonCore and pin the
   actual exact version plus Package.resolved. Replace only the old elastic file
   with `import SolidMechanics` and `public typealias TargetOrthotropicPlaneStress
   = OrthotropicPlaneStress`; do not add another local implementation. Check
   existing nested Frame/Result/MaterialError and parameter/result compatibility.
5. Edgerton mechanics owner reruns public-call/frame/parameter/error/accepted-state
   forwarding and unchanged P1 constitutive, all6assembled layup/mesh cases and
   static/native surface fixtures. Preserve inputs, original references, bounds,
   prior failures and bulk SHA catalogue. Check release compilation as appropriate.
   Existing study runners compile source directly; explicitly link/import the
   released module in those bounded runners rather than silently bypass the pin.
6. Record source/release identity, commands, terminal statuses and acceptance.
   Core owns exhaustive constitutive tests; Edgerton keeps small adapter and coupled
   acceptance tests. Do not retire original evidence or claim empirical plywood,
   finite-strain, damage, laminate/panel or impact validation.

No Edgerton package, original kernel, laminate assembler or panel source was edited
by the library extraction. The frozen original copy in the consumer is a protected
parity reference, not a production implementation.
