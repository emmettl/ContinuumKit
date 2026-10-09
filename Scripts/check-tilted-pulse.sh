#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-${CONTINUUMKIT_TILTED_PULSE_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-tilted-pulse.XXXXXX")}}
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/TiltedPulse.swift Sources/BenchmarkSupport/TiltedPulseCommand.swift Sources/BenchmarkSupport/CylinderModes.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite tilted-pulse-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-tilted-pulse-output.py "$output" --reference
