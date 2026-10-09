#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-${CONTINUUMKIT_CYLINDER_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-cylinder.XXXXXX")}}
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/CylinderModes.swift Sources/BenchmarkSupport/CylinderCommand.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite cylinder-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-cylinder-output.py "$output" --reference
