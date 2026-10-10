#!/usr/bin/env python3
"""Independent exact-rational packet/ledger checks over complete public consumer cases."""
import argparse,itertools,json,math,struct,sys
from fractions import Fraction as Q
from pathlib import Path
EPS=sys.float_info.epsilon

def require(v,label):
    if not v:raise ValueError(label)
def bits(v):return int.from_bytes(struct.pack('>d',float(v)),'big')
def unbits(b):return struct.unpack('>d',int(b).to_bytes(8,'big'))[0]
def snapshot(s):
    require(len(s['amount'])==8 and len(s['velocity'])==3 and len(s['bits'])==13,'complete native snapshot')
    values=[s['volume'],*s['amount'],*s['velocity'],s['pressure']]
    native=[unbits(b) for b in s['bits']]
    require(all(math.isfinite(v) for v in native),'nonfinite snapshot')
    # JSON integer -0 may lose its sign. Explicit bits are authoritative for zero.
    require(all(float(a)==b and (a==0 or bits(a)==raw) for a,b,raw in zip(values,native,s['bits'])),'snapshot values/bits')
    return native[0],native[1:9],native[9:12],native[12]
def close_exact(observed,expected,scale,label,multiplier=64):
    require(abs(Q(observed)-expected)<=Q(multiplier*EPS*max(float(scale),1e-300)),label)
def verify(root):
    cases=json.loads((root/'cases.json').read_text());summary=json.loads((root/'summary.json').read_text())
    require(len(cases)==1637 and len({c['id'] for c in cases})==1637,'complete unique case tree')
    expected=set(itertools.product(range(3),range(3),range(3),range(3),range(4),range(5)))
    actual={tuple(c['matrix']) for c in cases if 'matrix' in c}
    require(actual==expected,'complete 1620 matrix inputs')
    errors={'self':'invalidTransfer','negativeIndex':'invalidTransfer','largeIndex':'invalidTransfer','negativeTransfer':'invalidTransfer','excessiveOutflow':'excessiveOutflow','occupiedDry':'occupiedDryCell','invalidVolume':'invalidState','mismatchedCount':'invalidState','negativeEnergy':'invalidState','excessiveImpulse':'invalidState','invalidWall':'invalidState','reservedLane':'invalidState'}
    required={'rejection/'+k for k in errors}|{'cleanup/below','cleanup/at','cleanup/above','signedZero','empty'}
    require({c['id'] for c in cases if 'matrix' not in c}==required,'complete failure/cleanup controls')
    env=json.loads((root/'environment.json').read_text())
    require(env['workingTreeDirty'] is False and env['candidate']==summary['candidate'],'clean committed producer')
    pins=json.loads((root/'consumer-Package.resolved').read_text())['pins']
    require(len(pins)==1 and pins[0]['identity']=='continuumkit' and pins[0]['state']['revision']==summary['candidate'],'exact fetched public producer')
    if summary['version']:require(pins[0]['state']['version']==summary['version'],'exact tagged version')
    count=0
    for c in cases:
        old=[snapshot(s) for s in c['originalInput']];new_input=[snapshot(s) for s in c['sharedInput']]
        require([s['bits'] for s in c['originalInput']]==[s['bits'] for s in c['sharedInput']],'constructor complete bits')
        require(len(c['newVolumes'])==len(c['newVolumeBits']),'complete supplied volume bits')
        volumes=[unbits(b) for b in c['newVolumeBits']]
        require(all(v==float(raw) for v,raw in zip(volumes,c['newVolumes'])),'supplied volume values/bits')
        error=errors.get(c['id'].removeprefix('rejection/')) if c['id'].startswith('rejection/') else ('occupiedDryCell' if c['id']=='cleanup/above' else None)
        require(c.get('originalFailure')==c.get('sharedFailure')==error,'declared original/shared failure category')
        if error:
            require('original' not in c and 'shared' not in c,'failed trial published a partial result')
            continue
        original=[snapshot(s) for s in c['original']];result=[snapshot(s) for s in c['shared']]
        require(len(result)==len(original)==len(old)==len(volumes),'complete returned cell tree')
        require([s['bits'] for s in c['original']]==[s['bits'] for s in c['shared']],'complete returned bits')
        # Exact rational balances: remaining old packet + incoming old packets + external load.
        for n,(volume,amount,velocity,pressure) in enumerate(result):
            require(c['shared'][n]['bits'][0]==c['newVolumeBits'][n],'prescribed native volume identity')
            expected=[Q(x) for x in old[n][1]];scale=[abs(x) for x in expected]
            for t in c['transfers']:
                donor=t['from'];receiver=t['to'];packet=[Q(x)*Q(t['volume'])/Q(old[donor][0]) if t['volume'] else Q(0) for x in old[donor][1]]
                if n==donor:
                    expected=[x-y for x,y in zip(expected,packet)];scale=[x+abs(y) for x,y in zip(scale,packet)]
                if n==receiver:
                    expected=[x+y for x,y in zip(expected,packet)];scale=[x+abs(y) for x,y in zip(scale,packet)]
            for w in c['walls']:
                if w['cell']==n:
                    load=[0,*w['impulse'],w['gasWork'],0,0,0]
                    expected=[x+Q(y) for x,y in zip(expected,load)];scale=[x+abs(Q(y)) for x,y in zip(scale,load)]
            if volume==0:
                require(all(x==0 for x in amount) and all(b==0 for b in c['shared'][n]['bits'][1:9]),'canonical empty packet')
                # The special accepted cleanup inputs bracket the documented 64-eps budget.
                if c['id'].startswith('cleanup/'):
                    require(abs(expected[4])<=Q(2**-40),'explicit discarded dry work budget')
                else:require(all(x==0 for x in expected),'unaccounted dry-cell packet')
            else:
                require(volume>0 and amount[0]>0 and pressure>0 and all(x==0 for x in amount[5:]),'positive native physical packet')
                for a in range(8):close_exact(amount[a],expected[a],scale[a],'independent extensive packet balance')
                mass=Q(amount[0]);momentum=list(map(Q,amount[1:4]));kinetic=sum(x*x for x in momentum)/(2*mass);internal=Q(amount[4])-kinetic
                require(internal>0,'positive independent internal energy')
                for axis in range(3):close_exact(velocity[axis],momentum[axis]/mass,abs(momentum[axis]/mass),'independent velocity relation',128)
                close_exact(pressure,Q(1.4-1)*internal/Q(volume),(abs(Q(amount[4]))+abs(kinetic))/Q(volume),'independent pressure relation',128)
            count+=1
        if 'matrix' in c:
            si,di,pi,vi,fi,topology=c['matrix'];s=[1e-9,1,1e6][si];rho=[.25,1.225,7][di];p=[1,101325,1e7][pi];u=[[0,0,0],[1,-2,3],[100,50,-25]][vi];fraction=[0,.125,.5,1][fi]
            require(c['id']=='matrix/'+'/'.join(map(str,c['matrix'])),'matrix identity')
            require(len(old)==(2 if topology==0 else 3),'matrix native input count')
            expected_transfers=[{'from':0,'to':1,'volume':s*fraction}]
            if topology!=0:expected_transfers.append({'from':1,'to':2,'volume':(s if topology==3 else 2*s)*fraction})
            if topology==2:expected_transfers.append({'from':2,'to':0,'volume':4*s*fraction})
            require(c['transfers']==expected_transfers,'complete declared transfer graph')
            require(len(c['walls'])==(1 if topology==4 else 0),'complete declared external exchanges')
            for n,(volume,amount,velocity,pressure) in enumerate(old):
                require(volume==(0 if topology==3 and n==2 else s*[1,2,4][n]),'matrix old volume')
                if volume:
                    close_exact(amount[0],Q(volume)*Q(rho*[1,2,.5][n]),abs(Q(amount[0])),'matrix density')
                    for axis in range(3):close_exact(velocity[axis],Q(u[axis])*Q([1,-.5,.25][n]),abs(Q(velocity[axis])),'matrix initial velocity')
                    close_exact(pressure,Q(p*[1,.5,2][n]),(abs(Q(amount[4]))+sum(abs(Q(x)) for x in amount[1:4]))/Q(volume),'matrix initial pressure',128)
            for n,v in enumerate(volumes):
                volume=Q(old[n][0])+sum(Q(t['volume']) for t in c['transfers'] if t['to']==n)-sum(Q(t['volume']) for t in c['transfers'] if t['from']==n)
                close_exact(v,volume,sum(abs(Q(x[0])) for x in old),'matrix geometric input balance')
    require(count==4541,'complete returned native cells')
    require(summary['matrixCases']=='1620' and summary['totalCases']=='1637' and summary['bitMismatches']=='0','complete declared scope')
    pins=json.loads((root/'consumer-Package.resolved').read_text())['pins'];require(len(pins)==1 and pins[0]['identity']=='continuumkit','one fetched public product')
    require(pins[0]['state']['revision']==summary['candidate'],'exact fetched producer')
    if summary['version']:require(pins[0]['state']['version']==summary['version'],'exact tagged version')
    return {'schemaVersion':1,'status':'passed','candidate':summary['candidate'],'cases':1637,'matrixCases':1620,'returnedNativeCells':count,'bitMismatches':0,'independentReferences':'exact rational frozen packet and external impulse/work balances; positive internal energy, caloric pressure/velocity and declared graph/input completeness','roundingBudget':'64 eps sum-of-magnitudes for extensive balances; 128 eps for derived views; explicit dry-cell discarded work <= 2^-40 J in bracketing fixture'}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path);a=p.parse_args();d=verify(a.root)
    (a.root/'verification.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n');print('PASS 1637 complete gas-packet cases, exact rational ledgers, native bits and fetched pin;',d['returnedNativeCells'],'returned cells')
