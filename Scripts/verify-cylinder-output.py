#!/usr/bin/env python3
"""Require full native cylindrical pressure and all staggered velocity histories, or explicit unsupported cases."""
import argparse, ast, csv, gzip, json, math
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--unsupported',action='store_true');a=p.parse_args()
def read(name):
 f=a.output/name
 if f.exists():return json.loads(f.read_text())
 with gzip.open(str(f)+'.gz','rt') as stream:return json.load(stream)
cases=read('cases.json');results=read('results.json');checks=read('conformance.json')
assert len(cases)==1 and cases[0]['id']=='rigid-cylinder'
assert len(results)==(1 if a.unsupported else 6)
for c in cases:
 assert c['version']==1 and c['lengths']==[.25,.25,.125] and (c['density'],c['speed'],c['amplitude'])==(1.25,320,1)
 assert c['inactivePressure']==100 and c['centre']==[.125,.125] and c['radius']==.09375 and c['radialRoot']==3.8317059702075123
 runs=[r for r in results if r['specification']==c]
 if a.unsupported:
  assert len(runs)==1 and runs[0]['status']=='unsupported' and runs[0]['reason'] and runs[0].get('history') is None and runs[0].get('errors') is None and runs[0].get('resolution') is None
  report=[q for q in checks if q['case']==c['id']];assert len(report)==1 and report[0]['status']=='unsupported' and report[0]['reason']
  continue
 assert len(runs)==6
 duration=2*math.pi/(320*math.hypot(c['radialRoot']/c['radius'],math.pi/c['lengths'][2]))
 def dims(n):return (n,n,n//2)
 def steps(n,cfl):return 8*math.ceil(duration*320*math.sqrt(sum((d/l)**2 for d,l in zip(dims(n),c['lengths'])))/cfl/8)
 expected=[('space',*dims(n),steps(64,.25)) for n in (16,32,64)]+[('time',*dims(32),steps(32,cfl)) for cfl in (.8,.4,.2)]
 assert [(r['resolution']['axis'],r['resolution']['nx'],r['resolution']['ny'],r['resolution']['nz'],r['resolution']['steps']) for r in runs]==expected
 for r in runs:
  assert r['schemaVersion']==1 and r['status']==('reference' if a.reference else 'supported')
  cfg=r['resolution'];raw=r['history'];h=raw['fields'];ds=[cfg[k] for k in ['nx','ny','nz']]
  assert r['reference']==('exact-cylinder-masked-lattice' if cfg['axis']=='time' else 'continuum-cylinder-mode')
  assert len(h['spacing'])==3 and all(math.isfinite(x) and x>0 for x in h['spacing']) and math.isfinite(h['dt']) and h['dt']>0
  assert all(abs(s*d/l-1)<1e-6 for s,d,l in zip(h['spacing'],ds,c['lengths'])) and abs(h['dt']*cfg['steps']/duration-1)<1e-6
  assert [f['step'] for f in h['frames']]==[i*cfg['steps']//8 for i in range(9)]
  count=math.prod(ds)
  labels=[]
  for k in range(ds[2]):
   for j in range(ds[1]):
    for i in range(ds[0]):
     x=(i+.5)*h['spacing'][0]-c['centre'][0];y=(j+.5)*h['spacing'][1]-c['centre'][1]
     labels.append(0 if x*x+y*y<c['radius']**2 else -1)
  assert raw['inside']==[int(q>=0) for q in labels]
  assert len(raw['faces'])==6*count and all(math.isfinite(x) for x in raw['faces'])
  offsets=[[-1,0,0],[1,0,0],[0,-1,0],[0,1,0],[0,0,-1],[0,0,1]]
  for index,label in enumerate(labels):
   if label<0:continue
   xyz=[index%ds[0],index//ds[0]%ds[1],index//(ds[0]*ds[1])]
   for side,offset in enumerate(offsets):
    neighbor=[x+d for x,d in zip(xyz,offset)]
    active=all(0<=x<n for x,n in zip(neighbor,ds)) and labels[neighbor[0]+ds[0]*(neighbor[1]+ds[1]*neighbor[2])]>=0
    assert raw['faces'][side*count+index]==(-1 if active else 0)
  for frame in h['frames']:
   for field,offset in zip(['p','u','v','w'],[-1,0,1,2]):
    shape=[d+(axis==offset) for axis,d in enumerate(ds)]
    assert len(frame[field])==math.prod(shape) and all(math.isfinite(x) for x in frame[field])
  for frame in h['frames']:
   for index,label in enumerate(labels):
    if label<0:assert abs(frame['p'][index]-100)<1e-6
  e=r['errors'];assert abs(e['geometryVolumeError']-abs(sum(q>=0 for q in labels)*math.prod(h['spacing'])/(math.pi*c['radius']**2*c['lengths'][2])-1))<1e-14
  assert len(e['fieldL2'])==4 and all(math.isfinite(x) and x>=0 for x in e['fieldL2'])
  assert all(math.isfinite(v) and v>=0 for k,v in e.items() if k!='fieldL2')
 for axis in ['space','time']:
  report=[q for q in checks if q['case']==c['id'] and q['axis']==axis]
  assert len(report)==1 and report[0]['status']==('reference' if a.reference else 'passed')
  if not a.reference:
   orders=ast.literal_eval(report[0]['orders']);assert len(orders)==4 and all(len(row)==2 and all(math.isfinite(x) and (axis=="space" or 1.7<=x<=2.3) for x in row) for row in orders)
   series=[r for r in runs if r['resolution']['axis']==axis]
   for field,row in enumerate(orders):
    for i,order in enumerate(row):
     ratio=series[i+1]['resolution']['nx']/series[i]['resolution']['nx'] if axis=='space' else series[i]['history']['fields']['dt']/series[i+1]['history']['fields']['dt']
     computed=math.log(series[i]['errors']['fieldL2'][field]/series[i+1]['errors']['fieldL2'][field])/math.log(ratio)
     assert abs(order-computed)<1e-12
   if axis=='space':
    for field in range(4):assert .5<=math.log(series[0]['errors']['fieldL2'][field]/series[2]['errors']['fieldL2'][field])/math.log(4)<=2.5
   e=series[-1]['errors'];assert max(e['fieldL2'])<(.03 if axis=='space' else .01) and e['maxPressure']<(.10 if axis=='space' else .03) and e['maxVelocity']<(.10 if axis=='space' else .03) and e['energyBudget']<1e-4 and e['initialEnergyError']<(.01 if axis=='space' else .02) and e['boundaryVelocity']<1e-6 and e['inactivePreservationError']<1e-6 and e['geometryVolumeError']<(.005 if axis=='space' else .02)
with (a.output/'summary.csv').open() as f:rows=list(csv.DictReader(f))
assert len(rows)==len(results)
for row,r in zip(rows,results):
 assert (row['model'],row['case'],row['status'],row['reference'])==(r['model'],r['specification']['id'],r['status'],r['reference'])
 if r.get('errors'):
  e=r['errors']
  for col,value in zip(['pressure_relative_l2','ux_relative_l2','uy_relative_l2','uz_relative_l2'],e['fieldL2']):assert float(row[col])==value
  for col,key in [('max_pressure_normalized','maxPressure'),('max_velocity_normalized','maxVelocity'),('energy_budget_normalized','energyBudget'),('initial_energy_error','initialEnergyError'),('boundary_velocity_normalized','boundaryVelocity'),('inactive_preservation_error','inactivePreservationError'),('geometry_relative_volume_error','geometryVolumeError')]:assert float(row[col])==e[key]
print(f'PASS complete cylindrical reports: {len(results)} records; all three velocities retained; unsupported cases are not passes')
