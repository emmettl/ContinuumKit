#!/usr/bin/env python3
"""Require complete fields, independent plan geometry and ROI norms, all-step work, and explicit gaps."""
import argparse,ast,csv,gzip,json,math,struct
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--unsupported',action='store_true');a=p.parse_args()
def read(name):
 f=a.output/name
 if f.exists():return json.loads(f.read_text())
 with gzip.open(str(f)+'.gz','rt') as stream:return json.load(stream)
cases=read('cases.json');results=read('results.json');reports=read('conformance.json');env=read('environment.json')
assert len(cases)==1;c=cases[0];assert c['id']=='tilted-plan-pulse-xi3' and c['version']==1
assert c['lengths']==[.5,.5,.00390625] and c['normal']==[2/math.sqrt(5),1/math.sqrt(5),0] and c['reflectedDirection']==[-.6,-.8,0]
for key,value in {'intercept':.45,'density':1.25,'speed':320,'amplitude':1,'inactivePressure':100,'impedance':3,'centre':.075,'halfWidth':.04,'travel':.31,'roiYMinimum':.235,'roiYMaximum':.265,'wallClearance':.015,'patchHalfWidth':.018}.items():assert c[key]==value
assert all(r['specification']==c and r['environment']==env and r['schemaVersion']==1 for r in results)
mu=2/math.sqrt(5);reflection=(3*mu-1)/(3*mu+1);E0=3.337860107421875e-10;EP=9.0122222900390625e-12;duration=.31/320
if a.unsupported:
 assert len(results)==1 and results[0]['status']=='unsupported' and results[0]['reason'] and all(results[0].get(k) is None for k in ['history','errors','resolution'])
 assert len(reports)==1 and reports[0]['status']=='unsupported' and reports[0]['reason']
else:
 assert len(results)==6 and len(reports)==2
 def steps(n,cfl):return 8*math.ceil(.31*math.sqrt(2*(n/.5)**2+(2/.00390625)**2)/cfl/8)
 expected=[('space',n,n,2,steps(256,.2)) for n in [64,128,256]]+[('time',64,64,2,steps(64,q)) for q in [.8,.4,.2]]
 assert [(r['resolution']['axis'],*[r['resolution'][k] for k in ['nx','ny','nz','steps']]) for r in results]==expected
 def f32(x):return struct.unpack('f',struct.pack('f',x))[0]
 corners=[(0,0),(.45,0),(.2,.5),(0,.5)]
 def nearest(x,y):
  distances=[]
  for i,v in enumerate(corners):
   w=corners[(i+1)%4];dx=w[0]-v[0];dy=w[1]-v[1];q=max(0,min(1,((x-v[0])*dx+(y-v[1])*dy)/(dx*dx+dy*dy)))
   distances.append(math.hypot(x-v[0]-q*dx,y-v[1]-q*dy))
  return min(range(4),key=lambda i:distances[i])
 def pulse(s):return math.cos(math.pi*s/.08)**4 if abs(s)<.04 else 0
 def observe(x,y):return .05<=x<=.35 and .235<=y<=.265 and (.45-x-y/2)*mu>=.015
 def state(x,y,t):
  inc=pulse(x-.075-320*t);ref=reflection*pulse(-.6*x-.8*y+.72-.075-320*t)
  return [inc+ref,(inc-.6*ref)/400,-.8*ref/400,0]
 for r in results:
  cfg=r['resolution'];h=r['history'];fields=h['fields'];nx,ny,nz=[cfg[k] for k in ['nx','ny','nz']];ds=[nx,ny,nz];count=nx*ny*nz;d=fields['spacing'];dt=fields['dt'];vol=math.prod(d);axis=cfg['axis']
  assert r['status']==('reference' if a.reference else 'supported') or (not a.reference and axis=='space' and r['status']=='gap' and r.get('reason'))
  assert r['reference']==('causal-plane-pulse-region' if axis=='space' else 'fixed-finite-plan-graph')
  assert len(d)==3 and all(abs(x*n/l-1)<1e-6 for x,n,l in zip(d,ds,c['lengths'])) and dt>0 and abs(dt*cfg['steps']/duration-1)<1e-6
  assert h['layoutDt']>0 and abs(h['materialImpedance']/3-1)<1e-6
  flags=[int((i%nx+.5)*d[0]+(i//nx%ny+.5)*d[1]/2<.45) for i in range(count)]
  assert h['inside']==flags and len(h['faces'])==len(h['layoutFaces'])==6*count
  raw=list(map(f32,h['layoutFaces']));scaled=list(map(f32,h['faces']));rates=[0.0]*count;patch=[0.0]*count;wall=[];area=0.0;coef=0.0
  offsets=[(-1,0,0),(1,0,0),(0,-1,0),(0,1,0),(0,0,-1),(0,0,1)]
  def active(xyz):return all(0<=x<n for x,n in zip(xyz,ds)) and flags[xyz[0]+nx*(xyz[1]+ny*xyz[2])]
  for cell,flag in enumerate(flags):
   if not flag:continue
   xyz=[cell%nx,cell//nx%ny,cell//(nx*ny)];has_wall=False
   for side,offset in enumerate(offsets):
    other=[x+t for x,t in zip(xyz,offset)];index=side*count+cell;beta=raw[index];v=scaled[index]
    assert math.isfinite(beta) and math.isfinite(v)
    x=(xyz[0]+.5)*d[0];y=(xyz[1]+.5)*d[1]
    if side<2:x+=(.5 if side%2 else -.5)*d[0]
    elif side<4:y+=(.5 if side%2 else -.5)*d[1]
    if active(other):assert beta==v==-1
    elif side>=4 or nearest(x,y)!=1:assert beta==v==0
    else:
     has_wall=True;ideal=f32(320*h['layoutDt']/(6*d[side//2]*(3/math.sqrt(5))))
     assert beta>0 and abs(v-beta*dt/h['layoutDt'])<max(1e-12,abs(v)*2e-6)
     coef=max(coef,abs(beta/ideal-1));area+=2*beta*vol*3/(320*h['layoutDt']);rates[cell]+=2*v/dt
     distance=(2*x+y-.9)/math.sqrt(5);yp=y-distance/math.sqrt(5);w=math.cos(math.pi*(yp-.25)/.036)**4 if abs(yp-.25)<.018 else 0
     patch[cell]+=2*v/dt*w
   if has_wall:wall.append(cell)
  assert h['wallCells']==wall and coef<2e-6
  captures=[i*cfg['steps']//8 for i in range(9)];assert [f['step'] for f in fields['frames']]==captures
  assert len(h['patchDissipation'])==9 and h['patchDissipation'][0]==0 and all(math.isfinite(w) and w>=0 for w in h['patchDissipation'])
  budget=0.0;initial=None;squares=[0.0]*3;norms=[0.0]*3;maxP=0.0;maxV=0.0
  for capture,frame in enumerate(fields['frames']):
   for field,fd in enumerate(['p','u','v','w']):
    shape=list(ds)
    if field:shape[field-1]+=1
    assert len(frame[fd])==math.prod(shape) and all(math.isfinite(x) for x in frame[fd])
    for index,value in enumerate(frame[fd]):
     xyz=[index%shape[0],index//shape[0]%shape[1],index//(shape[0]*shape[1])];opened=False
     if not field:
      opened=flags[index]
      if not opened:assert abs(value-100)<1e-6
     else:
      left=list(xyz);left[field-1]-=1;opened=active(xyz) and active(left)
      if not opened:assert abs(value)*400<1e-6
      if field==3:assert abs(value)*400<1e-6
     if axis=='space' and field<3 and opened:
      pos=[(xyz[j]+(0 if j+1==field else .5))*d[j] for j in range(3)]
      if observe(*pos[:2]):
       truth=state(*pos[:2],frame['step']*dt-(dt/2 if field else 0))[field];delta=value-truth
       squares[field]+=delta*delta;norms[field]+=truth*truth
       if field:maxV=max(maxV,abs(delta)*400)
       else:maxP=max(maxP,abs(delta))
   energy=sum(v*v for v,flag in zip(frame['p'],flags) if flag)*vol/(2*1.25*320**2)
   for field,fd in enumerate(['u','v','w']):
    shape=list(ds);shape[field]+=1;stride=[1,nx,nx*ny][field]
    for index,v in enumerate(frame[fd]):
     xyz=[index%shape[0],index//shape[0]%shape[1],index//(shape[0]*shape[1])];left=list(xyz);left[field]-=1
     if not active(xyz) or not active(left):continue
     plus=xyz[0]+nx*(xyz[1]+ny*xyz[2]);future=v-dt*(frame['p'][plus]-frame['p'][plus-stride])/(1.25*d[field]);energy+=1.25*vol*v*future/2
   assert energy>0 and math.isfinite(energy)
   if initial is None:initial=energy
   if not a.reference:budget=max(budget,abs(energy+h['dissipation'][capture]-initial)/initial)
  e=r['errors'];assert len(e['fieldL2'])==3 and all(math.isfinite(x) and x>=0 for x in e['fieldL2'])
  assert all(v is None or math.isfinite(v) for k,v in e.items() if k!='fieldL2')
  assert abs(e['initialEnergyError']-abs(initial/E0-1))<1e-12 and abs(e['areaRelativeError']-abs(area/(.5/mu*.00390625)-1))<1e-12 and abs(e['coefficientLayoutError']-coef)<1e-12
  assert abs(e['continuumCoefficient']-reflection)<1e-15
  if axis=='space':
   assert all(abs(e['fieldL2'][f]-math.sqrt(squares[f]/norms[f]))<1e-12 for f in range(3))
   assert abs(e['maxPressure']-maxP)<1e-12 and abs(e['maxVelocity']-maxV)<1e-12
   assert abs(e['referenceCoefficient']-reflection)<1e-15 and e['referenceShift']==0
  if a.reference:assert e.get('energyBudget') is None and h.get('wallPressures') is None
  else:
   assert abs(e['energyBudget']-budget)<1e-12 and budget<1e-4
   assert all(e[key]<1e-6 for key in ['initialStateError','boundaryVelocity','inactivePreservation','zeroZ'])
   trace=h['wallPressures'];assert len(trace)==cfg['steps']+1 and all(len(row)==len(wall) and all(math.isfinite(v) for v in row) for row in trace)
   assert len(h['dissipation'])==9 and h['dissipation'][0]==0
   work=0.0;pw=0.0;capture=0
   for step,row in enumerate(trace):
    if step:
     for cell,x,y in zip(wall,row,trace[step-1]):
      inc=dt*vol*((x+y)/2)**2/(1.25*320**2);work+=inc*rates[cell];pw+=inc*patch[cell]
    if captures[capture]==step:
     assert abs(h['dissipation'][capture]-work)/E0<1e-9 and abs(h['patchDissipation'][capture]-pw)/EP<1e-9
     assert all(abs(p-fields['frames'][capture]['p'][cell])<1e-6 for cell,p in zip(wall,row))
     if capture<8:capture+=1
 for axis in ['space','time']:
  series=[r for r in results if r['resolution']['axis']==axis];report=[q for q in reports if q['axis']==axis];assert len(series)==3 and len(report)==1
  report=report[0];assert report['case']==c['id']
  if a.reference:assert report['status']=='reference';continue
  if axis=='space' and report['status']=='gap':assert report['reason'] and all(r['status']=='gap' and r['reason'] for r in series);continue
  assert report['status']=='passed' and all(r['status']=='supported' for r in series)
  orders=ast.literal_eval(report['orders']);assert len(orders)==3 and all(len(row)==2 for row in orders)
  for field,row in enumerate(orders):
   errors=[r['errors']['fieldL2'][field] for r in series]
   for i,order in enumerate(row):
    ratio=series[i+1]['resolution']['nx']/series[i]['resolution']['nx'] if axis=='space' else series[i]['history']['fields']['dt']/series[i+1]['history']['fields']['dt']
    assert abs(order-math.log(errors[i]/errors[i+1])/math.log(ratio))<1e-12
   if axis=='space':assert .5<=math.log(errors[0]/errors[2])/math.log(4)<=2.5
   else:assert all(1.7<=order<=2.3 for order in row)
  e=series[-1]['errors'];assert all(x<(.10 if axis=='space' else .01) for x in e['fieldL2'])
  assert e['maxPressure']<(.20 if axis=='space' else .03) and e['maxVelocity']<(.20 if axis=='space' else .03) and e['patchWorkError']<(.05 if axis=='space' else .002)
  assert e['initialEnergyError']<.01 and e['areaRelativeError']<(.005 if axis=='space' else .03) and e['geometryVolumeError']<.01
  assert abs(e['reflectedCoefficient']-e['referenceCoefficient'])<(.03 if axis=='space' else .005) and abs(e['pulseShift']-e['referenceShift'])/.04<(.10 if axis=='space' else .005)
  if axis=='time':assert e['globalWorkError']<.002
with (a.output/'summary.csv').open() as f:rows=list(csv.DictReader(f))
assert len(rows)==len(results) and all(row['status']==r['status'] for row,r in zip(rows,results))
print(f'PASS complete tilted pulse reports: {len(results)} records; physical gaps are explicit')
