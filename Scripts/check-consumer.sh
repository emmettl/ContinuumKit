#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
configuration=${CONTINUUMKIT_CONSUMER_CONFIGURATION:-release}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-consumer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

# Fetch committed source through Git, without a path dependency or source alias.
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
mkdir -p "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/Consumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c "$configuration" -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c "$configuration" --skip-build Consumer
