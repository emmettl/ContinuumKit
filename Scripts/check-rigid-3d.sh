#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
trap continuumkit_cleanup EXIT
cd "$root"
continuumkit_output rigid-3d "${1:-${CONTINUUMKIT_RIGID_3D_OUTPUT:-}}"
mkdir -p "$output"
python3 Scripts/benchmark-metadata.py --root "$root" --repository https://github.com/emmettl/ContinuumKit \
 --output "$output/environment.json" Sources/BenchmarkSupport/RigidModes3D.swift Sources/BenchmarkSupport/RigidModeCommand.swift
swift run -c release -Xswiftc -warnings-as-errors continuumbench --suite rigid-3d-reference --output "$output" --metadata "$output/environment.json"
python3 Scripts/verify-rigid-3d-output.py "$output" --reference
