# Cloud report: stale documentation

Branch `claude/project-thread-h86kna`, 18 October 2026. The change touches documentation only. No Swift, Metal, Python, fixture or package file was changed.

## What changed

- **`ROADMAP.md`**: the roadmap's last release entry was alpha.19. A new section, "Published since alpha.19", lists alpha.20 to alpha.28, what each published, and a link to each publication proof. It also records:
  - that alpha.27 was never published;
  - where adoption stands for BombCAD, RoomCAD and Edgerton;
  - which work is still open.

  One line notes that the earlier "Double spatial candidate" was published in alpha.23.
- **`README.md`**: the Verification section said the gate covers "fourteen" libraries and "eleven" consumers. `Package.swift` declares sixteen library products, and `Scripts/check.sh` runs seventeen consumer scripts (lines 21 to 37). The section now gives those counts and names every consumer.
- **`docs/extraction/CONTACT_SEARCH.md`**: the doc said no release includes contact search and no application has adopted it. It now says alpha.25 published it, BombCAD adopted it, and Edgerton has not adopted it yet.

## Sources for the new text

- Release contents and dates come from `docs/RELEASING.md` and `docs/extraction/alpha*-release-verification.json`.
- Alpha.21 has neither a proof nor a section in `RELEASING.md`, so its contents come from its GitHub release notes (ContinuumKit #76 and #77).
- BombCAD's usage comes from its `Package.swift`, its imports and `docs/continuumkit-adoption.md`, all on BombCAD main at `40665a0`.

## Corrections to the earlier survey

The survey in the project's shared folder (`continuumkit-survey/SURVEY.md`) listed two items as open. Neither is open:

- **Weighted QR**: the weighted QR plan ended in `PivotedQR`, where the caller weights the rows before factoring.
- **BombCAD's QR adoption**: BombCAD's conserved gas reconstruction already uses `PivotedQR` through `FiniteVolumePressureFit`, so the adoption plan was carried out.

The roadmap does not list either as open.

## Checks

- Every relative link and anchor in the three edited files resolves. This was checked by running BombCAD's `Scripts/check-doc-links.py` on a copy of this tree; ContinuumKit has no link checker of its own.
- `git diff --check` is clean.
- No Python was touched, so no Python tests apply.
- Nothing was built: Swift and Metal cannot run on this Linux box.

## Limitations

- RoomCAD and Edgerton were not read. What the roadmap says about their adoption comes from ContinuumKit's own records:
  - RoomCAD's adoption of the Double box query is recorded as a separate task, RoomCAD #39.
  - Edgerton's pin to alpha.22 is as recorded when alpha.24 was published.
- BombCAD's own stale docs, such as `Packages/SimulationKit/README.md`, are left to the separate docs audit.

The branch is ready for review.
