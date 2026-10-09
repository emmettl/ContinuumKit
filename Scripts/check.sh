#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

for script in Scripts/*.sh; do bash -n "$script"; done
git diff --check
if test "${CONTINUUMKIT_REQUIRE_METAL:-0}" = 1; then
    swift Scripts/check-metal.swift
fi
swift build -Xswiftc -warnings-as-errors
if test -d Tests; then
    swift test -Xswiftc -warnings-as-errors
fi
bash Scripts/check-consumer.sh "${1:-}"

bash Scripts/check-adiabatic.sh

bash Scripts/check-acoustics.sh

bash Scripts/check-boundaries.sh

bash Scripts/check-rigid-3d.sh

bash Scripts/check-oblique.sh

bash Scripts/check-masked.sh

bash Scripts/check-cylinder.sh

bash Scripts/check-admittance.sh

bash Scripts/check-absorbing-cylinder.sh
