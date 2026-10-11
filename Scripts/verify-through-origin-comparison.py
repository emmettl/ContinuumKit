#!/usr/bin/env python3
"""Independently check selected one-column QR and scaled-projection comparisons."""
import argparse,copy,importlib.util,json,math,struct,sys
from decimal import Decimal,localcontext
from fractions import Fraction
from pathlib import Path
sys.dont_write_bytecode=True
SCRIPT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('audit',SCRIPT/'through-origin-audit.py');audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
EPS=Fraction(1,2**52)
def require(ok,label):
    if not ok:raise ValueError(label)
def number(bits):return struct.unpack('>d',struct.pack('>Q',int(bits)))[0]
def exact(bits):
    n=number(bits);require(math.isfinite(n),'finite actual binary64 observable');return Fraction(n)
def scaled(x,exponent):return x*Fraction(2)**(-exponent)
def rounded(x):
    try:return float(x)
    except OverflowError:return (-math.inf if x<0 else math.inf)
def decimal(x):return Decimal(x.numerator)/Decimal(x.denominator)
def direct(case):
    xs=[float.fromhex(v) for v in case['x']];ys=[float.fromhex(v) for v in case['y']]
    largest=max(map(abs,xs));ylargest=max(map(abs,ys))
    if not largest:return {'status':'rankDeficient'}
    xe=math.frexp(largest)[1]-1;ye=math.frexp(ylargest)[1]-1 if ylargest else 0
    xn=[math.ldexp(x,-xe) for x in xs];yn=[math.ldexp(y,-ye) for y in ys]
    for old,new,e in [(xs,xn,xe),(ys,yn,ye)]:require(all(math.ldexp(b,e)==a and (a==0 or b!=0) for a,b in zip(old,new)),'lossless prototype normalization')
    squares=[v*v for v in xn];products=[x*y for x,y in zip(xn,yn)]
    den=math.fsum(squares);dot=math.fsum(products);ratio=dot/den
    try:coefficient=math.ldexp(ratio,ye-xe)
    except OverflowError:coefficient=math.inf
    result={'xExponent':xe,'yExponent':ye,'normalizedX':audit.encoded(xn),'normalizedY':audit.encoded(yn),'squares':audit.encoded(squares),'products':audit.encoded(products),'denominator':audit.encoded(den),'dot':audit.encoded(dot),'normalizedCoefficient':audit.encoded(ratio)}
    if not math.isfinite(coefficient) or (ratio!=0 and coefficient==0):result['status']='unrepresentableSolution'
    else:result.update(status='returned',coefficient=audit.encoded(coefficient))
    return result

def verify(inputs,qr):
    cases=audit.cases();require(len(inputs)==len(qr)==len(cases)==90,'complete ninety-case comparison')
    findings=[]
    for case,data,result in zip(cases,inputs,qr):
        require(case['id']==data['id']==result['id'],'exact native case identity')
        xs=[Fraction(float.fromhex(v)) for v in case['x']];ys=[Fraction(float.fromhex(v)) for v in case['y']]
        require([exact(v) for v in data['xBits']]==xs and [exact(v) for v in data['yBits']]==ys,'same actual source-audit coordinates')
        den=sum(x*x for x in xs);dot=sum(x*y for x,y in zip(xs,ys));prototype=direct(case)
        if not den:
            require(result['stage']=='factor' and result['failure']=='rankDeficient' and prototype['status']=='rankDeficient','both explicit nonunique zero-strain failures')
            findings.append({'id':case['id'],'status':'rankDeficient','prototype':prototype});continue
        coefficient=dot/den;responseNorm2=sum(y*y for y in ys);budget2=(128*len(xs)*EPS)**2*responseNorm2/den
        expected=rounded(coefficient);supported=math.isfinite(expected) and (coefficient==0 or expected!=0)
        if not supported:
            require(result['stage']=='solve' and result['failure']=='unrepresentableSolution' and prototype['status']=='unrepresentableSolution','both explicit unsupported coefficient failures')
            findings.append({'id':case['id'],'status':'unrepresentableSolution','exactCoefficient':audit.ratio(coefficient),'prototype':prototype});continue
        require(result['stage']=='returned' and 'failure' not in result,'supported selected QR solve')
        require(result['permutation']==[0] and result['reciprocalConditionBits']==str(struct.unpack('>Q',struct.pack('>d',1.))[0]),'one-column permutation and triangular condition diagnostic')
        require(number(result['relativeRankToleranceBits'])==1e-10,'unchanged released relative rank floor')
        require(len(result['coefficientBits'])==1,'one coefficient')
        value=exact(result['coefficientBits'][0]);error=value-coefficient
        require(error*error<=budget2,'selected absolute projection error budget '+case['id'])
        q=result['qBits'];r=result['rBits'];require(len(q)==len(r)==1 and len(q[0])==len(xs) and len(r[0])==1,'complete thin factor shapes')
        qv=[exact(v) for v in q[0]];rv=exact(r[0][0]);normalized=[scaled(x,result['matrixScaleExponent']) for x in xs];norm2=sum(x*x for x in normalized)
        require(abs(sum(v*v for v in qv)-1)<=64*len(xs)*EPS,'independent Q orthogonality')
        for x,v in zip(normalized,qv):require((x-v*rv)**2 <= (64*len(xs)*EPS)**2*norm2,'independent full factor reconstruction')
        residuals=[y-coefficient*x for x,y in zip(xs,ys)];residual2=sum(v*v for v in residuals)
        require(sum(x*v for x,v in zip(xs,residuals))==0,'exact projection orthogonality')
        residual=exact(result['scaledResidualNormBits']);require(residual>=0,'nonnegative residual norm')
        normalizedResidual2=scaled(residual2,2*result['rhsScaleExponent']);normalizedResponse2=scaled(responseNorm2,2*result['rhsScaleExponent'])
        with localcontext() as ctx:
            ctx.prec=160
            norm=decimal(normalizedResidual2).sqrt();limit=decimal(128*len(xs)*EPS)*decimal(normalizedResponse2).sqrt()
            require(abs(decimal(residual)-norm)<=limit,'selected scaled residual diagnostic budget '+case['id'])
        require(prototype['status']=='returned','supported direct prototype')
        directValue=Fraction(float.fromhex(prototype['coefficient']['binary64']));directError=directValue-coefficient
        require(directError*directError<=budget2,'selected direct projection error budget '+case['id'])
        findings.append({'id':case['id'],'status':'supported','exactCoefficient':audit.ratio(coefficient),'qrCoefficientError':audit.ratio(error),'directCoefficientError':audit.ratio(directError),'absoluteCoefficientBudgetSquared':audit.ratio(budget2),'exactResidualNormSquared':audit.ratio(residual2),'prototype':prototype,'scope':'selected-input roundoff diagnostic; no general relative-error or material-validation claim'})
    return findings

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('output',type=Path);args=p.parse_args();o=args.output
    inputs=json.loads((o/'inputs.json').read_text());qr=json.loads((o/'qr.json').read_text());findings=verify(inputs,qr)
    pins=json.loads((o/'Package.resolved').read_text())['pins'];require(len(pins)==1 and pins[0]['state']=={'revision':'00eac5537843c85c3c25a7ecef1120f49e8aa469','version':'0.1.0-alpha.19'},'exact existing released package')
    linkage=(o/'linkage.txt').read_text();require(all('/'+v+'.framework/' not in linkage for v in ['Metal','MetalKit','AppKit','SwiftUI','Accelerate']),'CPU-only numerical consumer')
    rejected=[]
    for label in ['coefficient','factor','residual','failure','coherent-input','missing-case']:
        a=copy.deepcopy(inputs);b=copy.deepcopy(qr)
        if label=='coefficient':b[0]['coefficientBits']=['0']
        elif label=='factor':b[0]['qBits'][0][0]='0'
        elif label=='residual':b[0]['scaledResidualNormBits']=str(struct.unpack('>Q',struct.pack('>d',1.))[0])
        elif label=='failure':b[0]['stage']='solve';b[0]['failure']='unrepresentableSolution'
        elif label=='coherent-input':
            # Rescale both native input/output coherently; the frozen native identity still rejects.
            a[0]['yBits']=[str(struct.unpack('>Q',struct.pack('>d',number(v)*2))[0]) for v in a[0]['yBits']]
            b[0]['coefficientBits']=[str(struct.unpack('>Q',struct.pack('>d',number(v)*2))[0]) for v in b[0]['coefficientBits']]
        else:b.pop()
        try:verify(a,b)
        except ValueError:rejected.append(label)
        else:raise ValueError('comparison corruption escaped '+label)
    savedDirect=direct
    def badDirect(case):
        result=savedDirect(case)
        if result['status']=='returned':result['coefficient']={'binary64':'0x0.0p+0'}
        return result
    globals()['direct']=badDirect
    try:
        try:verify(inputs,qr)
        except ValueError:rejected.append('direct-prototype')
        else:raise ValueError('direct projection corruption escaped')
    finally:globals()['direct']=savedDirect
    (o/'reference.json').write_text(json.dumps({'schemaVersion':1,'cases':findings},indent=2,sort_keys=True)+'\n');(o/'controls.json').write_text(json.dumps({'rejectedControls':rejected},indent=2)+'\n')
    counts={s:sum(v['status']==s for v in findings) for s in ['supported','rankDeficient','unrepresentableSolution']}
    print(json.dumps({'cases':len(findings),'counts':counts,'rejectedControls':rejected,'newAPI':False},sort_keys=True))
if __name__=='__main__':main()
