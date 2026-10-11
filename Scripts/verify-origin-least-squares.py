#!/usr/bin/env python3
"""Check complete native inputs, exact accumulators, division and public rounding independently."""
import argparse,collections,copy,hashlib,importlib.util,json,math,struct,sys
from fractions import Fraction
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
UNIT=1<<2148
CAP=1048576

def require(ok,label):
    if not ok:raise ValueError(label)
def value(bits):return struct.unpack('<d',struct.pack('<Q',int(bits)))[0]
def bits(v):return str(struct.unpack('<Q',struct.pack('<d',v))[0])
def integer(words):
    require(all(0<=int(v)<1<<64 for v in words) and (not words or int(words[-1])!=0),'canonical exact integer words')
    return sum(int(v)<<(64*i) for i,v in enumerate(words))
def rounded(q):
    try:v=float(q)
    except OverflowError:return None
    return None if not math.isfinite(v) or (q!=0 and v==0) else v

def inputs(case,raw):
    xp=[int(v) for v in case['xBits']];yp=[int(v) for v in case['yBits']];nx=case.get('count',len(xp));ny=case.get('count',len(yp))
    require(len(raw)==8*(nx+ny),'complete every native input byte')
    xs=struct.iter_unpack('<Q',memoryview(raw)[:8*nx]);ys=struct.iter_unpack('<Q',memoryview(raw)[8*nx:]);pairs=collections.Counter()
    for i,(x,) in enumerate(xs):
        require(x==xp[i%len(xp)],'actual complete native x witness')
        if i<ny:
            y=next(ys)[0];require(y==yp[i%len(yp)],'actual complete native y witness');pairs[(x,y)]+=1
    for i,(y,) in enumerate(ys,start=min(nx,ny)):require(y==yp[i%len(yp)],'actual remaining native y witness')
    return nx,ny,pairs

def verify_case(case,output,trace,raw):
    require(case['id']==output['id'],'actual case identity');nx,ny,pairs=inputs(case,raw)
    expectedFailure=None
    if nx!=ny or nx==0:expectedFailure='invalidDimensions'
    elif nx>CAP:expectedFailure='allocationLimit'
    elif not all(math.isfinite(value(v)) for v in case['xBits']+case['yBits']):expectedFailure='nonFiniteInput'
    if expectedFailure:
        require(output=={'id':case['id'],'failure':expectedFailure,'predictions':[]} and trace==[],'exact public input rejection before arithmetic')
        return {'id':case['id'],'status':expectedFailure,'count':nx}
    denominator=Fraction();positive=Fraction();negative=Fraction()
    for (xb,yb),count in pairs.items():
        x=Fraction(value(xb));y=Fraction(value(yb));denominator+=count*x*x;product=count*x*y
        if product>=0:positive+=product
        else:negative-=product
    def dyadic(q):
        n=q*UNIT;require(n.denominator==1,'every native product exact on2^-2148 lattice');return n.numerator
    events={v['stage']:v for v in trace};require(len(events)==len(trace),'unique complete arithmetic stages')
    require('accumulation' in events,'actual complete accumulator observation');s=events['accumulation']
    require(integer(s['denominator'])==dyadic(denominator) and integer(s['positive'])==dyadic(positive) and integer(s['negative'])==dyadic(negative),'exact full source product sums')
    require(all(len(s[k])<=66 for k in ['denominator','positive','negative']),'proved cap-bounded accumulator widths')
    if denominator==0:
        require(output=={'id':case['id'],'failure':'rankDeficient','predictions':[]} and set(events)=={'accumulation'},'mathematical nonunique zero-vector rank failure')
        return {'id':case['id'],'status':'rankDeficient','count':nx}
    numerator=positive-negative;require('difference' in events,'actual signed cancellation difference');d=events['difference'];require(integer(d['numerator'])==dyadic(abs(numerator)) and d['negative']==(numerator<0),'exact signed native dot product')
    coefficient=numerator/denominator;expected=rounded(coefficient)
    if numerator!=0:
        require('exponent' in events,'actual nonzero exact ratio exponent');e=events['exponent']['exponent'];q=abs(coefficient);require(Fraction(2)**e<=q<Fraction(2)**(e+1),'exact ratio binary exponent enclosure')
        if -1075<=e<=1023:
            require('division' in events and 'rounding' in events,'complete supported-scale division and tie decision')
            division=events['division'];subnormal=e<-1022;shift=1074 if subnormal else 52-e
            a=dyadic(abs(numerator))*(1<<max(shift,0));b=dyadic(denominator)*(1<<max(-shift,0));quo,rem=divmod(a,b)
            require(division['shift']==shift and integer(division['a'])==a and integer(division['b'])==b and int(division['quotient'])==quo and integer(division['remainder'])==rem,'exact numerator/denominator quotient and remainder')
            decision=events['rounding'];nearest=quo+(2*rem>b or (2*rem==b and quo%2==1));require(int(decision['significand'])==nearest and decision['subnormal']==subnormal,'actual exact nearest-even decision')
            require(set(events)=={'accumulation','difference','exponent','division','rounding'},'complete valid-scale stage tree')
        else:require(set(events)=={'accumulation','difference','exponent'},'explicit unsupported output-scale stage tree')
    else:require(set(events)=={'accumulation','difference'},'exact-zero coefficient with no fabricated ratio stage')
    if expected is None:
        require(output=={'id':case['id'],'failure':'unrepresentableCoefficient','predictions':[]},'exact mathematical coefficient representation failure')
        return {'id':case['id'],'status':'unrepresentableCoefficient','count':nx,'exactNumerator':str(numerator.numerator),'exactDenominator':str(numerator.denominator),'normalizationRequired':False}
    require(output.get('coefficientBits')==bits(expected) and output.get('count')==nx and 'failure' not in output,'correctly rounded exact-native coefficient, including cancellation sign')
    require(len(output['predictions'])==len(case['queryBits']),'all query outcomes retained')
    for query,prediction in zip(case['queryBits'],output['predictions']):
        require(prediction['queryBits']==query,'same actual query')
        v=value(query)
        if not math.isfinite(v):require(prediction=={'queryBits':query,'failure':'nonFiniteQuery'},'nonfinite query boundary');continue
        exact=Fraction(expected)*Fraction(v);answer=rounded(exact)
        if answer is None:require(prediction=={'queryBits':query,'failure':'unrepresentablePrediction'},'prediction representation boundary');continue
        outputBits=bits(answer)
        if exact==0:outputBits=str(((int(bits(expected))>>63)^(int(query)>>63))<<63)
        require(prediction=={'queryBits':query,'valueBits':outputBits},'exact rounded product of represented fitted line')
    # Projection orthogonality uses the exact mathematical coefficient, before final rounding.
    require(sum(count*Fraction(value(x))*(Fraction(value(y))-coefficient*Fraction(value(x))) for (x,y),count in pairs.items())==0,'exact full native projection residual orthogonality')
    residual=sum(count*(Fraction(value(y))-coefficient*Fraction(value(x)))**2 for (x,y),count in pairs.items())
    roundedResidual=sum(count*(Fraction(value(y))-Fraction(expected)*Fraction(value(x)))**2 for (x,y),count in pairs.items())
    return {'id':case['id'],'status':'correctly-rounded','count':nx,'coefficientNumerator':str(coefficient.numerator),'coefficientDenominator':str(coefficient.denominator),'roundedCoefficientBits':bits(expected),'exactCoefficientErrorNumerator':str((Fraction(expected)-coefficient).numerator),'exactCoefficientErrorDenominator':str((Fraction(expected)-coefficient).denominator),'exactProjectionResidualSquaredNumerator':str(residual.numerator),'exactProjectionResidualSquaredDenominator':str(residual.denominator),'representedLineResidualSquaredNumerator':str(roundedResidual.numerator),'representedLineResidualSquaredDenominator':str(roundedResidual.denominator),'distinctNativePairs':len(pairs),'normalizationRequired':False}

def verify(folder,probe_only=False):
    binding=json.loads((folder/'source-binding.json').read_text());original=(ROOT/'Sources/Numerics/OriginLeastSquares.swift').read_bytes();adapted=(folder/'ObservedOriginLeastSquares.swift').read_bytes()
    require(hashlib.sha256(original).hexdigest()==binding['originalSHA256'] and hashlib.sha256(adapted).hexdigest()==binding['adaptedSHA256'],'actual original/adapted production source')
    restored=adapted.decode()
    for item in reversed(binding['bindings']):
        require(restored.count(item['observed'])==1,'unique passive source binding');restored=restored.replace(item['observed'],item['original'])
    require(restored.encode()==original,'source adaptation restores exact production bytes')
    spec=importlib.util.spec_from_file_location('prep',ROOT/'Scripts/prepare-origin-least-squares.py');prepare=importlib.util.module_from_spec(spec);spec.loader.exec_module(prepare)
    cases=json.loads((folder/'inputs.json').read_text());require(cases==prepare.cases(),'complete fixed native case cohort including protected ninety source cases')
    outputs=json.loads((folder/'native/results.json').read_text());require(len(outputs)==len(cases),'every actual source outcome')
    if not probe_only:require(json.loads((folder/'public/results.json').read_text())==outputs,'every actual public Git-consumer outcome matches observed production source')
    findings=[]
    for i,(case,out) in enumerate(zip(cases,outputs)):
        findings.append(verify_case(case,out,json.loads((folder/f'native/trace-{i}.json').read_text()),(folder/f'native/inputs-{i}.bin').read_bytes()))
    index=next(i for i,c in enumerate(cases) if c['id']=='shear/cancellation-positive');case=cases[index];original=outputs[index];trace=json.loads((folder/f'native/trace-{index}.json').read_text());raw=(folder/f'native/inputs-{index}.bin').read_bytes();rejected=[]
    for label in ['coefficient','product-sum','signed-difference','division-remainder','rounding','query','false-failure','coherent-input','coherent-denominator-output']:
        out=copy.deepcopy(original);t=copy.deepcopy(trace);r=raw
        if label=='coefficient':out['coefficientBits']='0'
        elif label=='product-sum':t[0]['positive'][0]=str(int(t[0]['positive'][0])+1)
        elif label=='signed-difference':t[1]['numerator']=['0']
        elif label=='division-remainder':next(v for v in t if v['stage']=='division')['remainder']=['0']
        elif label=='rounding':next(v for v in t if v['stage']=='rounding')['significand']='0'
        elif label=='query':out['predictions'][2]['valueBits']='0'
        elif label=='false-failure':out={'id':case['id'],'failure':'rankDeficient','predictions':[]}
        elif label=='coherent-denominator-output':
            def words(v):
                return [str((v>>(64*i))&((1<<64)-1)) for i in range((v.bit_length()+63)//64)]
            denominator=integer(t[0]['denominator'])*2;t[0]['denominator']=words(denominator)
            numerator=integer(t[1]['numerator']);ratio=Fraction(numerator,denominator);e=numerator.bit_length()-denominator.bit_length()
            if ratio<Fraction(2)**e:e-=1
            next(v for v in t if v['stage']=='exponent')['exponent']=e
            shift=52-e;a=numerator<<shift;b=denominator;quo,rem=divmod(a,b)
            division=next(v for v in t if v['stage']=='division');division.update(shift=shift,a=words(a),b=words(b),quotient=str(quo),remainder=words(rem))
            next(v for v in t if v['stage']=='rounding')['significand']=str(quo+(2*rem>b or (2*rem==b and quo%2==1)))
            coefficient=float(ratio);out['coefficientBits']=bits(coefficient)
            for prediction in out['predictions']:
                query=value(prediction['queryBits'])
                if not math.isfinite(query):continue
                product=Fraction(coefficient)*Fraction(query);answer=rounded(product)
                prediction.pop('valueBits',None);prediction.pop('failure',None)
                if answer is None:prediction['failure']='unrepresentablePrediction'
                elif product==0:prediction['valueBits']=str(((int(bits(coefficient))>>63)^(int(prediction['queryBits'])>>63))<<63)
                else:prediction['valueBits']=bits(answer)
        else:
            # Coherent x/y scaling keeps the fitted coefficient but changes the fixed native cohort.
            words=list(struct.unpack('<'+'Q'*(len(raw)//8),raw));r=b''.join(struct.pack('<Q',int(bits(value(v)*2))) for v in words)
            def asWords(v):return [str((v>>(64*i))&((1<<64)-1)) for i in range((v.bit_length()+63)//64)]
            for event in t:
                for key in ['denominator','positive','negative','numerator','a','b','remainder']:
                    if isinstance(event.get(key),list):event[key]=asWords(integer(event[key])*4)
        try:verify_case(case,out,t,r)
        except ValueError:rejected.append(label)
        else:raise ValueError('coherent corruption escaped '+label)
    (folder/'reference.json').write_text(json.dumps({'schemaVersion':1,'cases':findings},indent=2,sort_keys=True)+'\n');(folder/'controls.json').write_text(json.dumps({'rejectedControls':rejected},indent=2)+'\n');counts=collections.Counter(v['status'] for v in findings)
    print(json.dumps({'cases':len(findings),'findings':dict(counts),'rejectedControls':rejected},sort_keys=True))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--probe-only',action='store_true');a=p.parse_args();verify(a.folder,a.probe_only)
