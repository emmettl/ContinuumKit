#!/usr/bin/env python3
"""Exact rational OLS on the actual native binary64 coordinates, not paired equality."""
import argparse,hashlib,json,math,struct
from fractions import Fraction
from pathlib import Path

def need(ok,msg):
 if not ok:raise ValueError(msg)
def scalar(v):
 x=float(v['value']);encoded=int(v['bits'],16);bits=int.from_bytes(struct.pack('>d',x),'big')
 if math.isnan(x):need((encoded&0x7ff0000000000000)==0x7ff0000000000000 and encoded&0xfffffffffffff,'NaN representation')
 else:need(bits==encoded,'scalar native identity')
 return x
def vector(v):
 need(len(v['values'])==len(v['bits']),'complete native vector')
 return [scalar({'value':x,'bits':b}) for x,b in zip(v['values'],v['bits'])]
def expected():
 cases={}
 for n in [2,3,8,17,64,257]:
  for offset in [0,1000,10**6,10**9,2**40,2**53]:
   for p in ['line','perturbed','constant']:cases[f'index/{n}/{offset}/{p}']={'kind':'index','count':n,'offset':offset,'profile':p}
 for n in [3,8,17,64,480,4800]:
  for first in [0,480,48000,480000]:
   for rate in [8000,48000]:
    for p in (['decay-window'] if n>64 else ['line','perturbed']):cases[f'time/{n}/{first}/{rate}/{p}']={'kind':'time','count':n,'first':first,'rate':rate,'profile':p}
 return cases
def verify(records):
 cases=expected();ids=[c['id'] for c in records];need(len(ids)==len(set(ids)) and set(ids)==set(cases),'complete unique case tree')
 outcomes=[]
 for c in records:
  need(all(c[k]==v for k,v in cases[c['id']].items()),'case identity')
  n=c['count'];p=c['profile'];x=vector(c['x']);y=vector(c['y'])
  need(len(x)==len(y)==n,'full native inputs')
  expected_x=[float(i+c['offset']) if c['kind']=='index' else float(i+c['first'])/float(c['rate']) for i in range(n)]
  expected_y=[-10.0 if p=='constant' else -5-30*float(i)/float(n-1) if p=='decay-window' else -10-float(i)/16+(((i*7)%11-5)/128 if p=='perturbed' else 0) for i in range(n)]
  need(x==expected_x and y==expected_y,'independent complete input identity')
  xx=list(map(Fraction.from_float,x));yy=list(map(Fraction.from_float,y));sx=sum(xx);sy=sum(yy);sxx=sum(t*t for t in xx);sxy=sum(a*b for a,b in zip(xx,yy));den=n*sxx-sx*sx
  slope=scalar(c['slope']);intercept=scalar(c['intercept']) if 'intercept' in c else None
  r={'id':c['id'],'exactNativeDeterminant':str(den),'actualSlope':str(slope),'actualIntercept':str(intercept) if intercept is not None else None}
  if den==0:r.update(classification='native_coordinate_rank_failure',referenceSlope=None)
  else:
   exact=(n*sxy-sx*sy)/den;b=(sy-exact*sx)/n;ref=float(exact);reference_b=float(b)
   r.update(referenceSlope=str(ref),exactSlope=str(exact),referenceIntercept=str(reference_b),exactIntercept=str(b))
   if not math.isfinite(slope) or (intercept is not None and not math.isfinite(intercept)):r.update(classification='raw_moment_nonfinite',absoluteSlopeError=None)
   else:
    err=abs(slope-ref);scale=max(abs(ref),1e-300);r.update(absoluteSlopeError=err,relativeSlopeError=err/scale if ref else err)
    prediction=max(abs((Fraction.from_float(slope)-exact)*a+((Fraction.from_float(intercept)-b) if intercept is not None else 0)) for a in xx)
    # Slopes are the common output. Intercept is separately audited; a slope-only
    # time fit does not imply that evaluation through the origin is meaningful.
    if intercept is not None:r['maximumAffinePredictionError']=str(float(prediction))
    r['classification']='raw_moment_inaccurate' if err>2e-10*max(1,abs(ref)) else 'reference_agreement'
  outcomes.append(r)
 return outcomes
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();records=json.loads((a.output/'original.json').read_text());outcomes=verify(records)
 counts={k:sum(r['classification']==k for r in outcomes) for k in sorted({r['classification'] for r in outcomes})}
 result={'schemaVersion':1,'scope':'original arithmetic audit; numerical failures are findings, not passing shared contracts','reference':'exact Fraction OLS over complete native binary64 coordinates/values','cases':len(outcomes),'classifications':counts,'results':outcomes}
 (a.output/'audit.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 print('PASS complete protected-source audit and independent exact references:',len(outcomes),'cases',counts)
