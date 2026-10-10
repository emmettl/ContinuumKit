#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
python3 "$root/Scripts/verify-gas-packet-source.py"
test -z "$(git -C "$root" status --porcelain)"
revision=$(git -C "$root" rev-parse HEAD)
candidate_version=${1:-}
scratch=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-gas-packet-consumer.XXXXXX")
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
output=${2:-${CONTINUUMKIT_GAS_PACKET_OUTPUT:-$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-gas-packet-output.XXXXXX")}}
mkdir -p "$output"
export CONTINUUMKIT_PACKET_OUTPUT="$output"
python3 - "$root" "$output" <<'PYMETA'
import json,hashlib,platform,subprocess,sys
from pathlib import Path
r,o=map(Path,sys.argv[1:])
def git(*args):return subprocess.check_output(['git',*args],cwd=r,text=True).strip()
paths=git('ls-files','Sources/CompressibleFlow','Tests/CompressibleFlowTests','Fixtures/GasPacketConsumer','Scripts/check-gas-packet-consumer.sh','Scripts/verify-gas-packet-source.py','Scripts/verify-gas-packet-output.py','Scripts/test-gas-packet-gate.py').splitlines()
d={'schemaVersion':1,'candidate':git('rev-parse','HEAD'),'workingTreeDirty':bool(git('status','--porcelain')),'sourceHashes':{p:hashlib.sha256((r/p).read_bytes()).hexdigest() for p in paths},'hardware':subprocess.check_output(['sysctl','-n','machdep.cpu.brand_string'],text=True).strip(),'swift':subprocess.check_output(['swift','--version'],text=True).strip(),'os':platform.platform()}
(o/'environment.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n')
PYMETA
mkdir "$scratch/consumer"
cp -R "$scratch/ContinuumKit/Fixtures/GasPacketConsumer/." "$scratch/consumer/"
swift build --package-path "$scratch/consumer" -c release -Xswiftc -warnings-as-errors
swift run --package-path "$scratch/consumer" -c release --skip-build GasPacketConsumer
binary=$(swift build --package-path "$scratch/consumer" -c release --show-bin-path)/GasPacketConsumer
linked_frameworks=$(otool -L "$binary")
if rg -q '/(Metal|MetalKit|AppKit|SwiftUI)\.framework/' <<< "$linked_frameworks"; then
  echo 'Gas packet consumer unexpectedly links a rendering/UI framework' >&2
  exit 1
fi
cp "$scratch/consumer/Package.resolved" "$output/consumer-Package.resolved"
python3 "$root/Scripts/verify-gas-packet-output.py" "$output"
printf 'PASS Gas packet consumer has no Metal or UI framework dependency\n'
python3 "$root/Scripts/test-gas-packet-gate.py" "$output"
