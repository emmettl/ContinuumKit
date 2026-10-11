#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
trap continuumkit_cleanup EXIT
cd "$root"
continuumkit_output boundary "${1:-${CONTINUUMKIT_BOUNDARY_OUTPUT:-}}"
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/BoundaryAcoustic.swift Sources/BenchmarkSupport/BoundaryCommand.swift Sources/BenchmarkSupport/DissipativeLattice.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite boundary-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-boundary-output.py "$output" --reference
