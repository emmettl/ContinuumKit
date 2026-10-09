#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-${CONTINUUMKIT_ADMITTANCE_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-admittance.XXXXXX")}}
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/AdmittanceAudit.swift Sources/BenchmarkSupport/AdmittanceCommand.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite admittance-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-admittance-output.py "$output" --reference
