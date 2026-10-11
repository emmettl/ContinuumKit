#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
trap continuumkit_cleanup EXIT
continuumkit_output extruded-layout "${1:-${CONTINUUMKIT_EXTRUDED_LAYOUT_OUTPUT:-}}"
python3 "$root/Scripts/test-extruded-layout.py"
python3 "$root/Scripts/extruded_layout.py" reference "$output"
python3 "$root/Scripts/benchmark-metadata.py" --root "$root" --repository https://github.com/emmettl/ContinuumKit --precision Float64-oracle-Float32-storage --output "$output/environment.json" Scripts/extruded_layout.py Scripts/test-extruded-layout.py Fixtures/ExtrudedLayout/cases.json
