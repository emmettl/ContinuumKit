#!/usr/bin/env python3
"""Audit complete coupled fields, geometry, stepwise wall work and declared refinements.

Swift's independent continuum/graph oracle evaluates complete field norms; this second
validator independently reconstructs geometry, energy and the retained wall-work trace.
"""
import argparse,ast,csv,gzip,json,math,struct
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--unsupported',action='store_true');a=p.parse_args()
def read(name):
 f=a.output/name
 if f.exists():return json.loads(f.read_text())
 with gzip.open(str(f)+'.gz','rt') as stream:return json.load(stream)
cases=read('cases.json');results=read('results.json');reports=read('conformance.json');env=read('environment.json')
assert len(cases)==1
c=cases[0];g=c['geometry'];assert c['version']==1 and c['id']=='coupled-absorbing-cylinder-xi3' and c['impedance']==3
assert g=={'version':1,'id':'rigid-cylinder','lengths':[.25,.25,.125],'centre':[.125,.125],'radius':.09375,'radialRoot':3.8317059702075123,'density':1.25,'speed':320,'amplitude':1,'inactivePressure':100}
assert all(r['environment']==env and r['specification']==c and r['schemaVersion']==1 for r in results)
if a.unsupported:
 assert len(results)==1 and results[0]['status']=='unsupported' and results[0]['reason']
 assert all(results[0].get(k) is None for k in ['resolution','history','errors'])
 assert len(reports)==1 and reports[0]['status']=='unsupported' and reports[0]['reason']
else:
 assert len(results)==6 and len(reports)==2
 duration=.00041047560726976465947
 def steps(n,cfl):return 8*math.ceil(duration*320*math.sqrt(3)*n/.25/cfl/8)
 expected=[('space',n,n,n//2,steps(64,.2)) for n in [16,32,64]]+[('time',32,32,16,steps(32,cfl)) for cfl in [.8,.4,.2]]
 assert [(r['resolution']['axis'],*[r['resolution'][k] for k in ['nx','ny','nz','steps']]) for r in results]==expected
 def f32(x):return struct.unpack('f',struct.pack('f',x))[0]
 for r in results:
  assert r['status']==('reference' if a.reference else 'supported') and r.get('reason') is None
  cfg=r['resolution'];h=r['history'];fields=h['fields'];d=fields['spacing'];dt=fields['dt'];ds=[cfg[k] for k in ['nx','ny','nz']];nx,ny,nz=ds;count=math.prod(ds);vol=math.prod(d)
  assert r['reference']==('continuous-damped-masked-graph' if cfg['axis']=='time' else 'continuum-robin-bessel-mode')
  assert len(d)==3 and all(abs(x*n/l-1)<1e-6 for x,n,l in zip(d,ds,g['lengths']))
  assert dt>0 and abs(dt*cfg['steps']/duration-1)<1e-6 and h['layoutDt']>0 and abs(h['materialImpedance']/3-1)<1e-6
  flags=[int(((i%nx+.5)*d[0]-.125)**2+((i//nx%ny+.5)*d[1]-.125)**2<.09375**2) for i in range(count)]
  assert h['inside']==flags and len(h['faces'])==len(h['layoutFaces'])==6*count
  raw=list(map(f32,h['layoutFaces']));scaled=list(map(f32,h['faces']));rates=[0.0]*count;area=0.0;local=0.0;walls=[]
  offsets=[(-1,0,0),(1,0,0),(0,-1,0),(0,1,0),(0,0,-1),(0,0,1)]
  for cell,inside in enumerate(flags):
   if not inside:continue
   xyz=[cell%nx,cell//nx%ny,cell//(nx*ny)];wall=False
   for side,offset in enumerate(offsets):
    other=[x+t for x,t in zip(xyz,offset)];active=all(0<=x<n for x,n in zip(other,ds)) and flags[other[0]+nx*(other[1]+ny*other[2])]
    index=side*count+cell;beta=raw[index];value=scaled[index]
    assert math.isfinite(beta) and math.isfinite(value)
    if active:assert beta==value==-1
    elif side>=4:assert beta==value==0
    else:
     wall=True;full=320*h['layoutDt']/(6*d[side//2]);assert 0<beta<=full*(1+1e-6)
     assert abs(value-beta*dt/h['layoutDt'])<max(1e-12,abs(value)*2e-6)
     xy=[(xyz[j]+.5)*d[j]-.125 for j in [0,1]];xy[side//2]+=(.5 if side%2 else -.5)*d[side//2]
     ideal=f32(full*math.hypot(*xy)/sum(map(abs,xy)));local=max(local,abs(beta/ideal-1))
     area+=2*beta*vol*3/(320*h['layoutDt']);rates[cell]+=2*value/dt
   if wall:walls.append(cell)
  assert h['wallCells']==walls
  captures=[i*cfg['steps']//8 for i in range(9)];assert [f['step'] for f in fields['frames']]==captures
  assert len(h['dissipation'])==9 and h['dissipation'][0]==0 and all(math.isfinite(w) and w>=0 for w in h['dissipation'])
  assert all(x>=y-1e-18 for x,y in zip(h['dissipation'][1:],h['dissipation']))
  budget=0.0;e0=None
  for capture,frame in enumerate(fields['frames']):
   for field,axis in zip(['p','u','v','w'],[-1,0,1,2]):
    shape=[n+(j==axis) for j,n in enumerate(ds)];assert len(frame[field])==math.prod(shape) and all(math.isfinite(x) for x in frame[field])
    for index,value in enumerate(frame[field]):
     xyz=[index%shape[0],index//shape[0]%shape[1],index//(shape[0]*shape[1])]
     if axis<0:
      if not flags[index]:assert abs(value-100)<1e-6
     else:
      left=list(xyz);left[axis]-=1
      valid=all(0<=q<n for q,n in zip(xyz,ds)) and all(0<=q<n for q,n in zip(left,ds))
      active=valid and flags[xyz[0]+nx*(xyz[1]+ny*xyz[2])] and flags[left[0]+nx*(left[1]+ny*left[2])]
      if not active:assert abs(value)*400<1e-6
   energy=sum(value*value for value,flag in zip(frame['p'],flags) if flag)*vol/(2*1.25*320**2)
   for axis,field in enumerate(['u','v','w']):
    shape=list(ds);shape[axis]+=1;stride=[1,nx,nx*ny][axis]
    for index,velocity in enumerate(frame[field]):
     xyz=[index%shape[0],index//shape[0]%shape[1],index//(shape[0]*shape[1])]
     if not all(0<=q<n for q,n in zip(xyz,ds)) or xyz[axis]==0:continue
     plus=xyz[0]+nx*(xyz[1]+ny*xyz[2])
     if not flags[plus] or not flags[plus-stride]:continue
     future=velocity-dt*(frame['p'][plus]-frame['p'][plus-stride])/(1.25*d[axis])
     energy+=1.25*vol*velocity*future/2
   assert energy>0 and math.isfinite(energy)
   if e0 is None:e0=energy
   budget=max(budget,abs(energy+h['dissipation'][capture]-e0)/e0)
  e=r['errors'];assert len(e['fieldL2'])==4 and all(math.isfinite(x) and x>=0 for x in e['fieldL2'])
  assert all(math.isfinite(x) and x>=0 for k,x in e.items() if k!='fieldL2')
  assert abs(e['energyBudget']-budget)<1e-12 and abs(e['areaRelativeError']-abs(area/(2*math.pi*.09375*.125)-1))<1e-12 and abs(e['localWeightError']-local)<1e-12
  assert abs(e['initialEnergyError']-abs(e0/1.2294217641745638498e-9-1))<1e-12
  assert e['finalDissipationJ']==h['dissipation'][-1]
  if a.reference:assert h.get('wallPressures') is None
  else:
   trace=h['wallPressures'];assert len(trace)==cfg['steps']+1 and all(len(row)==len(walls) and all(math.isfinite(v) for v in row) for row in trace)
   work=0.0;capture=0
   for step,row in enumerate(trace):
    if step:
     work+=sum(dt*vol*rates[cell]*((x+y)/2)**2/(1.25*320**2) for cell,x,y in zip(walls,row,trace[step-1]))
    if captures[capture]==step:
     assert abs(h['dissipation'][capture]-work)/1.2294217641745638498e-9<1e-9
     assert all(abs(p-fields['frames'][capture]['p'][cell])<1e-6 for cell,p in zip(walls,row))
     if capture<8:capture+=1
   assert e['energyBudget']<1e-4 and e['boundaryVelocity']<1e-6 and e['inactivePreservation']<1e-6 and e['initialStateError']<1e-6
 for axis in ['space','time']:
  series=[r for r in results if r['resolution']['axis']==axis];report=[q for q in reports if q['axis']==axis];assert len(series)==3 and len(report)==1
  report=report[0];assert report['case']==c['id'] and report['status']==('reference' if a.reference else 'passed')
  if a.reference:continue
  e=series[-1]['errors'];assert all(x<(.05 if axis=='space' else .01) for x in e['fieldL2'])
  assert e['maxPressure']<(.10 if axis=='space' else .03) and e['maxVelocity']<(.10 if axis=='space' else .03)
  assert e['workError']<(.03 if axis=='space' else .002) and e['initialEnergyError']<(.03 if axis=='space' else .06)
  assert e['geometryVolumeError']<(.005 if axis=='space' else .02) and e['areaRelativeError']<.005 and e['localWeightError']<.01 and e['finalDissipationJ']>0
  orders=ast.literal_eval(report['orders']);assert len(orders)==4 and all(len(row)==2 for row in orders)
  for field,row in enumerate(orders):
   errors=[r['errors']['fieldL2'][field] for r in series]
   for i,order in enumerate(row):
    ratio=series[i+1]['resolution']['nx']/series[i]['resolution']['nx'] if axis=='space' else series[i]['history']['fields']['dt']/series[i+1]['history']['fields']['dt']
    assert abs(order-math.log(errors[i]/errors[i+1])/math.log(ratio))<1e-12
   if axis=='time':assert all(1.7<=order<=2.3 for order in row)
   else:assert .5<=math.log(errors[0]/errors[2])/math.log(4)<=2.5
with (a.output/'summary.csv').open() as f:rows=list(csv.DictReader(f))
assert len(rows)==len(results) and all(row['status']==r['status'] and row['case']==r['specification']['id'] for row,r in zip(rows,results))
print(f'PASS complete coupled absorbing-cylinder fields and work: {len(results)} records')
