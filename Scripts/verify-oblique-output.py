#!/usr/bin/env python3
"""Require complete oblique-mode fields, fitted reflection and work refinement, or explicit unsupported cases."""
import argparse,ast,csv,gzip,json,math
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--unsupported',action='store_true');a=p.parse_args()
def read(name):
 f=a.output/name
 if f.exists():return json.loads(f.read_text())
 with gzip.open(str(f)+'.gz','rt') as stream:return json.load(stream)
cases=read('cases.json');results=read('results.json');checks=read('conformance.json')
assert [(c['id'],c['impedance']) for c in cases]==[('positive-oblique',3),('inverted-oblique',.5)]
assert len(results)==(2 if a.unsupported else 12)
gold={3:(25.2286102042480187,-2.0321333081312975,-461.0672311031544,-11386.26324994717,.36160025261824914,-.017346410623760986),.5:(31.3781351977367685,-1.6500617441026332,-412.25598140175063,-12860.572929124806,-.4381432331100583,-.008279995013423546)}
for c in cases:
 assert c['version']==1 and (c['lengthX'],c['lengthY'],c['density'],c['speed'],c['amplitude'])==(.25,.125,1.25,320,1)
 runs=[r for r in results if r['specification']==c];g=gold[c['impedance']];duration=2*math.pi/abs(g[3])
 for r in runs:
  params=r['parameters']
  values=(params['kx']['real'],params['kx']['imag'],params['rate']['real'],params['rate']['imag'],params['reflection']['real'],params['reflection']['imag'])
  assert all(abs(x-y)<2e-7 for x,y in zip(values,g)) and abs(params['duration']/duration-1)<1e-12
  assert params['initialEnergy']>0 and math.isfinite(params['initialEnergy'])
 if a.unsupported:
  assert len(runs)==1 and runs[0]['status']=='unsupported' and runs[0]['reason'] and all(runs[0].get(k) is None for k in ['resolution','history','errors'])
  report=[q for q in checks if q['case']==c['id']];assert len(report)==1 and report[0]['status']=='unsupported' and report[0]['reason'];continue
 def count(n,cfl):return 8*math.ceil(duration*320*math.hypot(n/.25,(n//2)/.125)/cfl/8)
 expected=[('space',n,n//2,count(384,.25)) for n in (96,192,384)]+[('time',64,32,count(64,cfl)) for cfl in (.7,.35,.175)]
 assert [(r['resolution']['axis'],r['resolution']['nx'],r['resolution']['ny'],r['resolution']['steps']) for r in runs]==expected
 for r in runs:
  assert r['schemaVersion']==1 and r['status']==('reference' if a.reference else 'supported')
  cfg=r['resolution'];h=r['history'];nx,ny,steps=cfg['nx'],cfg['ny'],cfg['steps']
  assert r['reference']==('fixed-spatial-oblique-matrix-exponential' if cfg['axis']=='time' else 'continuum-damped-oblique-mode')
  assert all(math.isfinite(h[k]) and h[k]>0 for k in ['dx','dy','dt']) and abs(h['dx']*nx/.25-1)<1e-6 and abs(h['dy']*ny/.125-1)<1e-6 and abs(h['dt']*steps/duration-1)<1e-6
  assert [f['step'] for f in h['frames']]==[i*steps//8 for i in range(9)]
  last=0
  for f in h['frames']:
   assert [len(f[k]) for k in ['p','u','v']]==[nx*ny,(nx+1)*ny,nx*(ny+1)]
   assert all(math.isfinite(x) for k in ['p','u','v'] for x in f[k]) and math.isfinite(f['dissipation']) and f['dissipation']>=last
   last=f['dissipation']
  e=r['errors'];assert len(e['fieldL2'])==3 and all(math.isfinite(x) and x>=0 for x in e['fieldL2'])
  assert all(math.isfinite(x) for x in e['fittedReflection'].values())
  assert all(math.isfinite(v) and v>=0 for k,v in e.items() if k not in ['fieldL2','fittedReflection'])
 for axis in ['space','time']:
  report=[q for q in checks if q['case']==c['id'] and q['axis']==axis]
  assert len(report)==1 and report[0]['status']==('reference' if a.reference else 'passed')
  if a.reference:continue
  orders=ast.literal_eval(report[0]['orders']);assert len(orders)==4 and all(len(row)==2 for row in orders)
  low=.8 if axis=='space' else 1.7
  assert all(low<=value<=2.3 for row in orders for value in row)
  series=[r for r in runs if r['resolution']['axis']==axis]
  for metric,row in enumerate(orders):
   for i,order in enumerate(row):
    ea=series[i]['errors']['dissipationError'] if metric==3 else series[i]['errors']['fieldL2'][metric]
    eb=series[i+1]['errors']['dissipationError'] if metric==3 else series[i+1]['errors']['fieldL2'][metric]
    ratio=series[i+1]['resolution']['nx']/series[i]['resolution']['nx'] if axis=='space' else series[i]['history']['dt']/series[i+1]['history']['dt']
    assert abs(order-math.log(ea/eb)/math.log(ratio))<1e-12
  e=series[-1]['errors'];assert max(e['fieldL2'])<.02 and e['maxPressure']<.03 and e['maxVelocity']<.03 and e['energyBudget']<1e-4 and e['initialEnergyError']<.01 and e['boundaryVelocity']<1e-6
  assert e['dissipationError']<(.001 if axis=='time' else .02)
  if axis=='space':assert e['reflectionError']<.02 and e['fitResidual']<.02
with (a.output/'summary.csv').open() as f:rows=list(csv.DictReader(f))
assert len(rows)==len(results)
for row,r in zip(rows,results):
 assert (row['model'],row['case'],row['status'],row['reference'])==(r['model'],r['specification']['id'],r['status'],r['reference'])
 if r.get('errors'):
  e=r['errors']
  for col,value in zip(['pressure_relative_l2','ux_relative_l2','uy_relative_l2'],e['fieldL2']):assert float(row[col])==value
  mapping={'max_pressure_normalized':'maxPressure','max_velocity_normalized':'maxVelocity','energy_budget_normalized':'energyBudget','initial_energy_error':'initialEnergyError','boundary_velocity_normalized':'boundaryVelocity','dissipation_error_normalized':'dissipationError','reflection_error':'reflectionError','fit_residual':'fitResidual'}
  for col,key in mapping.items():assert float(row[col])==e[key]
  assert float(row['reflection_real'])==e['fittedReflection']['real'] and float(row['reflection_imag'])==e['fittedReflection']['imag']
print(f'PASS complete oblique reports: {len(results)} records; unsupported capability checks are not numerical passes')
