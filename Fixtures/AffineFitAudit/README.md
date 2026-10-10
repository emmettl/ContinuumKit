# Original affine fitting arithmetic audit

This is an audit, not a released fitting implementation. Run
`bash Scripts/check-affine-fit-audit.sh OUTPUT`. It reconstructs the exact original
RoomCAD index-coordinate and time-coordinate loops from protected complete source
snapshots and compiles them in isolation with `swiftc -O`. Only visibility and
bindings are adapted; summation/coordinate expressions remain verbatim. No acoustic
window selection, noise compensation, material calibration or GUI code is linked.

The 188 complete cases include 108 index fits (six counts, six integer offsets,
three profiles) and 80 time fits (four narrow counts plus two wider decay windows,
four starts, two rates). Inputs and all coefficient outputs retain full native
Double strings/bits, including nonfinite results. The reference computes exact
rational least squares over the actual binary64 coordinates and values; it does
not assume that an integer coordinate survived its Double conversion.

On the measured M4 Max, 108 cases agree with the declared diagnostic bound,
50 finite fits exceed it, 27 nondegenerate fits produce nonfinite coefficients,
and three cases have rank loss already in the native coordinates. The diagnostic
bound is `2e-10 * max(1, abs(exact-native slope))`; it classifies this chosen case
tree, not a general numerical error theorem. Findings are explicitly not passing
shared-model contracts. Typical wider windows are included alongside stress cases;
this audit alone does not prove an error in a real measured room workflow.

Complete source, fixture identity, inputs, raw results and exact rational references
remain reproducible. Changing summation algorithms, result/API representation,
finite/rank handling or application policy requires its separate verified task.
