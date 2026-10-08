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
independent geometry tests and a fetched public consumer. The release points to
reviewed commit `d3c7367ba43940155f7e33da738e6f5058723fd5`. Its
[exact-tag workflow](https://github.com/emmettl/ContinuumKit/actions/runs/37854603915)
passed all 57 tests, actual Metal work and the version-pinned optimized consumer on
the physical Mac mini before [publication](https://github.com/emmettl/ContinuumKit/releases/tag/0.1.0-alpha.4).

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
