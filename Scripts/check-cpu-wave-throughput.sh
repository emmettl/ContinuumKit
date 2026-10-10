#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
output=${1:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-cpu-throughput-output.XXXXXX")}
mkdir -p "$output"
test -z "$(git status --porcelain)"
revision=$(git rev-parse HEAD)
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-cpu-throughput-build.XXXXXX")
task_completed=0
trap 'task_status=$?; rm -rf "$scratch"; if test "$task_completed" != 1 && test "$task_status" = 0; then exit 1; fi; exit "$task_status"' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
test "$(git -C "$scratch/ContinuumKit" rev-parse HEAD)" = "$revision"
python3 Scripts/prepare-cpu-wave-throughput.py --core "$scratch/ContinuumKit" --output "$scratch/consumer"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
python3 - "$root" "$output" <<'PY'
import json,subprocess,sys,platform
from pathlib import Path
root,output=map(Path,sys.argv[1:])
def run(*cmd):return subprocess.check_output(cmd,cwd=root,text=True).strip()
(output/'environment.json').write_text(json.dumps({'schemaVersion':1,'candidate':run('git','rev-parse','HEAD'),'workingTreeDirty':bool(run('git','status','--porcelain')),'hardware':run('sysctl','-n','machdep.cpu.brand_string'),'os':platform.platform(),'swift':run('swift','--version'),'scope':'optimized whole CPU source/observation batches; three rotating repetitions per mode/grid, fields copied and encoded outside timing; live host, no isolation claim'},indent=2,sort_keys=True)+'\n')
PY
swift run --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors CPUWaveThroughput --output "$output"
cp "$scratch/consumer/Package.resolved" "$output/consumer-Package.resolved"
cp "$scratch/consumer/baseline-source-provenance.json" "$output/baseline-source-provenance.json"
cp "$scratch/consumer/Sources/CPUWaveThroughput/Alpha8CPUWaveStepper.swift" "$output/Alpha8CPUWaveStepper.swift"
python3 Scripts/verify-cpu-wave-throughput.py "$output"
task_completed=1
