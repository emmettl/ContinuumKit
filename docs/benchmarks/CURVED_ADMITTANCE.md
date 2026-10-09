# Absorbing wall area calibration and isolated wall flow

This bounded audit separates physical wall admittance from a numerical substep. The
geometry is an aligned square prism or a circular cylinder, centred at (0.125,0.125) m,
half-width/radius R=0.09375 m and height H=0.125 m inside a 0.25×0.25×0.125 m grid.
Side walls have real normalized impedance ξ=3; end caps are rigid. Density is 1.25 kg/m³,
sound speed 320 m/s and prescribed pressure load 1 Pa. Inactive pressure is a deliberate
100 Pa sentinel. This is a pressure-load calibration, not a compatible initial-boundary
condition or full continuum transient wave solution.

For outward wall-normal velocity u_n=p/(ρcξ), prescribed instantaneous wall power is
p² A/(ρcξ). Physical side area is 8RH for the box and 2πRH for the cylinder.
The local-reaction pressure/normal-velocity boundary is described in
[Okuzono and Yoshida (2022), §2.1](https://www.frontiersin.org/journals/built-environment/articles/10.3389/fbuil.2022.1006365/full).
The power/area calibration here is independently derived; this paper supplies the
boundary convention, not validation of our solver or cylinder.

At 16/32/64 × same × half, independent cell-centre shape membership determines masks
and open/closed connectivity. The effective side area is recovered from actual wall
coefficients β: sum(2β V ξ/(c dt_layout)). Full unweighted Cartesian stair faces around
this cylinder have perimeter 8R at every declared grid, versus 2πR physically, giving
4/π−1 ≈27.324% excess admittance under a prescribed uniform pressure load. Refining the
mask alone cannot remove this factor. The aligned box is a positive physical control.
The physical area tolerance is 0.5%; any failure is explicitly `physicalStatus=gap` and
is never a physical conformance pass. The report does not predict a reverberation-time
or arbitrary free-wave error from that area bias.

A separate test binds the actual source's isolated first wall-flow update. Initial
active pressure is uniform and all stored velocities zero, so the first velocity update
has zero interior gradient. The local post-velocity wall substep has dp/dt=−λp, where
λ=2 sum(β)/dt, with independent exact exponential p(dt)=p(0) exp(−λdt). Measured rate
−log(p1/p0)/dt tests the trapezoidal substep's second-order error at fixed 32×32×16 and
CFL 0.8/0.4/0.2. Required orders are 1.7–2.3, finest relative L2/max rate errors <0.2%,
energy-plus-midpoint-wall-work residual <1e−5 of initial energy, relative work mismatch
<5e−5, and zero velocities, initial pressure/padding errors <1e−6. This is not a coupled
transient temporal convergence claim; the existing wave suites cover their own contracts.

The history retains both unmodified layout faces/layout clock and linearly rescaled
faces/benchmark clock. Actual material impedance and every active face are audited;
interiors are −1, caps zero, and side weights remain nonnegative and at most one.
Weights can change in a future geometry-aware fix; the audit classifies physical pass/gap
from observed area rather than requiring the old defect to persist. An analytic π/4
uniform weighting control demonstrates the area gate, but is not a proposed general
solver correction or a transient accuracy claim. Correcting geometry must preserve
spatially varying loads, material identity, energy and the existing rigid/box suites.

Ten tests verify independent area/power goldens, staircase bias, the box control,
exponential decay, an analytic weighted-area control, separate status semantics,
false caps/clocks/masks, missing fields, padding corruption and malformed cases.
The clean Git consumer exercises the physical law and preserves the explicit gap.
Run `bash Scripts/check-admittance.sh [output]`; verify complete plain or lossless-gzip
reports with `python3 Scripts/verify-admittance-output.py output --reference` (omit the
flag for source audits; `--unsupported` requires capability records). CI may pass report
integrity and numerical substep checks while the physical geometry gate remains `gap`.

Production solvers, prior benchmark gates, measured fixtures and release tags are
unchanged. Full app-derived histories/layouts are retained privately in Edgerton.
Geometry-aware boundary admittance and coupled absorbing-cylinder continuum convergence
remain gates before extracting that implementation into a shared production model.
