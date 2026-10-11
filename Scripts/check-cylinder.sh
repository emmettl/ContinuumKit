#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
trap continuumkit_cleanup EXIT
cd "$root"
continuumkit_output cylinder "${1:-${CONTINUUMKIT_CYLINDER_OUTPUT:-}}"
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/CylinderModes.swift Sources/BenchmarkSupport/CylinderCommand.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite cylinder-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-cylinder-output.py "$output" --reference
