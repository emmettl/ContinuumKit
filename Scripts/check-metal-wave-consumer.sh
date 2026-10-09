#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
revision=$(git -C "$root" rev-parse HEAD)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-metal-wave-consumer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/MetalWaveConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build WaveConsumer
printf 'PASS optimized Git Metal wave consumer with actual device work\n'
