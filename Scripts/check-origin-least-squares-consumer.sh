#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
test -z "$(git -C "$root" status --porcelain)"
revision=$(git -C "$root" rev-parse HEAD)
version=${1:-}
continuumkit_output origin-output "${2:-${CONTINUUMKIT_ORIGIN_OUTPUT:-}}"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-origin-consumer.XXXXXX")
trap 'rm -rf "$scratch"; continuumkit_cleanup' EXIT
mkdir -p "$output"
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
if test -n "$version"; then test "$(git -C "$scratch/ContinuumKit" rev-parse "refs/tags/$version^{commit}")" = "$revision"; fi
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
export CONTINUUMKIT_CONSUMER_VERSION="$version"
python3 -B "$root/Scripts/prepare-origin-least-squares.py" "$output"
git -C "$root" archive HEAD Fixtures/OriginLeastSquaresConsumer | tar -x -C "$scratch"
consumer="$scratch/Fixtures/OriginLeastSquaresConsumer"
swift build --package-path "$consumer" -c release -Xswiftc -warnings-as-errors
binary=$(swift build --package-path "$consumer" -c release --show-bin-path)/OriginLeastSquaresConsumer
"$binary" "$output/inputs.json" "$output/public"
otool -L "$binary" > "$output/linkage.txt"
if grep -Eq '/(Metal|MetalKit|AppKit|SwiftUI|Accelerate)\.framework/' "$output/linkage.txt"; then echo 'Unexpected numerical consumer dependency' >&2; exit 1; fi
cp "$consumer/Package.resolved" "$output/consumer-Package.resolved"
swiftc -O -warnings-as-errors -D ORIGIN_SOURCE_CAPTURE "$output/ObservedOriginLeastSquares.swift" "$root/Fixtures/OriginLeastSquaresConsumer/Sources/OriginLeastSquaresConsumer/main.swift" -o "$scratch/capture"
"$scratch/capture" "$output/inputs.json" "$output/native"
cmp "$output/public/results.json" "$output/native/results.json"
python3 -B "$root/Scripts/verify-origin-least-squares.py" "$output"
python3 - "$root" "$output" "$revision" "$version" <<'PY'
import hashlib,json,platform,shutil,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:3]);revision,version=sys.argv[3:]
paths=subprocess.check_output(['git','ls-files','Sources/Numerics','Tests/NumericsTests','Fixtures/OriginLeastSquaresConsumer','Fixtures/ThroughOriginAudit','Scripts/through-origin-audit.py','Scripts/prepare-origin-least-squares.py','Scripts/verify-origin-least-squares.py','Scripts/check-origin-least-squares-consumer.sh'],cwd=r,text=True).splitlines()
pins=json.loads((o/'consumer-Package.resolved').read_text())['pins'];assert len(pins)==1 and pins[0]['state']['revision']==revision
if version:assert pins[0]['state']['version']==version
metadata={'producerRevision':revision,'version':version,'workingTreeDirty':False,'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'os':platform.platform(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'python':sys.version,'publicFlags':['-c','release','-Xswiftc','-warnings-as-errors'],'observationFlags':['-O','-warnings-as-errors','-D','ORIGIN_SOURCE_CAPTURE'],'sourceHashes':{p:{'bytes':(r/p).stat().st_size,'sha256':hashlib.sha256((r/p).read_bytes()).hexdigest()} for p in paths}}
(o/'environment.json').write_text(json.dumps(metadata,indent=2,sort_keys=True)+'\n')
for p in paths:
 t=o/'source'/p;t.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(r/p,t)
PY
