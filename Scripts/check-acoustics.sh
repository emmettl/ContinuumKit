#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
trap continuumkit_cleanup EXIT
cd "$root"
continuumkit_output acoustic "${1:-${CONTINUUMKIT_ACOUSTIC_OUTPUT:-}}"
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/AcousticCase.swift \
 Sources/BenchmarkSupport/AcousticOracle.swift Sources/BenchmarkSupport/AcousticResult.swift \
 Sources/BenchmarkSupport/AcousticCommand.swift Sources/continuumbench/main.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite acoustic-reference \
 --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-acoustic-output.py "$output" --reference
