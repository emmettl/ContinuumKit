# Double closed-box queries

`SceneModel.BoxQuery.intersection` accepts explicit `SIMD3<Double>` bounds,
origin and direction, returning the clipped closed parameter interval. It introduces
no persisted geometry type and never converts to Float. Metres, a common coordinate
frame and z up follow SceneModel conventions. Direction need not be normalized:
unit directions give distances, segment directions with `0...1` give fractions.

The algorithm adapts the existing released Float slab query without changing
`Box`, its Codable representation, half-open containment or Float query bytes.
Double precision is needed by RoomCAD's thin fitted zones and mesh geometry.
The initial application consumer is fitted-zone traversal; mesh/BVH replacement
is deliberately separate because planar node bounds and performance need their
own contract. BombCAD's existing Float consumers need no migration.

## Supported assumptions

Bounds and origin/direction must be finite, every dimension positive, and direction
nonzero. The lower clipping endpoint must be finite, the upper may be infinite.
Parallel classification uses `abs(component) <= parallelTolerance`, default zero;
the finite nonnegative tolerance is in direction units and never expands bounds.
Face/edge/corner contacts count, even when the returned interval has zero length.
Applications retain stationary-point and positive-path/material policy.

Arithmetic, including coordinate subtraction, is binary64. Entry overflow returns
nil; exit overflow may return infinity. No exact predicate, conservative rounding,
large-coordinate overflow correction, mesh acceptance, BVH or physical model is
promised. Precision already lost in input cannot be recovered.

## Provenance and independent verification

The Float algorithm is the BombCAD-origin query documented in [BOX_QUERIES.md](BOX_QUERIES.md).
The candidate starts at ContinuumKit `37d6550` and retains original MIT attribution.
RoomCAD's protected application source is `7d73614`,
`Sources/AcousticCore/FittingZone.swift`, SHA-256
`16a7ba8f2610b707bfa24fbbeec914ad34b2910fbdfb8dbdf08390982db219f6`.
It uses Double slab clipping but rejects zero-length traversal. Its stationary-point
convention stays in the application adapter.

Nine independent Core tests cover analytic axial entries/exits, clipping, backward
lines, closed touches, tolerance, invalid/extreme inputs and transformation laws.
Four hundred oblique segments compare to a six-face-plane oracle rather than a
second slab implementation. Additional thin bounds at 2^30 and 1e-100 distinguish
Double results from Float conversion. The committed fetched consumer exercises
Double-only thin bounds and a closed corner touch using the public product.
RoomCAD separately compares complete endpoint bit patterns against the protected
original and retains existing direct/image-source/ray attenuation checks.

Candidate package, fetched-consumer, actual-Metal and application acceptance must
pass before publication/adoption; numerical query verification does not establish
empirical acoustic accuracy.

## Local adoption checkpoint

RoomCAD's 13,500 valid ray/segment/stationary cases match the protected original's
complete endpoint bits. Its two adoption tests and full `make check` pass on the
M4 Max with the candidate supplied through a temporary SwiftPM edit; this is
pre-publication integration evidence, not an exact-version acceptance claim.

The public Double function is inlinable across the package boundary. A standalone
optimized microbenchmark (2 million varying bounded queries, alternating old/new,
four rounds) retained identical aggregate lengths. Checked queries took
14–24 ms versus 6–11 ms for the unchecked original on the M4 Max. Extra validation
is measurable; this extraction claims reuse/precision and no end-to-end speedup.
Existing Float callers and mesh acceleration are unchanged. Exact-tag application
checks remain required after publication.

## Accepted two-host candidate

The M4 Max and [physical M4 mini](https://github.com/emmettl/ContinuumKit/actions/runs/38537085474)
pass the complete committed-candidate `Scripts/check.sh`: 303 package tests,
all fetched optimized consumers, actual Metal and every inherited numerical and
geometry reference gate. [Scope and source identities](double-box-query-verification.json)
bind these results to `f2c8a5a`. This acceptance record changes documentation only;
Sources/Tests/Fixtures/Scripts/Package bytes remain identical. Alpha.23 publication
still requires the separate exact-tag release workflow.

Published: [alpha.23](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.23),
after both hosts pass complete exact-tag verification. [Publication proof](alpha23-release-verification.json)
retains the immutable tag, commit and release workflow. RoomCAD adoption remains
separately source-bound and verified.
