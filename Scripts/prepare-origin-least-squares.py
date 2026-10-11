#!/usr/bin/env python3
"""Create exact native input witnesses and a reversible passive production-source probe."""
import argparse,hashlib,importlib.util,json,math,random,struct,sys
from pathlib import Path
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
def bits(v):return str(struct.unpack('>Q',struct.pack('>d',v))[0])
def cases():
    spec=importlib.util.spec_from_file_location('old',ROOT/'Scripts/through-origin-audit.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
    result=[]
    queries=[bits(v) for v in [0.,-1.,1.,2.,math.ldexp(1.,-1074),float.fromhex('0x1.fffffffffffffp+1023'),math.inf,math.nan]]
    def add(name,x,y,count=None):
        d={'id':name,'xBits':[bits(v) for v in x],'yBits':[bits(v) for v in y],'queryBits':queries}
        if count is not None:d['count']=count
        result.append(d)
    for c in old.cases():add(c['id'],[float.fromhex(v) for v in c['x']],[float.fromhex(v) for v in c['y']])
    tiny=math.ldexp(1.,-1074);largest=float.fromhex('0x1.fffffffffffffp+1023')
    for name,x,y in [('empty',[],[]),('unequal',[1.],[1.,2.]),('nonfinite-x',[math.inf],[1.]),('nonfinite-y',[1.],[math.nan]),('mixed-full-range',[largest,tiny],[largest,tiny]),('product-tail',[largest,tiny],[tiny,-largest]),('native-coordinate-loss',[1.,1.,1.],[float(2**53+1),1.,-float(2**53)]),('normal-tie-even',[1.,1.],[1.,math.nextafter(1.,math.inf)]),('normal-tie-odd',[1.,1.],[math.nextafter(1.,math.inf),math.nextafter(math.nextafter(1.,math.inf),math.inf)])]:add(name,x,y)
    add('overflow-rounds-finite',[1.,2.**-54],[largest,largest])
    add('overflow-rounds-infinite',[1.,2.**-53],[largest,largest])
    add('subnormal-normal-tie',[2.],[math.nextafter(2*math.ldexp(1.,-1022),0.)])
    for n in range(1,18):add('subnormal-round-'+str(n),[2.],[n*tiny])
    for e in [-1074,-1073,-1022,-1000,-600,-100,-1,0,1,100,600,1000,1023]:
        a=math.ldexp(1.,e)
        for sign in [-1.,1.]:add('single-'+str(e)+'-'+str(sign),[a],[sign*a])
    rng=random.Random(0xC0171)
    for i in range(300):
        n=rng.randrange(1,35);xs=[];ys=[]
        for _ in range(n):
            xs.append(struct.unpack('>d',struct.pack('>Q',rng.randrange(0x7ff0000000000000)|(rng.randrange(2)<<63)))[0]);ys.append(struct.unpack('>d',struct.pack('>Q',rng.randrange(0x7ff0000000000000)|(rng.randrange(2)<<63)))[0])
        add('native-random-'+str(i),xs,ys)
    add('long-cancel',[1.],[2.**53,1.,-(2.**53)],count=12288)
    add('long-wide-tail',[largest],[largest,-largest,1.],count=12288)
    add('cap-carry',[largest],[largest],count=1048576)
    add('cap-cancellation',[1.],[2.**53,1.,-(2.**53)],count=1048576)
    add('one-past-cap',[1.],[1.],count=1048577)
    return result

def instrument(raw):
    text=raw.decode();bindings=[
      ('    guard !denominator.isZero else { throw Failure.rankDeficient }','    OriginObservation.record(["stage": "accumulation", "denominator": denominator.words.map(String.init), "positive": positive.words.map(String.init), "negative": negative.words.map(String.init)])\n    guard !denominator.isZero else { throw Failure.rankDeficient }'),
      ('    let coefficient = try quotient(numerator, denominator, sign: sign)','    OriginObservation.record(["stage": "difference", "numerator": numerator.words.map(String.init), "negative": sign == .minus])\n    let coefficient = try quotient(numerator, denominator, sign: sign)'),
      ('    guard exponent <= 1023, exponent >= -1075 else {','    OriginObservation.record(["stage": "exponent", "exponent": exponent])\n    guard exponent <= 1023, exponent >= -1075 else {'),
      ('    let doubled = remainder.shifted(1)','    OriginObservation.record(["stage": "division", "shift": shift, "a": a.words.map(String.init), "b": b.words.map(String.init), "quotient": String(significand), "remainder": remainder.words.map(String.init)])\n    let doubled = remainder.shifted(1)'),
      ('    guard significand != 0 else { throw Failure.unrepresentableCoefficient }','    OriginObservation.record(["stage": "rounding", "significand": String(significand), "subnormal": subnormal])\n    guard significand != 0 else { throw Failure.unrepresentableCoefficient }')]
    original=text
    for a,b in bindings:
        assert text.count(a)==1,a;text=text.replace(a,b)
    restored=text
    for a,b in reversed(bindings):restored=restored.replace(b,a)
    assert restored==original
    return text.encode(),{'originalSHA256':hashlib.sha256(raw).hexdigest(),'adaptedSHA256':hashlib.sha256(text.encode()).hexdigest(),'bindings':[{'original':a,'observed':b} for a,b in bindings],'restoredExactOriginal':True}
def main():
    p=argparse.ArgumentParser();p.add_argument('output',type=Path);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
    (a.output/'inputs.json').write_text(json.dumps(cases(),indent=2)+'\n');raw=(ROOT/'Sources/Numerics/OriginLeastSquares.swift').read_bytes();adapted,proof=instrument(raw);(a.output/'ObservedOriginLeastSquares.swift').write_bytes(adapted);(a.output/'source-binding.json').write_text(json.dumps(proof,indent=2)+'\n')
if __name__=='__main__':main()
