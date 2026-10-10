#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-metal-throughput-output.XXXXXX")}
mkdir -p "$output"
test -z "$(git status --porcelain)"
revision=$(git rev-parse HEAD)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-metal-throughput-build.XXXXXX")
trap 'task_status=$?; rm -rf "$scratch"; exit "$task_status"' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
test "$(git -C "$scratch/ContinuumKit" rev-parse HEAD)" = "$revision"
python3 Scripts/prepare-metal-wave-throughput.py --core "$scratch/ContinuumKit" --output "$scratch/consumer"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
python3 - "$root" "$output" <<'PY'
import json,subprocess,sys,platform
from pathlib import Path
root,output=map(Path,sys.argv[1:])
def run(*cmd):return subprocess.check_output(cmd,cwd=root,text=True).strip()
(output/'environment.json').write_text(json.dumps({'schemaVersion':1,'candidate':run('git','rev-parse','HEAD'),'workingTreeDirty':bool(run('git','status','--porcelain')),'hardware':run('sysctl','-n','machdep.cpu.brand_string'),'os':platform.platform(),'swift':run('swift','--version'),'scope':'optimized released/profiled32/profiled256 models; one unreported whole-run warmup each, three rotating repetitions; complete fields copied outside timing; live host, no isolation claim'},indent=2,sort_keys=True)+'\n')
PY
swift run --package-path "$scratch/consumer" -c release -Xswiftc -enable-testing -Xswiftc -warnings-as-errors MetalWaveThroughput --output "$output"
cp "$scratch/consumer/Package.resolved" "$output/consumer-Package.resolved"
cp "$scratch/consumer/profile-source-provenance.json" "$output/profile-source-provenance.json"
mkdir -p "$output/baseline-source" "$output/profiled-source"
python3 - "$scratch/ContinuumKit" "$scratch/consumer" "$output" <<'PY'
import json,subprocess,sys,shutil
from pathlib import Path
core,consumer,output=map(Path,sys.argv[1:]);p=json.loads((consumer/'profile-source-provenance.json').read_text())
for path in p['files']:
 (output/'baseline-source'/Path(path).name).write_bytes(subprocess.check_output(['git','show',p['baseline']+':'+path],cwd=core))
 shutil.copy2(consumer/'Sources/ProfiledMetal'/Path(path).relative_to('Sources/LinearAcousticsMetal'),output/'profiled-source'/Path(path).name)
PY
python3 Scripts/verify-metal-wave-throughput.py "$output"
python3 Scripts/test-metal-wave-throughput-gate.py "$output"
