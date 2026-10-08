#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-${CONTINUUMKIT_BOUNDARY_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-boundary.XXXXXX")}}
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/BoundaryAcoustic.swift Sources/BenchmarkSupport/BoundaryCommand.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite boundary-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-boundary-output.py "$output" --reference
