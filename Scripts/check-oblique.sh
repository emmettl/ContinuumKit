#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
trap continuumkit_cleanup EXIT
cd "$root"
continuumkit_output oblique "${1:-${CONTINUUMKIT_OBLIQUE_OUTPUT:-}}"
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/ObliqueMode.swift Sources/BenchmarkSupport/ObliqueModeCommand.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite oblique-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-oblique-output.py "$output" --reference
