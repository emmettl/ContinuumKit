# Original weighted QR and reconstruction arithmetic audit

Run `bash Scripts/check-weighted-qr-audit.sh OUTPUT` from a clean committed
candidate. This compiles the complete original BombCAD pressure fitter at revision
`5f2e50dcef5a5adcde3d3c4cb811426e6de2fe6c` in isolation with `swiftc -O
-warnings-as-errors`. Only private QR visibility and observation hooks change;
reversing the recorded hooks restores byte-identical source. The complete fitter,
conserved reconstruction and existing tests are retained with Git blob/SHA-256
identities. These snapshots originate in BombCAD under its MIT licence.

The fixture records 272 direct three/nine-column cases and 176 actual weighted
stencil cases, including both quadratic and linear factors: 624 factor records.
Inputs, complete Q/R/permutation, solutions, every row prediction, sample centres,
covariances, volume averages, weights, weighted RHS, selected degree and three
queries per stencil retain native binary64 strings and bits. The cohort includes
common and column scales, exact and noisy data, reversed rows, exact and near rank
loss, short matrices, malformed/nonfinite RHS, translated irregular geometry,
volume-aware/point fits, extreme coordinate scales and rank fallback.

An independent exact-rational reference solves the least-squares problem over the
actual native matrix and RHS. Its exact Gram elimination does not perform floating
normal equations. It cannot recover distinctions lost before native conversion.
The verifier separately reconstructs geometry, polynomial volume averages,
distance weights, basis terms, mean differences, fallback and query values.

`2e-10 * max(1, abs(exact-native coefficient))` is a diagnostic classification
bound for this cohort. Q orthogonality and relative matrix reconstruction use a
separate `2e-10` diagnostic. Exceeding either is retained as a finding; a successful
audit does not certify the original solver. Source/input/completeness corruption
must reject, while coherent wrong coefficients must be classified as inaccurate.

The preliminary M4 Max cohort records 336 coefficient reference agreements,
20 finite coefficient inaccuracies, 48 unsafe squared-norm scale rejections,
152 relative-rank-policy rejections, 52 exact-native rank rejections, eight empty
matrix rejections, four nonfinite RHS rejections and four silently accepted RHS
dimension mismatches. Eight accepted factors exceed the orthogonality diagnostic;
none exceed the reconstruction diagnostic. Rejections imposed by the original
relative rank threshold are policy observations, not automatically solver bugs.
Counts include both factors of each actual stencil, whether selected or not.

The actual stencil guards neighbour/RHS counts; malformed RHS probes exercise the
private QR directly. Geometry and gas admissibility are separate contracts. This
audit does not exercise the full conserved gas update, limiter, EOS, conservation
under transport or empirical pressure accuracy. Factor reuse across multiple RHS
requires its own conformance cases in the future primitive.

Output includes protected source, exact compiled bindings, compiler/hardware and
producer identities, complete native JSON, every reference finding and corruption
receipts. Portable replay uses the archived verifier and controls in `scripts/`:
`python3 OUTPUT/scripts/verify-weighted-qr-audit.py OUTPUT`, then
`python3 OUTPUT/scripts/test-weighted-qr-audit-gate.py OUTPUT`.
The [bounded plan](../../docs/extraction/WEIGHTED_QR_PLAN.md) separates stabilization,
release and application adoption. No shared product or new tag is added here.
