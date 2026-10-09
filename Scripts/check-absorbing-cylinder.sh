#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-${CONTINUUMKIT_ABSORBING_CYLINDER_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-absorbing-cylinder.XXXXXX")}}
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/AbsorbingCylinder.swift Sources/BenchmarkSupport/AbsorbingCylinderCommand.swift Sources/BenchmarkSupport/CylinderModes.swift Sources/BenchmarkSupport/ObliqueMode.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite absorbing-cylinder-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-absorbing-cylinder-output.py "$output" --reference
