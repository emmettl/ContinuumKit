# Releases

All products share the repository's semantic version. Begin with prerelease tags
such as `0.1.0-alpha.1`; tags have no `v` prefix. Treat published tags as immutable.
The CAD foundations candidate has no release tag yet. Its scope is geometry, scene,
import and document helpers; do not describe it as a validated numerical model library.

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
