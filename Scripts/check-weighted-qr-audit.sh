#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
test -z "$(git -C "$root" status --porcelain)"
revision=$(git -C "$root" rev-parse HEAD)
continuumkit_output weighted-qr-output "${1:-}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-weighted-qr-build.XXXXXX")
trap 'rm -rf "$scratch"; continuumkit_cleanup' EXIT
mkdir -p "$output"
test ! -e "$output/original.json"
python3 - "$root" "$output" "$revision" <<'PYMETA'
import hashlib,json,platform,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:3]);revision=sys.argv[3]
paths=subprocess.check_output(['git','ls-files','Fixtures/WeightedQRAudit','Scripts/check-weighted-qr-audit.sh','Scripts/prepare-weighted-qr-audit.py','Scripts/verify-weighted-qr-audit.py','Scripts/test-weighted-qr-audit-gate.py'],cwd=r,text=True).splitlines()
d={'schemaVersion':1,'producerRevision':revision,'workingTreeDirty':False,'scope':'protected original QR arithmetic audit; findings are not shared solver conformance','sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'os':platform.platform(),'flags':['-O','-warnings-as-errors']}
(o/'environment.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
PYMETA
python3 "$root/Scripts/prepare-weighted-qr-audit.py" --output "$scratch/Original.swift"
cp "$scratch/Original.swift" "$output/compiled-original.swift"
cp "$scratch/Original.bindings.json" "$output/bindings.json"
cp -R "$root/Fixtures/WeightedQRAudit" "$output/source"
mkdir -p "$output/scripts"
for name in check-weighted-qr-audit.sh prepare-weighted-qr-audit.py verify-weighted-qr-audit.py test-weighted-qr-audit-gate.py; do
  cp "$root/Scripts/$name" "$output/scripts/$name"
done
swiftc -O -warnings-as-errors "$scratch/Original.swift" "$root/Fixtures/WeightedQRAudit/main.swift" -o "$scratch/audit"
"$scratch/audit" "$output/original.json"
python3 "$root/Scripts/verify-weighted-qr-audit.py" "$output"
python3 "$root/Scripts/test-weighted-qr-audit-gate.py" "$output"
