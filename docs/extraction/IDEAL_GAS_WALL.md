# Planar ideal-gas wall reference candidate

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
