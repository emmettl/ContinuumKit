#!/usr/bin/env python3
"""Require full native 3D pressure and all staggered velocity histories, or explicit unsupported cases."""
import argparse, ast, csv, gzip, json, math
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--unsupported',action='store_true');a=p.parse_args()
def read(name):
 f=a.output/name
 if f.exists():return json.loads(f.read_text())
 with gzip.open(str(f)+'.gz','rt') as stream:return json.load(stream)
cases=read('cases.json');results=read('results.json');checks=read('conformance.json')
assert [(c['id'],c['modes'],c['anisotropicGrid']) for c in cases]==[('body-diagonal',[2,1,1],False),('anisotropic-grid',[1,1,1],True)]
assert len(results)==(2 if a.unsupported else 12)
for c in cases:
 assert c['version']==1 and c['lengths']==[.25,.125,.125] and (c['density'],c['speed'],c['amplitude'])==(1.25,320,1)
 runs=[r for r in results if r['specification']==c]
 if a.unsupported:
  assert len(runs)==1 and runs[0]['status']=='unsupported' and runs[0]['reason'] and runs[0].get('history') is None and runs[0].get('errors') is None and runs[0].get('resolution') is None
  report=[q for q in checks if q['case']==c['id']];assert len(report)==1 and report[0]['status']=='unsupported' and report[0]['reason']
  continue
 assert len(runs)==6
 duration=2*math.pi/(320*math.sqrt(sum((math.pi*m/l)**2 for m,l in zip(c['modes'],c['lengths']))))
 def dims(n):return (n,n//2,n//(4 if c['anisotropicGrid'] else 2))
 def steps(n,cfl):return 8*math.ceil(duration*320*math.sqrt(sum((d/l)**2 for d,l in zip(dims(n),c['lengths'])))/cfl/8)
 expected=[('space',*dims(n),steps(64,.25)) for n in (16,32,64)]+[('time',*dims(32),steps(32,cfl)) for cfl in (.8,.4,.2)]
 assert [(r['resolution']['axis'],r['resolution']['nx'],r['resolution']['ny'],r['resolution']['nz'],r['resolution']['steps']) for r in runs]==expected
 for r in runs:
  assert r['schemaVersion']==1 and r['status']==('reference' if a.reference else 'supported')
  cfg=r['resolution'];h=r['history'];ds=[cfg[k] for k in ['nx','ny','nz']]
  assert r['reference']==('exact-3D-spatial-eigenmode' if cfg['axis']=='time' else 'continuum-3D-rigid-mode')
  assert len(h['spacing'])==3 and all(math.isfinite(x) and x>0 for x in h['spacing']) and math.isfinite(h['dt']) and h['dt']>0
  assert all(abs(s*d/l-1)<1e-6 for s,d,l in zip(h['spacing'],ds,c['lengths'])) and abs(h['dt']*cfg['steps']/duration-1)<1e-6
  assert [f['step'] for f in h['frames']]==[i*cfg['steps']//8 for i in range(9)]
  for frame in h['frames']:
   for field,offset in zip(['p','u','v','w'],[-1,0,1,2]):
    shape=[d+(axis==offset) for axis,d in enumerate(ds)]
    assert len(frame[field])==math.prod(shape) and all(math.isfinite(x) for x in frame[field])
  e=r['errors'];assert len(e['fieldL2'])==4 and all(math.isfinite(x) and x>=0 for x in e['fieldL2'])
  assert all(math.isfinite(v) and v>=0 for k,v in e.items() if k!='fieldL2')
 for axis in ['space','time']:
  report=[q for q in checks if q['case']==c['id'] and q['axis']==axis]
  assert len(report)==1 and report[0]['status']==('reference' if a.reference else 'passed')
  if not a.reference:
   orders=ast.literal_eval(report[0]['orders']);assert len(orders)==4 and all(len(row)==2 and all(1.7<=x<=2.3 for x in row) for row in orders)
   series=[r for r in runs if r['resolution']['axis']==axis]
   for field,row in enumerate(orders):
    for i,order in enumerate(row):
     ratio=series[i+1]['resolution']['nx']/series[i]['resolution']['nx'] if axis=='space' else series[i]['history']['dt']/series[i+1]['history']['dt']
     computed=math.log(series[i]['errors']['fieldL2'][field]/series[i+1]['errors']['fieldL2'][field])/math.log(ratio)
     assert abs(order-computed)<1e-12
   e=series[-1]['errors'];assert max(e['fieldL2'])<.01 and e['maxPressure']<.03 and e['maxVelocity']<.03 and e['energyBudget']<1e-4 and e['initialEnergyError']<.01 and e['boundaryVelocity']<1e-6
with (a.output/'summary.csv').open() as f:rows=list(csv.DictReader(f))
assert len(rows)==len(results)
for row,r in zip(rows,results):
 assert (row['model'],row['case'],row['status'],row['reference'])==(r['model'],r['specification']['id'],r['status'],r['reference'])
 if r.get('errors'):
  e=r['errors']
  for col,value in zip(['pressure_relative_l2','ux_relative_l2','uy_relative_l2','uz_relative_l2'],e['fieldL2']):assert float(row[col])==value
  for col,key in [('max_pressure_normalized','maxPressure'),('max_velocity_normalized','maxVelocity'),('energy_budget_normalized','energyBudget'),('initial_energy_error','initialEnergyError'),('boundary_velocity_normalized','boundaryVelocity')]:assert float(row[col])==e[key]
print(f'PASS complete 3D reports: {len(results)} records; all three velocities retained; unsupported cases are not passes')
