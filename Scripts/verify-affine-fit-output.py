#!/usr/bin/env python3
"""Independent exact rational reference over all native coordinates and outputs."""
import argparse,importlib.util,json,math,struct,sys
from fractions import Fraction
from pathlib import Path
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('original_audit',Path(__file__).with_name('verify-affine-fit-audit.py'));audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
EPS=2**-52

def need(ok,message):
 if not ok:raise ValueError(message)
def scalar(v):return audit.scalar(v)
def vector(v):return audit.vector(v)
def rounded(q):
 try:return float(q)
 except OverflowError:return math.copysign(math.inf,1 if q>0 else -1)
def close(actual,reference,scale,ulps=128):
 need(math.isfinite(actual) and math.isfinite(reference),'nonfinite supported result')
 bound=max(4*math.ulp(reference),ulps*EPS*scale)
 need(abs(actual-reference)<=bound,f'accuracy {actual} != {reference} bound {bound}')
def exact(x,y):
 xs=list(map(Fraction.from_float,x));ys=list(map(Fraction.from_float,y));n=len(xs);sx=sum(xs);sy=sum(ys);sxx=sum(a*a for a in xs);sxy=sum(a*b for a,b in zip(xs,ys));den=n*sxx-sx*sx
 if den==0:return None
 m=(n*sxy-sx*sy)/den;b=(sy-m*sx)/n
 return m,b,xs,ys

def extra_inputs():
 d={}
 for ex in [-1000,-600,-100,0,100,600,1000]:
  for ey in [-1000,-600,-100,0,100,600,1000]:
   for rev in [False,True]:
    sx=math.ldexp(1,ex);sy=math.ldexp(1,ey);x=[a*sx for a in [-2.,-1,0,1,2]];y=[a*sy for a in [-2.,0,2,4,6]]
    if rev:x.reverse();y.reverse()
    d[f'scale/{ex}/{ey}/{str(rev).lower()}']=(x,y)
 h=sys.float_info.max;t=math.ulp(0.0)
 d.update({'extreme/opposite':([-h,0,h],[-h/2,0,h/2]),'extreme/translated':([h,h/2],[h/2,h/4]),'extreme/subnormal':([0,t,2*t],[0,t,2*t]),'extreme/normalization-x':([0,1e-300,1e300],[0,1,2]),'extreme/normalization-y':([0,1,2,3,4],[1e-300,1e300,-2e300,1e300,0]),'extreme/repeated':([0,0,1,1],[1,1,3,3]),'extreme/zero-covariance':([0,1e-100,2e-100],[1e300,-1e300,1e300]),'failure/empty':([],[]),'failure/count':([1,2],[1]),'failure/nan':([1,math.nan],[1,2]),'failure/infinity':([1,2],[1,math.inf]),'failure/rank':([2,2],[1,3]),'failure/slope-overflow':([0,t],[0,1]),'failure/slope-underflow':([0,h],[0,t])})
 return d
KNOWN_ERRORS={'extreme/normalization-x':'unrepresentableNormalization','extreme/normalization-y':'unrepresentableNormalization','failure/empty':'invalidDimensions','failure/count':'invalidDimensions','failure/nan':'nonFiniteInput','failure/infinity':'nonFiniteInput','failure/rank':'rankDeficient','failure/slope-overflow':'unrepresentableCoefficient','failure/slope-underflow':'unrepresentableCoefficient'}
def verify_records(records,originals):
 audit.verify(originals)
 inputs={'audit/'+c['id']:(vector(c['x']),vector(c['y'])) for c in originals};inputs.update(extra_inputs());ids=[c['id'] for c in records]
 need(len(ids)==len(set(ids)) and set(ids)==set(inputs),'complete unique 300-case tree')
 successes=failures=predictions=0;max_relative=0
 for c in records:
  x=vector(c['x']);y=vector(c['y']);expected_x,expected_y=inputs[c['id']]
  if c['id'].startswith('scale/'):
   _,ex,ey,rev=c['id'].split('/');need(c['parameters']=={'ex':int(ex),'ey':int(ey),'reversed':rev=='true'},'scale parameter identity')
  else:need(c['parameters']=={},'unexpected case parameters')
  need(len(x)==len(expected_x) and len(y)==len(expected_y),'complete input dimensions')
  need(all(a==b or (math.isnan(a) and math.isnan(b)) for a,b in zip(x+y,expected_x+expected_y)),'independent exact input identity')
  error=KNOWN_ERRORS.get(c['id'])
  ref=None
  if not error:
   ref=exact(x,y)
   if ref is None:error='rankDeficient'
   else:
    m,b,xs,ys=ref;rm=rounded(m)
    if not math.isfinite(rm) or (rm==0 and m!=0):error='unrepresentableCoefficient'
  if error:
   need(c.get('error')==error,'checked rank/finite/representation failure');failures+=1;continue
  need('error' not in c,'unexpected rejected supported fit')
  successes+=1;m,b,xs,ys=ref;rm=rounded(m);origin=scalar(c['origin']);anchor=scalar(c['valueAtOrigin']);slope=scalar(c['slope'])
  need(c['count']==len(x) and math.isfinite(origin),'count/origin ownership')
  if rm==0:need(slope==0,'exact zero covariance slope')
  else:close(slope,rm,abs(rm),ulps=128);max_relative=max(max_relative,abs(slope-rm)/abs(rm))
  sy=max(map(abs,y));close(anchor,rounded(m*Fraction.from_float(origin)+b),sy)
  need(scalar(c['normalizedVariance'])>0,'positive normalized native variance')
  ratio=scalar(c['covarianceCancellationRatio']);need(ratio>=1 and not math.isnan(ratio),'conditioning diagnostic')
  need(len(c['predictions'])==len(x),'complete query tree')
  for q,a,fa in zip(c['predictions'],x,xs):
   need(scalar(q['x'])==a,'query coordinate identity');expected=rounded(m*fa+b)
   if math.isfinite(expected):
    need('value' in q,'supported prediction rejected');close(scalar(q['value']),expected,max(sy,abs(expected)),ulps=256)
   else:need(q.get('error')=='unrepresentablePrediction','prediction overflow failure')
   predictions+=1
  ri=rounded(b)
  if math.isfinite(ri):
   # Intercept is extrapolation from the returned rounded slope/anchor. Its error
   # includes coefficient rounding amplified by the origin; avoid a false relative
   # accuracy claim when the true intercept is near zero.
   need('intercept' in c,'representable intercept missing');scale=max(sy,abs(ri),abs(slope*origin) if math.isfinite(slope*origin) else sy)
   close(scalar(c['intercept']),ri,scale,ulps=256)
  else:need(c.get('interceptError')=='unrepresentablePrediction','intercept representation failure')
  need(len(c['crossings'])==3,'complete crossing queries')
  for q,value in zip(c['crossings'],[y[0],y[len(y)//2],y[-1]]):
   need(scalar(q['y'])==value,'crossing value identity')
   if slope==0:need(q.get('error')=='constantFit','noninvertible constant fit');continue
   # Independently invert the public rounded line; crossing promises this line,
   # not an unrounded exact-real OLS slope hidden from the caller.
   coord=Fraction.from_float(origin)+(Fraction.from_float(value)-Fraction.from_float(anchor))/Fraction.from_float(slope);target=rounded(coord)
   if math.isfinite(target):need('coordinate' in q,'representable crossing missing');close(scalar(q['coordinate']),target,max(map(abs,x)),ulps=256)
   else:need(q.get('error')=='unrepresentableCoordinate','crossing overflow failure')
 return {'cases':len(records),'successfulFits':successes,'checkedFailures':failures,'completePredictions':predictions,'maximumRelativeSlopeError':max_relative}

def verify(root,metadata=True):
 root=Path(root);originals=json.loads((root/'original-audit.json').read_text());records=json.loads((root/'shared.json').read_text());summary=verify_records(records,originals)
 if metadata:
  env=json.loads((root/'environment.json').read_text());need(env['workingTreeDirty'] is False,'dirty producer')
  pins=json.loads((root/'consumer-Package.resolved').read_text())['pins'];need(len(pins)==1 and pins[0]['state']['revision']==env['candidate'],'exact fetched public source pin')
  links=(root/'linkage.txt').read_text();need(not any('/'+name+'.framework/' in links for name in ['Metal','MetalKit','AppKit','SwiftUI','Accelerate']),'unexpected numeric framework dependency')
 return summary
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('output',type=Path);p.add_argument('--preliminary',action='store_true');a=p.parse_args()
 try:
  summary=verify(a.output,not a.preliminary);(a.output/'verification.json').write_text(json.dumps(summary,indent=2,sort_keys=True)+'\n');print('PASS independent exact native affine references',summary)
 except (ValueError,KeyError,TypeError,IndexError) as e:raise SystemExit('FAIL affine reference: '+str(e))
