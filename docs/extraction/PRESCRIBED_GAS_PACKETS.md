# Prescribed gas packet conservation candidate

`CompressibleFlow.PrescribedGasTransport` is an immutable CPU value API for one
simultaneous extensive-state update. It supplies no Euler/Riemann flux, geometry,
volume trajectory, timestep, moving body, viscosity or empirical blast model.
The caller owns the directed transfer graph, new volumes and external gas loads.

## Quantities and ownership

Cell volume is m³. Its eight amount lanes contain mass kg, momentum xyz kg m/s,
total energy J, then three reserved zero lanes. The explicit storage keeps source
operation order and a small adapter possible; reserved lanes are not passive species.
Cells, transfers and wall exchanges are Equatable and Sendable value types. Array
positions are cell identities; result order matches the input. There is no persistent
state, hidden device or mutation of an input array on success or failure.

A transfer removes the old donor packet times transferred volume / old donor volume
and adds it to the receiver. All donor states are frozen before updating. Aggregate
outgoing volume must not exceed that donor's old volume; incoming material cannot be
reused during this update. Zero transfers still require valid distinct indices.
The operator preserves extensive quantities apart from stated floating-point rounding
and dry cleanup. It does not enforce that supplied volume changes match the graph.

WallExchange impulse (N s) and gasWork (J) act ON the gas: they add momentum and total
energy respectively. They are supplied values, not computed pressure forces. This
work sign differs from application records for work delivered TO a wall.

## Construction and checked operation

Construction and velocity/pressure accessors retain source behavior and are unchecked
algebraic views. The primitive initializer converts supplied density, velocity,
pressure and gamma to an extensive packet; pressure queries require the caller's
finite gamma > 1 and do not store a material ratio. Using another ratio later changes
the interpreted pressure. Inputs that happen to create a valid extensive packet are
not retroactively checked against their primitive-construction history.

`advance` is the checked operation. Occupied cells need finite nonnegative volume,
finite amounts, strictly positive mass and finite positive pressure under the source's
1.4 caloric view (a positive-internal-energy test with a representability condition).
Reserved lanes must be zero. An old dry cell must have an empty packet. New volumes
must be finite and nonnegative. Transfers need valid distinct endpoints and finite
nonnegative volume; positive transfer requires a wet donor. Wall exchanges require
valid cells and finite impulses/work. A resulting nonphysical state rejects the entire
trial. No density/pressure floor or borrowing from new inflow is introduced.

Failures retain the source categories invalidState, invalidTransfer, excessiveOutflow
and occupiedDryCell. Extreme intermediate momentum/pressure overflow rejects through
invalidState. Constructor/view algebra is not a universal all-scale accuracy promise;
there is no new representability adaptation in this extraction.

## Dry-cell rounding contract

Before making a new cell dry, each of the first five residual amounts must satisfy
`abs(residual) <= 64 * Double.ulpOfOne * max(abs(oldAmount), 1e-300)`. Accepted residuals
are discarded and all eight storage lanes become positive zero. Supplied volume bits,
including negative zero, are retained. This is a bounded numerical cleanup; it does
not promise exact global conservation. Caller graph/transfer order may change rounding.

Independent tests bracket the exact energy-cleanup boundary for a known 64 J old
packet: 2^-40 J is accepted/discarded; the next representable value rejects. The
complete consumer includes below/at/above controls and signed-zero/empty systems.

## Verification and adoption gates

The [immutable source provenance](gas-packet-source.json) identifies BombCAD's original
104-line operator. Its unmodified original exists only in the fetched consumer fixture.
Fourteen independent tests cover explicit analytic mixing, external ledgers, Galilean
covariance, uniform wet/dry transition, prescribed volume views, supplied adiabatic work
refinement, exact cleanup, invalid inputs/graphs and transactional failure. These tests
do not call the copied original.

A public CPU-only Git consumer compares 1,620 ordinary cases across volume/density/
pressure/velocity/transfer-fraction/graph axes plus seventeen rejection/cleanup/empty
controls. It retains all original/shared input and output native values/bits, graph,
new-volume bits and loads. An independent exact-rational verifier checks every extensive
packet balance, derived physical view, graph identity and failure category, with explicit
rounding budgets. Corruption controls require rejection beyond original/shared equality.

Clean committed consumers, source identity, both-host complete reports, all previous
package/reference/actual Metal gates and exact-tag verification precede publication.
BombCAD adoption is a separate task, with complete remap/reservoir/moving-gas/piston and
app/package checks. No application source or pin changes in this candidate.
