# Protected through-origin material arithmetic audit

The frozen MIT source is Edgerton's complete `Scripts/calibrate-material.py` at
`4956e002125c16aee805f624d13463a02368787f`; `source.json` binds its original Git
blob and SHA-256. Only the actual shear/bulk branches of `fit()` are evaluated.
The original relaxation search and CLI remain preserved in the snapshot.

The standalone standard-library Python capture executes the unedited source.
An observation binding freezes every term passed to its global `sum`, in the
original order, and delegates to the actual runtime `builtins.sum`. Every outcome
is also compared with an unobserved execution of the original function. Float
hex encodings preserve native finite, infinity, NaN and subnormal outcomes.

The 90 cases include ordinary/noisy/signed strains, count/rank/sign rejection,
ordered cancellation, common powers-of-two scaling, independent strain scaling,
intermediate overflow/underflow and unrepresentable coefficients or residuals.
Inputs are finite. Exact rational projections use the actual binary64 inputs,
with exact residuals, normal-equation orthogonality and mean squared residual.
The report distinguishes coefficient rounding from RMSE representation; it is a
source audit, not a passing material model or certified fitting error envelope.

Run `bash Scripts/check-through-origin-audit.sh OUTPUT` from a committed clean
candidate, or replay `python3 -B Scripts/through-origin-audit.py OUTPUT --verify`.
The verifier rejects altered source identity, native coefficients, inputs, exact
references and omitted cases. The hardware/Python producer receipt matters:
Python's builtin summation algorithm can differ between runtime versions.
