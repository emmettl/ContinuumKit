#!/usr/bin/env python3
"""Independent scalar DFT/inverse and time-domain gates, no Accelerate/app code."""
import argparse, json, math, struct, sys
from pathlib import Path

LENGTHS=[2,4,8,16,32]
GAINS=['identity','dcReject','tilt','center3tap']
def need(condition,message):
    if not condition: raise ValueError(message)
def near(a,b,scale=1,epsilon=2.220446049250313e-16,n=32):
    need(len(a)==len(b),'vector length')
    for j,(x,y) in enumerate(zip(a,b)):
        need(math.isfinite(x) and abs(x-y)<=256*epsilon*n*max(1,scale),f'reference value {j}: {x} != {y}')
def values(record,key,precision=64):
    v=record[key]
    need(set(v)=={'values','bits'},'native vector schema')
    xs,bs=v['values'],v['bits'];need(len(xs)==len(bs),'native bits length')
    for x,b in zip(xs,bs):
        need(math.isfinite(x),'nonfinite output')
        data=struct.pack('>d' if precision==64 else '>f',x)
        need(format(int.from_bytes(data,'big'),'x')==b,'native bit identity')
    return xs

def signal(n,p):
    if p=='dc':return [1.25]*n
    if p=='nyquist':return [0.75 if j%2==0 else -0.75 for j in range(n)]
    if p=='mixed':return [((j*7)%13-6)/8 for j in range(n)]
    kind,k=p.split('-');k=int(k)
    if kind=='impulse':return [float(j==k) for j in range(n)]
    return [math.cos(2*math.pi*k*j/n+.37) if kind=='cos' else math.sin(2*math.pi*k*j/n) for j in range(n)]
def dft(x):
    n=len(x);r=[2*math.fsum(x)];i=[2*math.fsum((-1)**j*t for j,t in enumerate(x))]
    for k in range(1,n//2):
        r.append(2*math.fsum(t*math.cos(2*math.pi*k*j/n) for j,t in enumerate(x)))
        i.append(-2*math.fsum(t*math.sin(2*math.pi*k*j/n) for j,t in enumerate(x)))
    return r,i

def inverse(r,i):
    n=len(r)*2
    return [(r[0]+(-1)**j*i[0]+2*math.fsum(r[k]*math.cos(2*math.pi*k*j/n)-i[k]*math.sin(2*math.pi*k*j/n) for k in range(1,n//2)))/(2*n) for j in range(n)]
def gain(name,f,rate):
    if name=='identity':return 1
    if name=='dcReject':return int(f!=0)
    if name=='tilt':return 1-4*f/rate
    return 1+.5*math.cos(2*math.pi*f/rate)
def frequency_order(n,rate):return [0,rate/2]+[k*(rate/n) for k in range(1,n//2)]
def weighted(r,i,name,rate):
    n=len(r)*2
    return ([r[0]*gain(name,0,rate)]+[r[k]*gain(name,k*rate/n,rate) for k in range(1,n//2)],
            [i[0]*gain(name,rate/2,rate)]+[i[k]*gain(name,k*rate/n,rate) for k in range(1,n//2)])
def packed(record,x,n):
    r,i=values(record,'real'),values(record,'imag');rr,ii=dft(x)
    need(len(x)==n,'signal dimensions');scale=sum(map(abs,x))
    near(r,rr,scale,n=n);near(i,ii,scale,n=n)
    energy=(r[0]**2+i[0]**2+2*math.fsum(a*a+b*b for a,b in zip(r[1:],i[1:])))/(4*n)
    near([energy],[math.fsum(t*t for t in x)],max(1,energy),n=n)
    return r,i

def expected_cases():
    result={}
    for n in LENGTHS:
        profiles=['dc','nyquist','mixed']+[f'impulse-{j}' for j in sorted(set([0,1,n//2,n-1]))]
        profiles += [f'{kind}-{k}' for k in range(1,n//2) for kind in ['cos','sin']]
        for p in profiles: result[f'forward/{n}/{p}']={'kind':'forward','n':n,'profile':p}
        for p in range(4):result[f'inverse/{n}/{p}']={'kind':'inverse','n':n,'pattern':p}
        for rate in [8,44100,48000]:
            for g in GAINS:result[f'accumulate/{n}/{rate}/{g}']={'kind':'accumulate','n':n,'rate':rate,'response':g}
    for count in [0,1,3,8,17]:
        for padding in [0,1,5,16]:
            n=2
            while n<count+padding:n*=2
            for g in GAINS:result[f'filter/{count}/{padding}/{g}']={'kind':'filter','count':count,'padding':padding,'n':n,'rate':48000,'response':g}
    for m in [0,1,2,3,7,8,9,17]:
        for n in [0,1,2,3,7,8,9,17]:
            for p in ['impulse','mixed','nyquist']:result[f'convolution/{m}/{n}/{p}']={'kind':'convolution','m':m,'n':n,'profile':p}
    return result

def verify_records(records):
    expected=expected_cases()
    ids=[c['id'] for c in records]
    need(len(ids)==len(set(ids)) and set(ids)==set(expected),'complete unique case tree')
    native=0
    for c in records:
        spec=expected[c['id']]
        need(all(c[k]==v for k,v in spec.items()),'parameter identity')
        kind=c['kind'];n=c['n'];y=values(c,'output',32 if kind in ['filter','convolution'] else 64)
        if kind=='forward':
            x=values(c,'input');near(x,signal(n,c['profile']),n=n)
            r,i=packed(c,x,n);near(y,inverse(r,i),sum(map(abs,x)),n=n);near(y,x,sum(map(abs,x)),n=n)
        elif kind=='inverse':
            p=c['pattern'];r=values(c,'real');i=values(c,'imag')
            need(r==[((k*5+p*3)%11-5)/4 for k in range(n//2)],'independent inverse real input')
            need(i==[((k*3+p*7)%13-6)/8 for k in range(n//2)],'independent inverse imag input')
            near(y,inverse(r,i),sum(map(abs,r+i)),n=n)
        elif kind=='accumulate':
            rate=c['rate'];g=c['response'];sr=values(c,'seedReal');si=values(c,'seedImag')
            need(sr==[(k+1)/8 for k in range(n//2)] and si==[-(k+1)/16 for k in range(n//2)],'sum seed')
            need(len(c['spectra'])==2,'multiple accumulation inputs')
            rr,ii=sr[:],si[:]
            for rec,p in zip(c['spectra'],['mixed','nyquist']):
                x=values(rec,'input');need(x==signal(n,p),'sum input');packed(rec,x,n)
                r,i=weighted(*dft(x),g,rate)
                rr=[a+b for a,b in zip(rr,r)];ii=[a+b for a,b in zip(ii,i)]
            near(values(c,'real'),rr,sum(map(abs,rr+ii)),n=n);near(values(c,'imag'),ii,sum(map(abs,rr+ii)),n=n)
            near(values(c,'frequencies'),frequency_order(n,rate)*2,rate,n=n)
            near(y,inverse(rr,ii),sum(map(abs,rr+ii)),n=n)
        elif kind=='filter':
            x=values(c,'input',32);count=c['count'];rate=c['rate'];g=c['response']
            need(x==[((j*7)%13-6)/8 for j in range(count)],'filter source')
            padded=x+[0]*(n-count)
            if g=='center3tap':ref=[padded[j]+.25*(padded[(j-1)%n]+padded[(j+1)%n]) for j in range(count)]
            elif g=='identity':ref=x
            elif g=='dcReject':ref=[t-math.fsum(padded)/n for t in x]
            else:ref=inverse(*weighted(*dft(padded),g,rate))[:count]
            near(y,ref,sum(map(abs,x)),epsilon=2**-23,n=1)
            near(values(c,'frequencies'),frequency_order(n,rate),rate,n=n)
        else:
            m=c['m'];p=c['profile'];a=values(c,'input',32);b=values(c,'responseInput',32)
            aa=[float(j==m-1) if p=='impulse' else (-1)**j if p=='nyquist' else ((j*7)%11-5)/8 for j in range(m)]
            bb=[.5*float(j==0) if p=='impulse' else .75*(-1)**j if p=='nyquist' else ((j*3)%7-3)/4 for j in range(n)]
            need(a==aa and b==bb,'convolution source')
            ref=[math.fsum(a[j]*b[k-j] for j in range(m) if 0<=k-j<n) for k in range(m+n-1)] if m and n else []
            near(y,ref,sum(map(abs,a))*sum(map(abs,b)),epsilon=2**-23,n=1)
        native+=len(y)
    return len(records),native

FAILURES={**{f'length/{n}':'invalidLength' for n in [-1,0,1,3,2**63-1]},'forward/count':'invalidDimensions','inverse/empty':'invalidDimensions','inverse/short':'invalidDimensions','forward/nan':'nonFiniteInput','inverse/infinity':'nonFiniteInput',**{f'rate/{s}':'invalidSampleRate' for s in ['0.0','-1.0','inf']},'padding/negative':'invalidPadding','count/overflow':'countOverflow','count/roundingOverflow':'countOverflow','accumulate/dimensions':'invalidDimensions','accumulate/coefficient':'nonFiniteResponse','convolution/nan':'nonFiniteInput','convolution/floatOverflow':'floatOverflow'}
def verify_failures(records):
    need(len(records)==len(FAILURES) and {c['id']:c['error'] for c in records}==FAILURES,'complete checked failure matrix')

def verify(root,metadata=True):
    root=Path(root)
    original=json.loads((root/'original.json').read_text());shared=json.loads((root/'shared.json').read_text())
    counts=verify_records(original);need(verify_records(shared)==counts,'scope parity')
    need(original==shared,'complete native original/shared values and bits')
    verify_failures(json.loads((root/'failures.json').read_text()))
    if metadata:
        env=json.loads((root/'environment.json').read_text());need(env['workingTreeDirty'] is False,'dirty producer')
        pins=json.loads((root/'consumer-Package.resolved').read_text())['pins'];need(len(pins)==1 and pins[0]['state']['revision']==env['candidate'],'fetched source pin')
    return counts
if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('output');args=a.parse_args()
    try:
        count,native=verify(args.output);print(f'PASS {count} complete original/shared FFT cases, {native} output values, {len(FAILURES)} checked failures; scalar DFT/inverse, Parseval, gains, circular filtering and direct convolution')
    except (ValueError,KeyError,IndexError,TypeError) as e:sys.exit(f'FAIL FFT reference: {e}')
