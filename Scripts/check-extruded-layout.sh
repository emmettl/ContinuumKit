#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
output=${1:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-extruded-layout.XXXXXX")}
python3 "$root/Scripts/test-extruded-layout.py"
python3 "$root/Scripts/extruded_layout.py" reference "$output"
python3 "$root/Scripts/benchmark-metadata.py" --root "$root" --repository https://github.com/emmettl/ContinuumKit --precision Float64-oracle-Float32-storage --output "$output/environment.json" Scripts/extruded_layout.py Scripts/test-extruded-layout.py Fixtures/ExtrudedLayout/cases.json
