#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
trap continuumkit_cleanup EXIT
cd "$root"
continuumkit_output adiabatic "${1:-${CONTINUUMKIT_BENCHMARK_OUTPUT:-}}"
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
    --output "$output/environment.json" Sources/Thermodynamics/AdiabaticReservoir.swift \
    Sources/BenchmarkSupport/AdiabaticCase.swift Sources/BenchmarkSupport/AdiabaticBenchmark.swift \
    Sources/BenchmarkSupport/BenchmarkResult.swift Sources/BenchmarkSupport/AdiabaticCommand.swift \
    Sources/continuumbench/main.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --output "$output" --metadata "$output/environment.json"
echo "Adiabatic histories and source metadata: $output"
