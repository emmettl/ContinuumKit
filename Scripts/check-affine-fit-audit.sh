#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
test -z "$(git -C "$root" status --porcelain)"
revision=$(git -C "$root" rev-parse HEAD)
continuumkit_output affine-audit-output "${1:-}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-affine-audit-build.XXXXXX")
trap 'rm -rf "$scratch"; continuumkit_cleanup' EXIT
mkdir -p "$output"
python3 - "$root" "$output" "$revision" <<'PYMETA'
import hashlib,json,platform,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:3]);revision=sys.argv[3]
paths=subprocess.check_output(['git','ls-files','Fixtures/AffineFitAudit','Scripts/check-affine-fit-audit.sh','Scripts/prepare-affine-fit-audit.py','Scripts/verify-affine-fit-audit.py','Scripts/test-affine-fit-audit-gate.py'],cwd=r,text=True).splitlines()
d={'schemaVersion':1,'producerRevision':revision,'workingTreeDirty':False,'scope':'protected original arithmetic audit, not shared fitting conformance','sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'os':platform.platform(),'flags':['-O','-warnings-as-errors']}
(o/'environment.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
PYMETA
python3 "$root/Scripts/prepare-affine-fit-audit.py" --output "$scratch/OriginalFits.swift"
cp "$scratch/OriginalFits.swift" "$output/compiled-original-loops.swift"
swiftc -O -warnings-as-errors "$scratch/OriginalFits.swift" "$root/Fixtures/AffineFitAudit/main.swift" -o "$scratch/audit"
"$scratch/audit" "$output/original.json"
python3 "$root/Scripts/verify-affine-fit-audit.py" "$output"
python3 "$root/Scripts/test-affine-fit-audit-gate.py" "$output"
