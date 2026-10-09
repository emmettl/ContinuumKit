#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-wave-consumer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
if test -n "$candidate_version"; then
 tagged_revision=$(git -C "$scratch/ContinuumKit" rev-parse "refs/tags/$candidate_version^{commit}")
 if test "$tagged_revision" != "$revision"; then
  echo 'Release tag must identify the candidate HEAD.' >&2
  exit 1
 fi
fi
export CONTINUUMKIT_CONSUMER_VERSION="$candidate_version"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/LinearWaveConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build WaveConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/WaveConsumer
linked_frameworks=$(otool -L "$binary")
if rg -q '/(Metal|MetalKit|AppKit|SwiftUI)\.framework/' <<< "$linked_frameworks"; then
  echo 'CPU wave consumer unexpectedly links a rendering/UI framework' >&2
  exit 1
fi
printf 'PASS CPU wave consumer has no Metal or UI framework dependency\n'
