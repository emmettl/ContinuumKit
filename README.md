# ContinuumKit

Shared Swift foundations for RoomCAD, BombCAD and Edgerton: independently verifiable
models, numerical primitives, geometry, model loading and scene helpers.

This repository currently provides package and release scaffolding. No application
code or physics models have been extracted, and no physical validation is claimed.

## Build and verify

Swift 6.0 or later; macOS 15 or later. From a committed checkout:

```sh
bash Scripts/check.sh
```

Checks build the package and compile/run a separate consumer against its committed
Git revision. The working-tree build also catches uncommitted source errors. There
are no numerical tests yet; each extracted model must bring its own verification.

CI runs on the physical Mac mini and requires a successful Metal compute dispatch.
To include that runner check locally, use `CONTINUUMKIT_REQUIRE_METAL=1 bash Scripts/check.sh`.
See [CI operations](docs/CI.md).

## Package ownership

The bootstrap `ContinuumKit` product has no public API. Add focused products when
their implementation and independent tests are ready. Applications own their
documents, presets, interpretation, workflows, presentation and integration tests.

See the [staged roadmap](ROADMAP.md), [architecture](docs/ARCHITECTURE.md), [verification](docs/VERIFICATION.md),
[contributing](CONTRIBUTING.md) and [releases](docs/RELEASING.md).

The [extraction inventory](docs/INVENTORY.md) records candidates, source hashes,
fresh verification and a concrete first-move plan.

## Dependency policy

Consumers adopt exact semantic-version tags and commit `Package.resolved`. No
release exists yet. After a release, a dependency would look like:

```swift
.package(url: "https://github.com/emmettl/ContinuumKit.git", exact: "0.1.0-alpha.1")
```

Library products in this repository share one release version. Local development
may use a path dependency; application release checks must use the Git dependency.

MIT licensed. Extraction candidates retain their original attribution.
