#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-consumer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

# Clone committed Git source into an isolated repository, without local object links.
# SwiftPM then fetches it as a Git dependency, not a path dependency or source alias.
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
if test -n "$candidate_version"; then
    tagged_revision=$(git -C "$scratch/ContinuumKit" rev-parse "refs/tags/$candidate_version^{commit}")
    if test "$tagged_revision" != "$revision"; then
        echo "Release tag must identify the candidate HEAD." >&2
        exit 1
    fi
fi
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
export CONTINUUMKIT_CONSUMER_VERSION="$candidate_version"
mkdir -p "$scratch/consumer/Sources/Consumer"
cat > "$scratch/consumer/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
let source = URL(fileURLWithPath: environment["CONTINUUMKIT_CONSUMER_SOURCE"]!).absoluteString
let version = environment["CONTINUUMKIT_CONSUMER_VERSION"]!
let dependency: Package.Dependency = version.isEmpty
    ? .package(url: source, revision: environment["CONTINUUMKIT_CONSUMER_REVISION"]!)
    : .package(url: source, exact: Version(version)!)

let package = Package(
    name: "ContinuumConsumer",
    platforms: [.macOS(.v15)],
    dependencies: [dependency],
    targets: [
        .executableTarget(
            name: "Consumer",
            dependencies: [.product(name: "ContinuumKit", package: "continuumkit")]
        )
    ],
    swiftLanguageModes: [.v6]
)
SWIFT
cat > "$scratch/consumer/Sources/Consumer/main.swift" <<'SWIFT'
import ContinuumKit
print("ContinuumKit clean Git consumer passed.")
SWIFT
swift build --package-path "$scratch/consumer" -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" --skip-build Consumer
