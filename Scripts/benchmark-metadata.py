#!/usr/bin/env python3
"""Write source/hardware provenance for a benchmark; source files are named explicitly."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', required=True, type=Path)
parser.add_argument('--repository', required=True)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--dependency', action='append', default=[])
parser.add_argument('--precision', default='Float64')
parser.add_argument('sources', nargs='+')
args = parser.parse_args()
root = args.root.resolve()
revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
changed = subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip()
try:
    hardware = subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
except (OSError, subprocess.CalledProcessError):
    hardware = platform.machine()
data = {
    'repository': args.repository, 'revision': revision,
    'dependencies': dict(item.split('=', 1) for item in args.dependency),
    'sourceHashes': {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in args.sources},
    'hardware': hardware, 'toolchain': subprocess.check_output(['swift', '--version'], text=True).strip(),
    'operatingSystem': platform.platform(), 'precision': args.precision, 'workingTreeDirty': bool(changed),
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(data, indent=2) + '\n')
