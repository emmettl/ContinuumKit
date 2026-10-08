# Closed box queries

This candidate adds `Box.intersection` to `SceneModel`, with no new product or renderer
dependency. It consolidates the slab intersection used by BombCAD's source picking
and one-way fragment segment tests. Application object IDs, selection priority,
opening subtraction and impact interpretation remain with BombCAD.

## Contract

Bounds and positions are Float metres in the same frame, z up. The query returns the
closed interval of parameters `t` for which `origin + t * direction` is in the box,
clipped to a caller-supplied interval (default `0...infinity`). A normalized direction
makes `t` a distance in metres; `end - start` with `0...1` makes it a segment fraction.
Interior starts return the supplied lower parameter. A face, edge or corner touch is
an intersection, including a zero-length returned interval. This closed convention
differs deliberately from `Box.contains`, whose maximum faces are excluded.

Direction need not be normalized. `parallelTolerance` is a nonnegative threshold in
direction-component units; components at or below it are treated as zero. It does not
inflate the box. Exact parallelism is the default. The caller chooses whether a
direction threshold is appropriate and must scale it when changing parameterization.
There is no scene-owned or implicit metre tolerance.

Invalid finite geometry, zero direction, nonpositive dimensions, nonfinite origin or
direction, nonfinite lower clipping parameter and invalid tolerance return nil.
Arithmetic is Float. An unrepresentable entry also returns nil; an exit beyond Float's
range can return positive infinity. This is a bounded geometry operation rather than
an exact-predicate or large-coordinate robust geometry library. No physical model,
contact response, time integration, BVH or visibility/exposure model is introduced.

## Provenance and compatibility

Source repository: `https://github.com/emmettl/bombcad`, commit
`280b3a22d5f4389566b3b70a432341c593fabcab` (MIT).

| Original path | SHA-256 |
| --- | --- |
| `Sources/BlastCore/ScenePicking.swift` | `f721df16a1d7918da128dcd65023ea10269d5fb29b20686d3acc251e19371aac` |
| `Sources/BlastCore/FragmentCloud.swift` | `731401af2d2002e99c9d494dd774c665eeb4727709ca0fb50cccb451fc0b58ae` |

The shared implementation is adapted, not byte-identical: it exposes both clipped
endpoints, unifies input checks, and makes parallel classification explicit. BombCAD's
adoption candidate retains the original picking and segment thresholds (strictly below
`1e-8` and `1e-12`, respectively), and handles stationary fragment segments in its own
adapter. Historical selection policy and impact naming remain application-owned.

## Independent evidence

Seven CPU tests verify all three coordinate axes in both directions against known
entry/exit values, segment clipping, interior starts, backward line intersections,
closed boundary and single-corner contact, parallel misses, tolerance classification,
invalid/extreme input, translation and direction scaling. Four hundred oblique
segments are checked against an independent oracle that intersects the six face
planes and retains points lying on the faces. These checks import `SceneModel` without
an application or renderer. No spatial discretization or time integration is involved.

The clean fetched Git consumer also checks a segment's entry/exit and a closed-edge
ray using the public product. Run `Scripts/check.sh` from the committed candidate.
BombCAD retains source picking, fragment, multiple-object and persistence integration
checks. Candidate and release checks remain separate; application adoption should pin
a tested release after it is explicitly authorized.
