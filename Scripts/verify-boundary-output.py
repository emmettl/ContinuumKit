#!/usr/bin/env python3
"""Require all cases, native staggered grids, refinement reports and explicit unsupported capability."""
import argparse,ast,csv,gzip,json,math
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--rigid-only',action='store_true');a=p.parse_args()
root=a.output
def read(name):
 p=root/name
 if p.exists(): return json.loads(p.read_text())
 with gzip.open(str(p)+'.gz','rt') as f: return json.load(f)
cases=read('cases.json');results=read('results.json');conformance=read('conformance.json')
assert len(cases)==5 and len({c['id'] for c in cases})==5
expected_count=15 if a.rigid_only else 24;assert len(results)==expected_count
for c in cases:
 assert c['version']==1 and (c['lengthX'],c['lengthY'],c['density'],c['speed'],c['amplitude'])==(.25,.125,1.25,320,1)
 runs=[r for r in results if r['specification']==c]
 if a.rigid_only and c['kind']=='impedancePulse':
  assert len(runs)==1 and runs[0]['status']=='unsupported' and runs[0]['reason'] and runs[0].get('history') is None
  continue
 assert len(runs)==(6 if c['kind']=='obliqueMode' else 4)
 duration=2*math.pi/(320*math.hypot(math.pi*c['modeX']/.25,math.pi*c['modeY']/.125)) if c['kind']=='obliqueMode' else .275/320
 intervals=8 if c['kind']=='obliqueMode' else 24
 def step_count(n,cfl):return math.ceil(duration*320*n/(cfl*.25)/intervals)*intervals
 if c['kind']=='obliqueMode':
  expected=[('space',n,n//2,step_count(192,.25)) for n in (48,96,192)]+[('time',96,48,step_count(96,cfl)) for cfl in (.6,.3,.15)]
 else:
  expected=[('space',n,4,step_count(512,.25)) for n in (128,256,512)]+[('time-sensitivity',512,4,2*step_count(512,.25))]
 assert [(r['resolution']['axis'],r['resolution']['nx'],r['resolution']['ny'],r['resolution']['steps']) for r in runs]==expected
 for r in runs:
  assert r['schemaVersion']==1 and r['status']==('reference' if a.reference else 'supported')
  config=r['resolution'];h=r['history'];nx,ny=config['nx'],config['ny'];steps=config['steps']
  intervals=8 if c['kind']=='obliqueMode' else 24
  captures={i*steps//intervals for i in range(intervals+1)}
  if c['kind']=='impedancePulse':captures.add(math.floor((.25-.075)/320/(.275/320)*steps+.5))
  assert [f['step'] for f in h['frames']]==sorted(captures)
  assert all(math.isfinite(h[k]) and h[k]>0 for k in ['dx','dy','dt'])
  assert abs(h['dx']*nx/.25-1)<1e-6 and abs(h['dy']*ny/.125-1)<1e-6 and abs(h['dt']*steps/duration-1)<1e-6
  for f in h['frames']:
   assert len(f['p'])==nx*ny and len(f['u'])==(nx+1)*ny and len(f['v'])==nx*(ny+1)
   assert all(math.isfinite(v) for field in ['p','u','v'] for v in f[field])
   assert math.isfinite(f['dissipation']) and f['dissipation']>=0
  assert all(math.isfinite(v) for v in r['errors'].values() if v is not None)
 for axis in (['space','time'] if c['kind']=='obliqueMode' else ['space','time-sensitivity']):
  checks=[r for r in conformance if r['case']==c['id'] and r['axis']==axis]
  assert len(checks)==1 and checks[0]['status']==('reference' if a.reference else 'passed')
  if not a.reference and axis in ('space','time'):
   orders=ast.literal_eval(checks[0]['orders']);assert len(orders)==2
   low=.8 if c['kind']=='impedancePulse' else 1.7
   assert all(low<=p<=2.3 for p in orders)
with (root/'summary.csv').open() as f: rows=list(csv.DictReader(f))
assert len(rows)==len(results)
for row,result in zip(rows,results):
 assert row['case']==result['specification']['id'] and row['status']==result['status']
 if result.get('errors'):
  assert float(row['pressure_relative_l2'])==result['errors']['pressureL2']
  assert float(row['energy_budget_normalized'])==result['errors']['energyBudget']
print(f'PASS complete boundary reports: {len(results)} records; unsupported cases are not passes')
