#!/usr/bin/env python3
"""Independent complete-case/bit/law postcondition for the public gas-wall consumer."""
import argparse,itertools,json,math,struct
from pathlib import Path

def require(value,label):
    if not value: raise ValueError(label)
def bits(value):
    require(math.isfinite(value),'nonfinite output')
    return int.from_bytes(struct.pack('>d',value),'big')
def close(a,b): return abs(a-b)<=2e-9*max(abs(a),abs(b),1e-300)
def verify(root):
    cases=json.loads((root/'cases.json').read_text());summary=json.loads((root/'summary.json').read_text())
    expected={(rho,p,m*math.sqrt(g*p/rho),g) for g,rho,p,m in itertools.product([1.1,1.4,5/3,3],[0.25,1.225,7],[0.01,101325,1e7],[-8,-3,-1,-.5,-.1,0,.001,.5,1,5])}
    actual={(x['density'],x['pressure'],x['normalVelocity'],x['gamma']) for x in cases}
    require(len(cases)==len(actual)==360 and actual==expected,'complete case tree')
    for x in cases:
        rho,p,u,g=[x[k] for k in ['density','pressure','normalVelocity','gamma']]
        c=math.sqrt(g*p/rho);star=x['sharedPressure'];rate=x['sharedSignalSpeed']
        require(bits(star)==bits(x['originalPressure'])==x['pressureBits'],'complete pressure bits')
        require(bits(rate)==bits(x['originalSignalSpeed'])==x['signalSpeedBits'],'complete signal bits')
        require(rate>0 and star>=0,'finite physical result')
        if u>0:
            require(not x['vacuum'] and star>p,'compression branch')
            ratio=star/p;beta=(g-1)/(g+1);r2=rho*(ratio+beta)/(beta*ratio+1)
            shock=-rho*u/(r2-rho);a=u-shock;b=-shock
            require(close(rho*a,r2*b),'mass jump')
            require(close(p+rho*a*a,star+r2*b*b),'momentum jump')
            require(close(g*p/((g-1)*rho)+a*a/2,g*star/((g-1)*r2)+b*b/2),'energy jump')
        elif 1+(g-1)*u/(2*c)<=0:
            require(x['vacuum'] and star==0,'analytic vacuum branch')
        else:
            require(not x['vacuum'] and star>0,'non-vacuum expansion/rest')
            recovered=2*c/(g-1)*(math.pow(star/p,(g-1)/(2*g))-1)
            require(abs(recovered-u)<=2e-10*c,'rarefaction invariant')
    require(summary['completeSourceCases']=='360' and summary['ordinaryBitMismatches']=='0','declared complete scope')
    require(abs(float(summary['nearIsothermalPressure'])-math.exp(-.2))<1e-12,'independent limiting pressure')
    pins=json.loads((root/'consumer-Package.resolved').read_text())['pins'];require(len(pins)==1,'one fetched dependency')
    require(pins[0]['state']['revision']==summary['candidate'],'resolved producer revision')
    if summary['version']: require(pins[0]['state']['version']==summary['version'],'exact tagged version')
    return {'schemaVersion':1,'status':'passed','candidate':summary['candidate'],'cases':360,'bitMismatches':0,'independentLaws':['mass/momentum/energy jumps','rarefaction invariant','vacuum branch','near-isothermal limit']}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('root',type=Path);args=parser.parse_args()
    result=verify(args.root);(args.root/'verification.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('PASS complete 360-case gas-wall pressure/signal bits, independent gas laws and exact fetched dependency')
