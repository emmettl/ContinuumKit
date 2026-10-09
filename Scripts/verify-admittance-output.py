#!/usr/bin/env python3
import argparse,ast,csv,gzip,json,math,struct
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--reference',action='store_true');p.add_argument('--unsupported',action='store_true');a=p.parse_args()
def read(name):
 f=a.output/name
 return json.loads(f.read_text()) if f.exists() else json.loads(gzip.decompress(Path(str(f)+'.gz').read_bytes()))
cases=read('cases.json');results=read('results.json');reports=read('conformance.json')
assert [(c['id'],c['kind']) for c in cases]==[('aligned-box-control','alignedBox'),('absorbing-cylinder','cylinder')]
assert len(results)==(2 if a.unsupported else 12)
for c in cases:
 assert c['version']==1 and c['lengths']==[.25,.25,.125] and c['centre']==[.125,.125] and (c['radius'],c['density'],c['speed'],c['amplitude'],c['inactivePressure'],c['impedance'])==(.09375,1.25,320,1,100,3)
 runs=[r for r in results if r['specification']==c]
 if a.unsupported:
  assert len(runs)==1 and all(runs[0][k]=='unsupported' for k in ['status','numericalStatus','physicalStatus']) and runs[0]['reason'] and not runs[0].get('history') and not runs[0].get('errors') and not runs[0].get('resolution')
  assert any(q['case']==c['id'] and q['status']=='unsupported' for q in reports);continue
 expected=[('space',n,n,n//2,.2) for n in [16,32,64]]+[('time',32,32,16,cfl) for cfl in [.8,.4,.2]]
 assert [(r['resolution']['axis'],r['resolution']['nx'],r['resolution']['ny'],r['resolution']['nz'],r['resolution']['courant']) for r in runs]==expected
 for r in runs:
  cfg=r['resolution'];raw=r['history'];raw['faces']=[struct.unpack('f',struct.pack('f',x))[0] for x in raw['faces']];raw['layoutFaces']=[struct.unpack('f',struct.pack('f',x))[0] for x in raw['layoutFaces']];h=raw['fields'];ds=[cfg[k] for k in ['nx','ny','nz']];count=math.prod(ds)
  assert r['schemaVersion']==1 and r['numericalStatus']==('reference' if a.reference else 'passed')
  dt=cfg['courant']*.25/cfg['nx']/(320*math.sqrt(3));assert abs(h['dt']/dt-1)<1e-6
  assert len(h['spacing'])==3 and all(abs(s*n/l-1)<1e-6 for s,n,l in zip(h['spacing'],ds,c['lengths']))
  assert math.isfinite(raw['layoutDt']) and raw['layoutDt']>0 and abs(raw['materialImpedance']/3-1)<1e-6
  labels=[]
  for k in range(ds[2]):
   for j in range(ds[1]):
    for i in range(ds[0]):
     x=(i+.5)*h['spacing'][0]-.125;y=(j+.5)*h['spacing'][1]-.125
     labels.append(int((x*x+y*y<.09375**2) if c['kind']=='cylinder' else (abs(x)<.09375 and abs(y)<.09375)))
  assert raw['inside']==labels and len(raw['faces'])==6*count and len(raw['layoutFaces'])==6*count
  assert all(math.isfinite(x) for x in raw['faces']+raw['layoutFaces'])
  area=0;rates=[0.0]*count;vol=math.prod(h['spacing'])
  offsets=[[-1,0,0],[1,0,0],[0,-1,0],[0,1,0],[0,0,-1],[0,0,1]]
  for cell in range(count):
   if not labels[cell]:continue
   xyz=[cell%ds[0],cell//ds[0]%ds[1],cell//(ds[0]*ds[1])]
   for side,offset in enumerate(offsets):
    other=[x+d for x,d in zip(xyz,offset)];active=all(0<=x<n for x,n in zip(other,ds)) and labels[other[0]+ds[0]*(other[1]+ds[1]*other[2])]
    index=side*count+cell;v=raw['layoutFaces'][index];scaled=raw['faces'][index]
    if active:assert v==scaled==-1
    elif side>=4:assert v==scaled==0
    else:
     beta=320*raw['layoutDt']/(6*h['spacing'][side//2]);assert 0<=v<=beta*(1+1e-6)
     assert abs(scaled-v*h['dt']/raw['layoutDt'])<max(1e-12,abs(scaled)*2e-6)
     area+=2*v*vol*3/(320*raw['layoutDt']);rates[cell]+=2*scaled/h['dt']
  assert [f['step'] for f in h['frames']]==[0,1]
  for frame in h['frames']:
   for field,offset in zip(['p','u','v','w'],[-1,0,1,2]):
    assert len(frame[field])==math.prod([n+(axis==offset) for axis,n in enumerate(ds)]) and all(math.isfinite(x) for x in frame[field])
    if field!='p':assert max(map(abs,frame[field]))*400<1e-6
   for i,flag in enumerate(labels):
    if not flag:assert abs(frame['p'][i]-100)<1e-6
  physical=(2*math.pi*.09375 if c['kind']=='cylinder' else 8*.09375)*.125
  e=r['errors'];assert all(math.isfinite(x) and x>=0 for x in e.values())
  assert abs(e['effectiveArea']/area-1)<1e-12 and abs(e['physicalArea']/physical-1)<1e-12 and abs(e['areaRelativeError']-abs(area/physical-1))<1e-12
  assert abs(e['physicalPrescribedPower']-physical/1200)<1e-15 and abs(e['effectivePrescribedPower']-area/1200)<1e-15
  physical_status='passed' if e['areaRelativeError']<.005 else 'gap';assert r['physicalStatus']==physical_status
  assert r['status']==('reference' if a.reference else 'gap' if physical_status=='gap' else 'supported')
  if physical_status=='gap':assert r['reason']
  p0=h['frames'][0]['p'];p1=h['frames'][1]['p'];er=sum(((-math.log(p1[i]/p0[i])/h['dt']-rates[i])**2) for i in range(count) if labels[i] and rates[i]>0);norm=sum(rate*rate for rate in rates)
  assert abs(e['rateL2']-math.sqrt(er/norm))<1e-12
  if not a.reference:assert e['energyBudget']<1e-5 and e['workRelative']<5e-5 and e['zeroVelocity']<1e-6 and e['inactivePreservation']<1e-6 and e['initialPressureError']<1e-6
 time=[r for r in runs if r['resolution']['axis']=='time'];spatial=[r for r in runs if r['resolution']['axis']=='space']
 t=[q for q in reports if q['case']==c['id'] and q['contract']=='isolated-wall-flow'];s=[q for q in reports if q['case']==c['id'] and q['contract']=='physical-side-area'];assert len(t)==len(s)==1
 assert s[0]['status']==('passed' if all(r['physicalStatus']=='passed' for r in spatial) else 'gap')
 if not a.reference:
  orders=ast.literal_eval(t[0]['orders']);assert len(orders)==2 and all(1.7<=x<=2.3 for x in orders) and t[0]['status']=='passed'
  for i,order in enumerate(orders):assert abs(order-math.log(time[i]['errors']['rateL2']/time[i+1]['errors']['rateL2'])/math.log(time[i]['history']['fields']['dt']/time[i+1]['history']['fields']['dt']))<1e-12
  assert time[-1]['errors']['rateL2']<.002 and time[-1]['errors']['maxRateRelative']<.002
with (a.output/'summary.csv').open() as f:rows=list(csv.DictReader(f))
assert len(rows)==len(results)
for row,r in zip(rows,results):assert all(row[col]==r[key] for col,key in [('model','model'),('status','status'),('numerical_status','numericalStatus'),('physical_status','physicalStatus')])
print(f'PASS complete admittance audit reports: {len(results)} records; physical gaps remain explicit, not conformance passes')
