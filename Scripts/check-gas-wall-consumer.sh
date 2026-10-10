#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 "$root/Scripts/verify-gas-wall-source.py"
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-gas-wall-consumer.XXXXXX")
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
output=${2:-${CONTINUUMKIT_GAS_WALL_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-gas-wall-output.XXXXXX")}}
mkdir -p "$output"
export CONTINUUMKIT_GAS_OUTPUT="$output"
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/GasWallConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build GasWallConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/GasWallConsumer
linked_frameworks=$(otool -L "$binary")
if rg -q '/(Metal|MetalKit|AppKit|SwiftUI)\.framework/' <<< "$linked_frameworks"; then
  echo 'Gas wall consumer unexpectedly links a rendering/UI framework' >&2
  exit 1
fi
cp "$scratch/consumer/Package.resolved" "$output/consumer-Package.resolved"
python3 "$root/Scripts/verify-gas-wall-output.py" "$output"
printf 'PASS Gas wall consumer has no Metal or UI framework dependency\n'
