#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test -z "$(git -C "$root" status --porcelain)"
python3 "$root/Scripts/verify-normal-contact-source.py"
revision=$(git -C "$root" rev-parse HEAD)
version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-normal-contact-consumer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
if test -n "$version"; then
  test "$(git -C "$scratch/ContinuumKit" rev-parse "refs/tags/$version^{commit}")" = "$revision"
fi
export CONTINUUMKIT_CONSUMER_VERSION="$version"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/NormalContactConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -j 1 -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build NormalContactConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/NormalContactConsumer
otool -L "$binary" > "$scratch/linkage.txt"
if grep -Eq '/(Metal|MetalKit|AppKit|SwiftUI|Accelerate)\.framework/' "$scratch/linkage.txt"; then
  echo 'SolidMechanics consumer unexpectedly links a rendering/UI/Accelerate framework' >&2
  exit 1
fi
printf 'PASS SolidMechanics consumer CPU-only linkage\n'
