#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Scripts/output.sh"
test -z "$(git -C "$root" status --porcelain)"
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-pivoted-qr-consumer.XXXXXX")
trap 'rm -rf "$scratch"; continuumkit_cleanup' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
if test -n "$candidate_version"; then
  test "$(git -C "$scratch/ContinuumKit" rev-parse "refs/tags/$candidate_version^{commit}")" = "$revision"
fi
export CONTINUUMKIT_CONSUMER_VERSION="$candidate_version"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
continuumkit_output pivoted-qr-output "${2:-${CONTINUUMKIT_QR_OUTPUT:-}}"
mkdir -p "$output"
test ! -e "$output/results.json"
export CONTINUUMKIT_QR_OUTPUT="$output"
python3 - "$root" "$output" <<'PYMETA'
import hashlib,json,os,platform,shutil,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:])
def git(*args):return subprocess.check_output(['git',*args],cwd=r,text=True).strip()
paths=git('ls-files','Sources/Numerics','Tests/NumericsTests','Fixtures/PivotedQRConsumer','Scripts/check-pivoted-qr-consumer.sh','Scripts/verify-pivoted-qr-output.py','Scripts/test-pivoted-qr-gate.py','Scripts/verify-weighted-qr-audit.py').splitlines()
d={'schemaVersion':1,'candidateRevision':git('rev-parse','HEAD'),'candidateVersion':os.environ['CONTINUUMKIT_CONSUMER_VERSION'],'workingTreeDirty':False,'sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'os':platform.platform(),'flags':['-c','release','-Xswiftc','-warnings-as-errors']}
(o/'environment.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
for path in paths:
 target=o/'reference-sources'/path;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(r/path,target)
PYMETA
# Recompile the protected original arithmetic unchanged for the exact producer.
bash "$root/Scripts/check-weighted-qr-audit.sh" "$output/original-audit"
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/PivotedQRConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build PivotedQRConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/PivotedQRConsumer
otool -L "$binary" > "$output/linkage.txt"
if grep -Eq '/(Metal|MetalKit|AppKit|SwiftUI|Accelerate)\.framework/' "$output/linkage.txt"; then
  echo 'Pivoted QR consumer unexpectedly links a rendering/UI/Accelerate framework' >&2
  exit 1
fi
cp "$scratch/consumer/Package.resolved" "$output/consumer-Package.resolved"
python3 "$root/Scripts/verify-pivoted-qr-output.py" "$output"
python3 "$root/Scripts/test-pivoted-qr-gate.py" "$output"
printf 'PASS pivoted QR consumer has no Metal, UI or Accelerate dependency\n'
