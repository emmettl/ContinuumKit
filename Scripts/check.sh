#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

for script in Scripts/*.sh; do bash -n "$script"; done
git diff --check
swift build -Xswiftc -warnings-as-errors
if test -d Tests; then
    swift test -Xswiftc -warnings-as-errors
fi
bash Scripts/check-consumer.sh "${1:-}"
