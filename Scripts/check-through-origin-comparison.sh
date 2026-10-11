#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test -z "$(git -C "$root" status --porcelain)"
output=${1:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-through-origin-comparison.XXXXXX")}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-through-origin-build.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$output"
python3 -B "$root/Scripts/prepare-through-origin-comparison.py" "$output/inputs.json"
git -C "$root" archive HEAD Fixtures/ThroughOriginComparison | tar -x -C "$scratch"
consumer="$scratch/Fixtures/ThroughOriginComparison"
# Build an independent exact-tag Git consumer, not an in-package source target.
swift build --package-path "$consumer" -c release -Xswiftc -warnings-as-errors
binary=$(swift build --package-path "$consumer" -c release --show-bin-path)/ThroughOriginComparison
"$binary" "$output/inputs.json" "$output/qr.json"
otool -L "$binary" > "$output/linkage.txt"
cp "$consumer/Package.resolved" "$output/Package.resolved"
python3 -B "$root/Scripts/verify-through-origin-comparison.py" "$output"
python3 - "$root" "$output" <<'PY'
import hashlib,json,platform,shutil,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:]);paths=subprocess.check_output(['git','ls-files','Fixtures/ThroughOriginAudit','Fixtures/ThroughOriginComparison','Scripts/through-origin-audit.py','Scripts/prepare-through-origin-comparison.py','Scripts/verify-through-origin-comparison.py','Scripts/check-through-origin-comparison.sh'],cwd=r,text=True).splitlines()
d={'producerRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'workingTreeDirty':False,'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'python':sys.version,'os':platform.platform(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'flags':['-c','release','-Xswiftc','-warnings-as-errors'],'dependency':'exact 0.1.0-alpha.19, commit00eac5537843c85c3c25a7ecef1120f49e8aa469','sources':{p:{'bytes':(r/p).stat().st_size,'sha256':hashlib.sha256((r/p).read_bytes()).hexdigest()} for p in paths}}
(o/'producer.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
for p in paths:
 t=o/'source'/p;t.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(r/p,t)
PY
