#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-${CONTINUUMKIT_ACOUSTIC_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-acoustic.XXXXXX")}}
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/AcousticCase.swift \
 Sources/BenchmarkSupport/AcousticOracle.swift Sources/BenchmarkSupport/AcousticResult.swift \
 Sources/BenchmarkSupport/AcousticCommand.swift Sources/continuumbench/main.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite acoustic-reference \
 --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-acoustic-output.py "$output" --reference
