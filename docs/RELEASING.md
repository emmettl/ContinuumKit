# Releases

All products share the repository's semantic version. Begin with prerelease tags
such as `0.1.0-alpha.1`; tags have no `v` prefix. Treat published tags as immutable.
The first CAD foundations prerelease is `0.1.0-alpha.1`. Its scope is geometry, scene,
import and document helpers. `0.1.0-alpha.2` adds response interchange, with twelve
independent tests and the expanded consumer. Neither release is a validated numerical
physics model library. `0.1.0-alpha.3` adds the uniform adiabatic reservoir, versioned
benchmark reports and fourteen independent numerical/conformance tests. It passed
the physical Mac mini exact-tag release checks, including all 41 tests and the
clean version-pinned consumer. Its scope is numerical verification of the declared
idealized contracts, not empirical validation of application scenes.

`0.1.0-alpha.4` adds the closed-box ray/segment query to `SceneModel`, with seven
independent geometry tests and a fetched public consumer. It also includes the analytic
acoustic reference/conformance APIs introduced after alpha.3; it extracts no acoustic
solver. The release points to
reviewed commit `d3c7367ba43940155f7e33da738e6f5058723fd5`. Its
[exact-tag workflow](https://github.com/emmettl/ContinuumKit/actions/runs/37854603915)
passed all 57 tests, actual Metal work and the version-pinned optimized consumer on
the physical Mac mini before [publication](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.4).

`0.1.0-alpha.5` improves project container and manifest diagnostics and adds the independent
acoustic reference/conformance contracts merged since alpha.4: mixed boundaries, dissipative
time refinement, three-dimensional modes, oblique impedance, masked and curved domains,
admittance and causal tilted pulses. Geometry extrusion audits and the linear-wave extraction
design/provenance checkpoint are included; no shared wave-update solver is extracted.
The app-linked CAD foundations retain alpha.4's source except DocumentKit.
The release points to reviewed commit `7d5ef9d0ca7b415d3fef86b5400017bb43111a3c`.
Its [exact-tag workflow](https://github.com/emmettl/ContinuumKit/actions/runs/37974874568)
passed 141 tests, actual Metal compute and the version-pinned optimized consumer on the
physical Mac mini before [publication](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.5).
Reference conformance does not establish empirical validation of application scenes.

## Candidate verification

Commit the candidate and run `bash Scripts/check.sh`. Review the public contract,
verification evidence, extraction provenance and consumer compatibility. When a
release is explicitly authorized, create and push its annotated semantic-version
tag pointing to the reviewed commit.

Run the manual **Release** GitHub Actions workflow with that existing tag. It:

1. Validates the version format and checks out exactly that tag.
2. Runs the Metal smoke check on the physical Mac mini, then builds and verifies a
   clean consumer using an exact version requirement.
3. Creates a GitHub release only after the checks pass, marking prereleases.

The workflow does not invent a version, create a tag, or publish on an ordinary
push/merge. SwiftPM consumes tagged Git source; no package registry or binary
artifact is required. The workflow refuses to overwrite an existing GitHub release.

Applications update their exact dependency and committed `Package.resolved`, then
run their integration checks. Keep previous releases available for reproducibility.

## Source-free wave release preparation

The next wave prerelease is bounded to the checked source-free masked CPU product
and explicit resident Metal product. Their independent Core suites, exact pinned
source comparisons and actual original/shared RoomCAD geometry/wall-work benchmark
consumers must pass before tagging. It does not claim production source/receiver
integration or measured acoustic validation; those are separate application gates.

All three fetched release consumers must use the exact version requirement, including
the CPU-only framework-link guard and the actual-device wave resource/multiple-batch
consumer. Check scripts reject a tag that does not identify their candidate HEAD.
Existing tags remain immutable. A new prerelease is published only through the
successful exact-tag workflow; release authorization comes from the active model-gap
instruction to commit, push and release as needed.

The [source-free readiness audit](extraction/SHARED_WAVE_READINESS.md) now records
all 96 exact actual RoomCAD pairs and their unchanged original reference identities.
`0.1.0-alpha.6` is the next candidate, adding LinearAcoustics/LinearAcousticsMetal;
publication still requires its exact-tag workflow. Production app integration remains
separate and is not claimed by a source-free model release.

## Published source-free wave prerelease

`0.1.0-alpha.6` is published from reviewed commit
`56210bf1aae4046224597128f0a286e55585a521`. Its [exact-tag workflow](https://github.com/emmettl/ContinuumKit/actions/runs/38003236841)
passed all 169 tests, actual Metal work, unchanged references and three optimized
consumers resolving the exact semantic version before publication. The CPU consumer
retains its no-Metal/UI linkage guard; the GPU consumer loads packaged kernels and
checks native fields/clocks over multiple command batches. [Publication proof](extraction/alpha6-release-verification.json)
records scope/identities. Existing tags are unchanged.

The release follows all 96 complete exact actual RoomCAD original/shared records
and original frozen reference bounds. It releases independently useful source-free
steppers, not production forcing/receiver integration or empirical acoustic accuracy.

## Published prepared pressure-forcing prerelease

`0.1.0-alpha.7` is published from reviewed commit
`5ee7c90161d1a002d0f5e7cca41cc37cbcd4bbc6`. Its
[exact-tag release run](https://github.com/emmettl/ContinuumKit/actions/runs/38009833474)
passed 189 tests and all three optimized consumers resolving the exact semantic
version, including packaged resident injection/command batches and CPU-only linkage.
[Publication proof](extraction/alpha7-release-verification.json) records identities.
Dual-host original-source gates retain 4,176 complete captures with zero runtime
Float32 mismatches. Receiver/application integration remains separate, and the
first-order damped forcing limit is unchanged and explicit. Existing tags are immutable.
