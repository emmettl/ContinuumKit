#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 "$root/Scripts/verify-euler-flux-source.py"
test -z "$(git -C "$root" status --porcelain)"
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-euler-flux-consumer.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
git clone --no-local --quiet "$root" "$scratch/ContinuumKit"
if test -n "$candidate_version"; then
 tagged_revision=$(git -C "$scratch/ContinuumKit" rev-parse "refs/tags/$candidate_version^{commit}")
 if test "$tagged_revision" != "$revision"; then
  echo 'Release tag must identify the candidate HEAD.' >&2
  exit 1
 fi
fi
export CONTINUUMKIT_CONSUMER_VERSION="$candidate_version"
export CONTINUUMKIT_CONSUMER_SOURCE="$scratch/ContinuumKit"
export CONTINUUMKIT_CONSUMER_REVISION="$revision"
output=${2:-${CONTINUUMKIT_EULER_FLUX_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-euler-flux-output.XXXXXX")}}
mkdir -p "$output"
export CONTINUUMKIT_EULER_OUTPUT="$output"
python3 - "$root" "$output" <<'PYMETA'
import json,hashlib,platform,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:])
def git(*args):return subprocess.check_output(['git',*args],cwd=r,text=True).strip()
paths=git('ls-files','Sources/CompressibleFlow','Tests/CompressibleFlowTests','Fixtures/EulerFluxConsumer','Scripts/check-euler-flux-consumer.sh','Scripts/verify-euler-flux-source.py','Scripts/verify-euler-flux-output.py','Scripts/test-euler-flux-gate.py').splitlines()
d={'schemaVersion':1,'candidate':git('rev-parse','HEAD'),'workingTreeDirty':bool(git('status','--porcelain')),'sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'os':platform.platform()}
(o/'environment.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
PYMETA
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/EulerFluxConsumer/." "$scratch/consumer/"
# The frozen app source used app aliases. Its compiled copy needs an explicit
# import for the already shared value types, without altering any original bytes
# in the repository or numerical declarations. Verify the import-only adaptation.
python3 - "$scratch/consumer/Sources/EulerFluxConsumer/OriginalFlux.swift" <<'PYIMPORT'
import hashlib,sys
from pathlib import Path
p=Path(sys.argv[1]);original=p.read_bytes()
assert hashlib.sha256(original).hexdigest()=='d80e566a9938f665d71ee00bb813e934bb5febff1a112920200fd47560c818c5'
p.write_bytes(b'import CompressibleFlow\n'+original)
assert p.read_bytes().split(b'\n',1)[1]==original
PYIMPORT
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build EulerFluxConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/EulerFluxConsumer
linked_frameworks=$(otool -L "$binary")
if rg -q '/(Metal|MetalKit|AppKit|SwiftUI)\.framework/' <<< "$linked_frameworks"; then
  echo 'Euler flux consumer unexpectedly links a rendering/UI framework' >&2
  exit 1
fi
cp "$scratch/consumer/Package.resolved" "$output/consumer-Package.resolved"
python3 "$root/Scripts/verify-euler-flux-output.py" "$output"
printf 'PASS Euler flux consumer has no Metal or UI framework dependency\n'
python3 "$root/Scripts/test-euler-flux-gate.py" "$output"
