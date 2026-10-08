#!/usr/bin/env python3
"""Require all cases, native staggered grids, refinement reports and explicit unsupported capability."""
import argparse,json,math
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--rigid-only',action='store_true');a=p.parse_args()
root=a.output;cases=json.loads((root/'cases.json').read_text());results=json.loads((root/'results.json').read_text());conformance=json.loads((root/'conformance.json').read_text())
assert len(cases)==5 and len({c['id'] for c in cases})==5
expected_count=15 if a.rigid_only else 24;assert len(results)==expected_count
for c in cases:
 runs=[r for r in results if r['specification']==c]
 if a.rigid_only and c['kind']=='impedancePulse':
  assert len(runs)==1 and runs[0]['status']=='unsupported' and runs[0]['reason'] and runs[0].get('history') is None
  continue
 assert len(runs)==(6 if c['kind']=='obliqueMode' else 4)
 for r in runs:
  assert r['schemaVersion']==1 and r['status']==('reference' if a.reference else 'supported')
  config=r['resolution'];h=r['history'];nx,ny=config['nx'],config['ny'];steps=config['steps']
  intervals=8 if c['kind']=='obliqueMode' else 24
  captures={i*steps//intervals for i in range(intervals+1)}
  if c['kind']=='impedancePulse':captures.add(math.floor((.25-.075)/320/(.275/320)*steps+.5))
  assert [f['step'] for f in h['frames']]==sorted(captures)
  assert all(math.isfinite(h[k]) and h[k]>0 for k in ['dx','dy','dt'])
  for f in h['frames']:
   assert len(f['p'])==nx*ny and len(f['u'])==(nx+1)*ny and len(f['v'])==nx*(ny+1)
   assert all(math.isfinite(v) for field in ['p','u','v'] for v in f[field])
   assert math.isfinite(f['dissipation']) and f['dissipation']>=0
  assert all(math.isfinite(v) for v in r['errors'].values() if v is not None)
 for axis in (['space','time'] if c['kind']=='obliqueMode' else ['space','time-sensitivity']):
  checks=[r for r in conformance if r['case']==c['id'] and r['axis']==axis]
  assert len(checks)==1 and checks[0]['status']==('reference' if a.reference else 'passed')
print(f'PASS complete boundary reports: {len(results)} records; unsupported cases are not passes')
