#!/bin/bash
# The complete gate, with bounded CPU scheduling and optional external evidence.
set -euo pipefail
task_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$task_root"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
# Homebrew's tools first (rg), but the system's Python, which the evidence was made and is audited
# with: Homebrew's 3.15 sums floats with compensation and leaves the weighted QR audit's 64-ulp
# predictions (alpha.27's release runs, 18 October 2026).
if test -x /usr/bin/python3; then
    task_python=$(mktemp -d "${TMPDIR:-/tmp}/continuumkit-python.XXXXXX")
    trap 'rm -rf "$task_python"' EXIT
    ln -s /usr/bin/python3 "$task_python/python3"
    export PATH="$task_python:$PATH"
fi
for task_tool in swift python3 rg otool git; do command -v "$task_tool" >/dev/null; done
swift() {
    case "${1:-}" in
        build) command swift "$@" -j 1 ;;
        test) command swift "$@" -j 1 --no-parallel ;;
        *) command swift "$@" ;;
    esac
}
export -f swift
# Without evidence selection, preserve the normal check's cleanup/retention policy.
if test -z "${CONTINUUMKIT_EVIDENCE_DIR:-}"; then
    exec bash Scripts/check.sh "$@"
fi
task_evidence=$CONTINUUMKIT_EVIDENCE_DIR
case "$task_evidence" in /*) ;; *) echo 'Evidence directory must be absolute' >&2; exit 1 ;; esac
# Never overwrite a prior receipt or write outputs into the source checkout.
python3 - "$task_root" "$task_evidence" <<'PY'
import sys
from pathlib import Path
root, evidence = map(lambda s: Path(s).resolve(), sys.argv[1:])
if evidence == root or root in evidence.parents:
    raise SystemExit('Evidence must be outside the source checkout')
if evidence.exists():
    raise SystemExit('Evidence directory already exists; choose a fresh run identity')
evidence.mkdir(parents=True)
PY
export CONTINUUMKIT_KEEP_OUTPUT=1
export CONTINUUMKIT_OUTPUT_ROOT="$task_evidence/outputs"
# Override workflow output variables so every retained report has the same external owner.
export CONTINUUMKIT_AFFINE_OUTPUT="$task_evidence/affine-fit"
export CONTINUUMKIT_QR_OUTPUT="$task_evidence/pivoted-qr"
export CONTINUUMKIT_ORIGIN_OUTPUT="$task_evidence/origin-least-squares"
export CONTINUUMKIT_REAL_FFT_OUTPUT="$task_evidence/real-fft"
export CONTINUUMKIT_EULER_FLUX_OUTPUT="$task_evidence/euler-flux"
printf '%s\n' "$$" > "$task_evidence/wrapper.pid"
git rev-parse HEAD > "$task_evidence/revision.txt"
type -P swift python3 rg otool git > "$task_evidence/tool-paths.txt"
date -u +%FT%TZ > "$task_evidence/started.txt"
set +e
bash Scripts/check.sh "$@" 2>&1 | tee "$task_evidence/full-check.log"
task_status=$?
set -e
printf '%s\n' "$task_status" > "$task_evidence/exit-status.txt"
date -u +%FT%TZ > "$task_evidence/finished.txt"
exit "$task_status"
