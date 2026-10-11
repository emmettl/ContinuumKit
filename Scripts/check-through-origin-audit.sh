#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
test -z "$(git -C "$root" status --porcelain)"
output=${1:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-through-origin-audit.XXXXXX")}
mkdir -p "$output"
python3 -B "$root/Scripts/through-origin-audit.py" "$output"
python3 -B "$root/Scripts/through-origin-audit.py" "$output" --verify
python3 - "$root" "$output" <<'PY'
import hashlib,json,platform,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:]);paths=subprocess.check_output(['git','ls-files','Fixtures/ThroughOriginAudit','Scripts/through-origin-audit.py','Scripts/check-through-origin-audit.sh'],cwd=r,text=True).splitlines()
d={'producerRevision':subprocess.check_output(['git','rev-parse','HEAD'],cwd=r,text=True).strip(),'workingTreeDirty':False,'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'python':sys.version,'os':platform.platform(),'sources':{p:{'bytes':(r/p).stat().st_size,'sha256':hashlib.sha256((r/p).read_bytes()).hexdigest()} for p in paths}}
(o/'producer.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
PY
