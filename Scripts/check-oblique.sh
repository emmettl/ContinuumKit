#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-${CONTINUUMKIT_OBLIQUE_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-oblique.XXXXXX")}}
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/ObliqueMode.swift Sources/BenchmarkSupport/ObliqueModeCommand.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite oblique-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-oblique-output.py "$output" --reference
