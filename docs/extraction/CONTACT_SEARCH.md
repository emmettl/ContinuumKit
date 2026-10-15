# Deterministic contact search — published in 0.1.0-alpha.25

`ContactSearch` (CPU) and `ContactSearchMetal` (GPU) carry the broad phase of BombCAD's
structure contact.

- Points fall into a cell table that wraps periodically.
- Each entry keeps its lowest-numbered points in ascending order, whatever the thread timing.
- Each point finds the others within reach in the 27 cells around it.
- Searches may skip pairs of points that have not moved far enough to touch.

Pair forces, which pairs to exclude (BombCAD's lattice neighbours), buried or retired points,
rubble and every other contact policy stay in the applications. Edgerton is the intended second
consumer: Codex reviews and owns its adoption. Neither application has adopted this candidate,
and no release includes it.

## Source and attribution

[`contact-search-source.json`](contact-search-source.json) pins BombCAD
`659091b336eb750e07286419558d067180c3b27a` (12 October 2026). The source is
`Sources/BlastCore/Shaders/Structure.metal`, in three blocks:

- the slot constants;
- the cell, entry, clearing, movement and insertion functions;
- `contactForces`.

`Fixtures/ContactSearchSource/BombCADStructureContact.metal` freezes those blocks byte for byte;
their hashes and the whole file's are recorded. The pair skip came in at BombCAD `afa5c84`. Both
repositories are MIT-licensed by Louis Emmett.

The extraction is an adaptation, not a rename. BombCAD's uniforms (grid origin, element size,
table period, stamp) become arguments, and its node arrays become a point buffer and flags.
`python3 Scripts/verify-contact-search-source.py` checks:

- the frozen hashes;
- that each of thirteen arithmetic statements of the original appears in the package with only
  those substitutions: the cell, the entry, clearing, the insertion chain, listing, the visited
  entries, the movement mark and the own-cell check.

## Contract

- **Cells and entries.**
  - A cell is `floor((p − origin) / cellSize)`, evaluated in Float.
  - The table has `period` cells per axis: powers of two, at most 2²⁸ entries.
  - Entries are numbered `x + px·(y + py·z)` of the wrapped cell.
  - A point within a rounding error of a cell face may land in a different cell on the CPU and
    the GPU. The table comparisons below keep test points clear of faces.
- **Building a table.** Each substep takes a new stamp (nonzero, never `0xFFFFFFFF`) and two
  passes over the active points.
  1. Each active point stamps its entry and empties its eight slots.
  2. Each active point offers its index through a chain of atomic minima.
  The entry then holds its eight lowest indices in ascending order, and `emptySlot` after them.
  Entries not stamped this substep hold nothing, so the table is never cleared. A point flagged
  `moved` stamps its entry's movement mark.
- **Listing.** A point is listed when its own entry kept it. One that a crowded entry dropped
  finds nothing and is found by no one, so every pair is seen from both sides or neither.
- **Search.** A listed active point visits the 27 cells around its own (z outermost, then y, then
  x). Within each it takes the points of the visited cell's entry, in slot order, that lie in
  that very cell and are nearer than `reach`, which is at most `cellSize`. Points in cells a
  whole period away share the entry but are not taken. Coincident points are candidates;
  degenerate geometry is the caller's to handle.
- **The still-pair skip.** A point not flagged `moved` visits only entries whose movement mark
  carries this substep's stamp.
  - **Premise:** every two points the search must consider began at least
    `minimumSeparation > reach` apart, and every point that has moved from its reference
    position by at least `stillThreshold = margin · (minimumSeparation − reach) / 2` is flagged
    `moved`.
  - **Result:** two still points are then more than `reach` apart, so skipping them drops only
    pairs that are out of reach, and every list is unchanged.
  - **Margin:** `margin` below 1 covers round-off. BombCAD uses 0.45 of an element (minimum
    separation 2h, reach h, margin 0.9) for solids, and margin 0.8 over shells'
    neighbourDistance.
  - **Exclusions:** pairs closer in reference must be excluded by the caller's own rule, as
    BombCAD excludes lattice neighbours.

`MetalContactSearch` keeps the heads, slots and movement marks resident and encodes the two
building passes and a candidate pass on the caller's serial encoder. `functionSource()` returns
the shared Metal functions, so an application can compile them ahead of its own kernels and
keep its pair forces there, as BombCAD does. `snapshot()` reads the table back for comparison,
and `search` is a synchronous convenience.

## Verification

**CPU (nine tests).**

- The cell and entry formulas, including negative cells and wrapping.
- Invalid layouts, points, stamps, counts and reaches are rejected.
- An independent brute-force search, with no table: 800 points, a cluster that crowds entries
  past eight slots, and one point in eleven inactive. Every list must equal it exactly, in
  search order.
- A crowded entry keeps its eight lowest; the rest see nothing.
- Aliased cells a period apart.
- The skip on 1,000 points of a lattice at twice the reach, some displaced beyond the
  threshold: identical lists with and without the skip, and no still pair within reach.
- A negative control: two points marked still after moving 0.6 of the reach towards each other
  lose their pair, so the premise is necessary.
- The threshold's validation.

**Device (six tests; a missing device fails).**

- Table and candidate lists equal the CPU reference bit for bit, with and without the skip.
- Repeated builds, thread groups of 1 to 256 and a new instance give the same bits.
- Entries from an earlier build hold nothing in the next.
- The skip and its negative control, on the device.
- A kernel of the test's own, compiled with `functionSource()`, computes the same entries for
  2,000 points.
- Capacity, reach and candidate-overflow behaviour.

**Consumer.** `Scripts/check-contact-search-consumer.sh` fetches the committed source and builds
two optimized consumers:

- a CPU-only one, whose binary must not link Metal, AppKit, SwiftUI or Accelerate;
- a device one: 4,000 points against the CPU reference, plus the shared functions' presence.

Both run in `Scripts/check.sh` with the source verification.

This is numerical verification of a search. It says nothing about contact forces or physical
contact accuracy.

## Release and adoption

- **Published** in [0.1.0-alpha.25](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.25)
  ([publication proof](alpha25-release-verification.json)).
- **BombCAD** adopted it at `4d58022` (on its main as `a361ae9`).
  - It compiles `functionSource()` into its shader library.
  - Its structure and shell contact now call `cksCell`, `cksEntry`, `cksClearEntry`,
    `cksInsert`, `cksListed` and `cksSearches`.
  - All seven `blastbench digest` cases and the contact-profile node hashes are bit-identical
    to the same tree without the shared functions.

## Remaining gates

- **Edgerton:** its GPU node-sphere hash is separate. Adopting this one is Codex's decision and
  work.
- **Out of scope:** a CPU-parallel build, other slot counts and sort-based broad phases.
