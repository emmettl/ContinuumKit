#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)

test -z "$(git -C "$root" status --porcelain)"
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-affine-fit-consumer.XXXXXX")
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
output=${2:-${CONTINUUMKIT_AFFINE_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-affine-fit-output.XXXXXX")}}
mkdir -p "$output"
export CONTINUUMKIT_AFFINE_OUTPUT="$output"
python3 - "$root" "$output" <<'PYMETA'
import json,hashlib,platform,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:])
def git(*args):return subprocess.check_output(['git',*args],cwd=r,text=True).strip()
paths=git('ls-files','Sources/Numerics','Tests/NumericsTests','Fixtures/AffineFitConsumer','Fixtures/AffineFitAudit','Scripts/check-affine-fit-consumer.sh','Scripts/prepare-affine-fit-audit.py','Scripts/verify-affine-fit-output.py','Scripts/test-affine-fit-gate.py').splitlines()
d={'schemaVersion':1,'candidate':git('rev-parse','HEAD'),'workingTreeDirty':bool(git('status','--porcelain')),'sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'os':platform.platform()}
(o/'environment.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
PYMETA
# Generate the unchanged original audit on this host. Source and loop identity
# stay protected by the released audit preparer; its numerical failures remain findings.
python3 "$root/Scripts/prepare-affine-fit-audit.py" --output "$scratch/OriginalFits.swift"
swiftc -O -warnings-as-errors "$scratch/OriginalFits.swift" "$root/Fixtures/AffineFitAudit/main.swift" -o "$scratch/original-audit"
"$scratch/original-audit" "$output/original-audit.json"
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/AffineFitConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build AffineFitConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/AffineFitConsumer
linked_frameworks=$(otool -L "$binary")
printf '%s\n' "$linked_frameworks" > "$output/linkage.txt"
if grep -Eq '/(Metal|MetalKit|AppKit|SwiftUI|Accelerate)\.framework/' <<< "$linked_frameworks"; then
  echo 'Affine fit consumer unexpectedly links a rendering/UI framework' >&2
  exit 1
fi
cp "$scratch/consumer/Package.resolved" "$output/consumer-Package.resolved"
python3 "$root/Scripts/verify-affine-fit-output.py" "$output"
printf 'PASS Affine fit consumer has no Metal or UI framework dependency\n'
python3 "$root/Scripts/test-affine-fit-gate.py" "$output"
