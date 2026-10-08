# Adiabatic reservoir conformance, version 1

## Model and independent reference

`Thermodynamics.AdiabaticReservoir` isolates Edgerton's chosen sealed-reservoir pressure
potential. With reference volume V0, internal energy U0 and constant gamma > 1:

- U(V) = U0 (V0/V)^(gamma-1).
- p(V) = (gamma-1) U(V)/V, so -dU/dV = p.
- Work out of the reservoir is W(a→b) = U(a)-U(b). Compression returns work to it.

Units are m³, J and Pa. The checked API requires finite positive volumes, finite
nonnegative energy and finite gamma > 1. Nonrepresentable positive states fail instead
of returning infinities or an underflowed false empty state. Zero charge stays empty.
Signed work uses log1p/expm1 to avoid small-change subtractive cancellation.

The energy/pressure expressions retain the source evaluation order; see
[provenance](../extraction/adiabatic-source.json). Input validation, parameterized gamma
and stable work are explicit new API behavior. The original coupled application is
unchanged. Its unchecked method's invalid-input behavior is not a promised core contract.

The independent pressure-first oracle uses p V^gamma = p0 V0^gamma, U = pV/(gamma-1)
and the integrated pressure-work expression. The perfect-gas, reversible adiabatic
assumptions and first-law work sign follow [MIT's thermodynamics notes](https://web.mit.edu/16.unified/www/SPRING/thermodynamics/notes/node17.html).
Integer-exponent golden states, a five-thirds/eightfold reference, pressure/energy
finite-difference refinement, independent Simpson integration, tiny work and explicit
failure/empty cases check the model beyond agreement with the old implementation.

## Matched cases and resolution

The standard cases use V0 = 0.001 m³, U0 = 12 J and gamma = 1.4:

1. Linear expansion to 2 V0.
2. Linear compression to 0.9 V0.
3. Linear expansion to 2 V0, then return to V0.

Each leg occupies the same clock fraction. The 1 s clock labels prescribed-volume
samples; it makes no finite-speed piston or acoustic claim. Refinement uses 16, 32,
64 and 128 intervals, aligned to leg boundaries. Complete-history maxima prevent a
closed cycle's endpoint cancellation from disguising pressure/work error.

Uniform pressure, fixed mass, no heat/mass exchange, constant gamma and no net momentum
are required. No spatial discretization is claimed for this zero-dimensional case.
There is no waveform, shock, wall Riemann, vent, contact or gel-material conformance claim.

## Implementations and independent accuracy

- The core law and Edgerton's source method evaluate endpoint states algebraically.
  Their adapter's trapezoidal p dV work is the quantity refined; its expected order is
  1.8–2.2. The state formula is not assigned a fictitious time-integration order.
- BombCAD's actual FractionalGasTransport source receives frozen-old-pressure wall work
  in one cell, no face transfers and zero net wall impulse. This reproduces the bounded
  pressure-work reference's assumptions, with density 1.225 kg/m³ and explicit mass.
  It supports gamma 1.4; pressure error must refine at order 0.85–1.15.

At the finest interval count, pressure, energy and work errors must be below 1%;
normalized energy-budget residual below 1e-3; tracked mass change below 1e-12. Values
are complete-history maxima. Energy/work errors and budgets normalize by U0; pressure
error is relative to the analytic pressure at each sample. Budget accounting alone
cannot pass accuracy: the suite includes a balanced but wrong history.

Source adapters build the current production calculation through an immutable Git
consumer of BenchmarkSupport. Edgerton's scalar method and actual gamma declaration
are copied verbatim into a generated minimal field wrapper; no old model copy is kept
in the fixture. This audits the constitutive calculation independently of its bore,
support/geometry/recording fixture. BombCAD's whole transport reference source is copied
at run time without numerical edits. It is not a test of the production Metal air solver.
Unsupported capabilities are recorded explicitly and make required-case conformance fail.

## Commands and reports

From a committed core checkout:

```sh
bash Scripts/check-adiabatic.sh /private/tmp/core-adiabatic
```

Each app repository has `Scripts/check-adiabatic.sh OUTPUT_DIRECTORY`. Its fixture pins
an immutable core revision; a future tagged adoption is a separate release decision.
Scripts compile optimized consumers without touching application studies or exports.

Reports contain case/schema versions, full parameters, SI column names, Float64 precision,
source revisions and SHA-256 hashes, dirty-tree status, hardware, OS, toolchain, interval
count and measured monotonic runtime. `results.json` records errors and budget residuals;
`conformance.json` records observed/expected order and finest bounds. CSVs retain complete
histories. Mass accounting distinguishes an implicit closed reservoir from tracked mass.
Concurrent runtime measurements are diagnostics rather than a performance gate.

```sh
python3 Scripts/compare-adiabatic.py --output /private/tmp/adiabatic-comparison \
  /private/tmp/core-adiabatic /private/tmp/edgerton-adiabatic /private/tmp/bombcad-adiabatic
```

Comparison rejects differing case definitions, incomplete series or failed/unsupported
required cases. Each error is measured against the independent analytic reference;
agreement between implementations is not the accuracy oracle. Numerical conformance
does not establish empirical gas, gel or blast accuracy.
