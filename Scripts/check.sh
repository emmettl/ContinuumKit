#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

for script in Scripts/*.sh; do bash -n "$script"; done
git diff --check
python3 Scripts/verify-orthotropic-source.py
python3 Scripts/verify-isotropic-tet-source.py
python3 Scripts/verify-gmres-source.py
python3 Scripts/verify-scalar-material-source.py
python3 Scripts/verify-normal-contact-source.py
python3 Scripts/verify-contact-search-source.py
if test "${CONTINUUMKIT_REQUIRE_METAL:-0}" = 1; then
    swift Scripts/check-metal.swift
fi
swift build -Xswiftc -warnings-as-errors
if test -d Tests; then
    swift test -Xswiftc -warnings-as-errors
fi
bash Scripts/check-orthotropic-consumer.sh "${1:-}"
bash Scripts/check-isotropic-tet-consumer.sh "${1:-}"
bash Scripts/check-gmres-consumer.sh "${1:-}"
bash Scripts/check-scalar-material-consumer.sh "${1:-}"
bash Scripts/check-timber-failure-consumer.sh "${1:-}"
bash Scripts/check-normal-contact-consumer.sh "${1:-}"
bash Scripts/check-contact-search-consumer.sh "${1:-}"
bash Scripts/check-consumer.sh "${1:-}"
bash Scripts/check-linear-wave-consumer.sh "${1:-}"
bash Scripts/check-metal-wave-consumer.sh "${1:-}"
bash Scripts/check-gas-wall-consumer.sh "${1:-}"
bash Scripts/check-gas-packet-consumer.sh "${1:-}"
bash Scripts/check-euler-flux-consumer.sh "${1:-}"
bash Scripts/check-real-fft-consumer.sh "${1:-}"
bash Scripts/check-affine-fit-consumer.sh "${1:-}"
bash Scripts/check-pivoted-qr-consumer.sh "${1:-}"
bash Scripts/check-origin-least-squares-consumer.sh "${1:-}"

python3 Scripts/verify-wave-metal-port.py

bash Scripts/check-adiabatic.sh

bash Scripts/check-acoustics.sh

bash Scripts/check-boundaries.sh

bash Scripts/check-rigid-3d.sh

bash Scripts/check-oblique.sh

bash Scripts/check-masked.sh

bash Scripts/check-cylinder.sh

bash Scripts/check-admittance.sh

bash Scripts/check-absorbing-cylinder.sh

bash Scripts/check-tilted-pulse.sh

bash Scripts/check-extruded-layout.sh
