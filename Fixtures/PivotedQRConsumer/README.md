# Optimized public PivotedQR consumer

Run `bash Scripts/check-pivoted-qr-consumer.sh [VERSION] [OUTPUT]` from a clean
committed candidate. A fresh Git clone and exact revision/version SwiftPM dependency
compile a release consumer of `Numerics`, with warnings as errors. Linkage checks
reject Metal, UI or Accelerate dependencies. Candidate/source/script/fixture hashes,
resolved dependency, hardware/toolchain/flags and complete protected source bindings
are retained beside full native outputs and every independent reference finding.

The 741-case cohort contains the 272 direct original QR cases and 352 actual
weighted-stencil factor inputs, plus 50 common-scale cases, 45 explicit diagonal
rank boundaries, eight extreme/64-column cases and fourteen error cases. Accepted
factors retain full thin Q, scaled R, permutation and condition estimate. They
solve primary, alternate and zero RHS using the same immutable factor, then repeat
the primary solve exactly. Native coefficients, every row prediction, scaled optimal
residual and RHS exponent are retained. Predictions are consumer diagnostics;
the library API does not expose unchecked prediction arithmetic.

Independent exact-rational input/rank/least-squares references verify complete
coverage, construction, supported failures, factors, condition diagnostics,
conditioning-dependent coefficients and residuals. The protected original audit
is rerun unchanged. Its inaccurate cases remain findings. Coherent corruption of
inputs, coefficients with every derived prediction, factors, errors, diagnostics,
RHS reuse and source/pin identities must fail the new conformance gate.

Allocation limits are exercised by focused package tests, including an actual
64-column matrix just above the element cap; the optimized consumer covers the
column cap with full inputs. Numerical checks establish the declared primitive
contract on this cohort. They do not validate gas reconstruction, limiting,
transport, measured pressure or acoustic/material interpretation.

[Contract and bounds](../../docs/extraction/PIVOTED_QR.md) distinguish conditioning
diagnostics and selected conformance criteria from general accuracy claims.
