# Planar ideal-gas wall reference

CompressibleFlow.IdealGasWallRiemann is a Foundation-only stateless relation for one
uniform incident calorically perfect gas and a planar impermeable wall. Inputs are
density kg/m³, pressure Pa, signed normal velocity m/s relative to the wall, and
constant heat-capacity ratio gamma > 1. Positive velocity points toward the wall.
A moving-wall caller must subtract wall velocity before this call. The result owns
wall pressure Pa, an incident-state signal estimate m/s and an analytic vacuum flag.
It supplies no bulk Euler transport, viscosity, heat, nonuniform face reconstruction,
geometry, wall motion, integration or blast/material accuracy claim.

The normal-shock and isentropic-rarefaction relations are specified in the primary
[Clawpack Euler reference](https://www.clawpack.org/riemann_book/html/Euler.html).
The shock branch inverts its pressure/velocity relation, and retreating flow uses
the rarefaction invariant; sufficient retreat forms an analytic vacuum at the wall.
Tests independently parameterize normal-shock Mach states and verify mass, momentum,
energy and entropy, rarefaction sound/density relations, vacuum and acoustic limits.
The references are model-owned and require no application code.

signalSpeed preserves BombCAD's |normalVelocity| plus the upstream sound/shock metric.
It is not the exact wall-frame shock-front velocity, nor a universal certificate of
all downstream characteristic speeds for arbitrary gamma. Callers retain timestep,
wall travel, face normals and coupled work/impulse policy; the signal meaning must
not silently change during adoption.

Finite positive density/pressure, finite velocity and finite gamma > 1 are required.
Invalid input throws invalidState. The implementation retains ordinary-state source
operation order; extreme inputs with unrepresentable intermediates or non-vacuum
pressure underflow throw unrepresentableState instead of applying floors or inventing
physical vacuum. Near gamma = 1, only the rarefaction branch uses log1p/exp to avoid
rounding away the increment, with an independent near-isothermal limit check. These
are explicit numerical contract adaptations, not universal all-scale accuracy claims.

Original authored source is pinned to BombCAD 0b4943def5ec50064d1e44b9ab0ab249c2689b15,
with MIT attribution and complete source hash/Git blob in [provenance](ideal-gas-wall-source.json).
A protected original lives only in the standalone Git consumer fixture; independent
unit tests do not compare the implementation against that copy. Eleven tests cover
laws, scaling, invalid/overflow/underflow inputs, limits and signal semantics. The
optimized CPU-only Git consumer uses just the public CompressibleFlow product and
requires 360 complete ordinary-state pressure/signal/vacuum cases to match original
bits. Near-isothermal and underflow adaptations remain separately specified.

Before release, retain clean committed consumer source/pins, both-host complete
comparison reports, full package/reference checks and physical-mini actual Metal
regressions for the existing libraries. No application defaults or dependency pins
change in this candidate. BombCAD adoption follows an exact tested tag and separate
wall/flux/piston/full application gates. Existing acoustic and thermodynamic products
retain their own assumptions and previous tags.

## Verified candidate checkpoint

Clean 518b118e73cc847228a830758028edc49d467158 passes the full local package gate
and [physical mini](https://github.com/emmettl/ContinuumKit/actions/runs/38040549991):
233 tests, four optimized fetched consumers, CPU-only linkage, protected source identity
and all unchanged numerical/kernel/topology references. All 360 ordinary cases, complete
pressure/signal values/bits and vacuum branches remain exact across M4 Max/M4. The
independent complete-case gas-law and near-isothermal postconditions pass too. The
initial all-library consumer name collision and repaired run remain retained. Final
evidence checkpoint changes documentation only. [Aggregate proof](ideal-gas-wall-verification.json)
is public; full raw comparison reports, pins, logs and source provenance remain private
in Edgerton. Exact-tag verification precedes prerelease; application adoption is separate.

## Published prerelease

[0.1.0-alpha.13](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.13)
points to b6ff3ca28eb96bbac23ec15d93a13afda99b2be9. The
[exact-tag physical-mini release gate](https://github.com/emmettl/ContinuumKit/actions/runs/38041229593)
passed all 233 tests and four optimized fetched consumers before publication,
including the public CPU-only CompressibleFlow consumer at this precise tag.
[Publication provenance](ideal-gas-wall-release.json) records the tag object,
commit, publication time and retained log hash. The earlier candidate checkpoint
remains a historical record.

[BombCAD adoption](https://github.com/emmettl/bombcad/pull/22) proceeds separately,
with an exact dependency pin, application bridge/error-category tests, complete
pre/post piston states and wall-load intervals, public reflection histories and
full application/package checks. Publication alone does not certify that adoption.

## Completed application adoption

[BombCAD #22](https://github.com/emmettl/bombcad/pull/22) is merged with an exact
alpha.13 pin and its result/error-category bridge. All four complete original/shared
M4 Max/M4 reports are byte-identical: 360 wall states, twelve piston runs with 396
native frames/9,424 cells/2,898 accepted load intervals, eight public reflection
histories and the eight-case wall study. Independent accounting/completeness and
twelve rejection controls pass on both hosts. The separate full app check passes
872 Swift Testing cases, lint, script checks, build and mini packaging/signature.
Concrete/cloud main work is preserved with additional integrated build/focused checks;
complete raw logs/reports remain private in Edgerton PR #49.

The [application acceptance record](https://github.com/emmettl/bombcad/blob/8ec83cb524d1e745c0793106b0d78a7269131030/docs/wall-adoption-verification.json)
retains each measured clean source revision and integration scope. Publication and
adoption are complete for the declared wall relation; bulk gas transport and geometry
remain separate. The [next packet-conservation plan](GAS_PACKET_PLAN.md) bounds the
following candidate without changing model code.
