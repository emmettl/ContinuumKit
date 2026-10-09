#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
revision=$(git -C "$root" rev-parse HEAD)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-wave-consumer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/LinearWaveConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build WaveConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/WaveConsumer
if otool -L "$binary" | rg -q '/(Metal|MetalKit|AppKit|SwiftUI)\.framework/'; then
  echo 'CPU wave consumer unexpectedly links a rendering/UI framework' >&2
  exit 1
fi
printf 'PASS CPU wave consumer has no Metal or UI framework dependency\n'
