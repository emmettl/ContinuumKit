#!/usr/bin/env python3
"""Require all native fields, raw receiver histories, clocks, modes and timing repetitions."""
import argparse,hashlib,json,math,statistics,struct,subprocess
from pathlib import Path
MODES={'alpha8','serial','parallel'}
def require(value,label):
    if not value:raise ValueError(label)
def bits(value,width):
    require(isinstance(value,(float,int)) and math.isfinite(value),'nonfinite value')
    return int.from_bytes(struct.pack('>f' if width==32 else '>d',value),'big')
def verify(root):
    env=json.loads((root/'environment.json').read_text());require(not env['workingTreeDirty'],'dirty candidate')
    pins=json.loads((root/'consumer-Package.resolved').read_text())['pins'];require(len(pins)==1 and pins[0]['identity']=='continuumkit' and pins[0]['state']=={'revision':env['candidate']},'exact fetched candidate')
    provenance=json.loads((root/'baseline-source-provenance.json').read_text());require(provenance['baseline']=='2aecacbc3da082382cb11639d67af0ea37583272','alpha8 baseline')
    original=subprocess.check_output(['git','show',provenance['baseline']+':'+provenance['source']],cwd=Path(__file__).resolve().parents[1])
    require(hashlib.sha256(original).hexdigest()==provenance['sourceSHA256'],'immutable baseline source')
    body=original.decode();body=body[body.index('public final class CPUWaveStepper {'):]
    require(hashlib.sha256(body.encode()).hexdigest()==provenance['classSHA256'],'immutable baseline class')
    adapted=(root/'Alpha8CPUWaveStepper.swift').read_text();adapted=adapted[adapted.index('final class Alpha8CPUWaveStepper {'):]
    require(adapted==body.replace('public final class CPUWaveStepper {','final class Alpha8CPUWaveStepper {',1),'only class name adaptation')
    reports=json.loads((root/'timings.json').read_text());require(len(reports)==3 and {tuple(r['dimensions']) for r in reports}=={(24,18,9),(47,35,18),(105,79,40)},'complete grid tree')
    summary=[];captures=0
    for report in reports:
        count=math.prod(report['dimensions']);dt=report['dt'];timings=report['timings']
        require(dt>0 and math.isfinite(dt),'timestep')
        require(report['activeMask']=='all active' and report['initialFields']=='all four fields zero','input scope')
        require(len(timings)==9 and {(t['mode'],t['repetition']) for t in timings}=={(m,r) for m in MODES for r in range(3)},'complete modes/repetitions')
        values={}
        for timing in timings:
            require(timing['steps']==1024 and timing['wallSeconds']>0 and timing['cpuSeconds']>0 and math.isfinite(timing['wallSeconds']) and math.isfinite(timing['cpuSeconds']),'timing scope/values')
            require(timing['slabs']==(min(16,report['dimensions'][2]) if timing['mode']=='parallel' else 1),'actual slab execution')
            path=Path(timing['fieldsFile']);require(str(path)=='x'.join(map(str,report['dimensions']))+'/'+timing['mode']+'-'+str(timing['repetition'])+'.json','unique exact field path')
            data=json.loads((root/path).read_text())
            require(data['step']==1024 and data['pressureTime']==1024*dt and data['velocityTime']==1023.5*dt,'complete clocks')
            require(len(data['values'])==len(data['bits'])==4 and all(len(a)==len(b)==count for a,b in zip(data['values'],data['bits'])),'complete four native fields')
            require(all(bits(a,32)==b for values,encoded in zip(data['values'],data['bits']) for a,b in zip(values,encoded)),'native value/bit agreement')
            require(len(data['pressure'])==len(data['velocity'])==len(data['pressureBits'])==len(data['velocityBits'])==1024,'complete receiver histories')
            for pressure,velocity,pbits,vbits in zip(data['pressure'],data['velocity'],data['pressureBits'],data['velocityBits']):
                require(len(pressure)==len(velocity)==len(pbits)==len(vbits)==2 and velocity[0] is None and vbits[0] is None and velocity[1] is not None,'receiver shape/presence')
                require(all(bits(v,64)==b for v,b in zip(pressure,pbits)) and bits(velocity[1],64)==vbits[1],'receiver value/bit agreement')
            values[(timing['mode'],timing['repetition'])]=(data['bits'],data['pressureBits'],data['velocityBits']);captures+=1
        baseline=values[('alpha8',0)];require(all(v==baseline for v in values.values()),'complete baseline/serial/parallel bit mismatch')
        wall={m:statistics.median(t['wallSeconds'] for t in timings if t['mode']==m) for m in MODES}
        cpu={m:statistics.median(t['cpuSeconds'] for t in timings if t['mode']==m) for m in MODES}
        summary.append({'dimensions':report['dimensions'],'cells':count,'wallMedians':wall,'cpuMedians':cpu,'parallelToAlpha8Wall':wall['parallel']/wall['alpha8'],'serialToAlpha8Wall':wall['serial']/wall['alpha8']})
    return {'schemaVersion':1,'candidate':env['candidate'],'status':'passed','completeNativeCaptures':captures,'completeRawReceiverFrames':captures*1024,'runtimeBitMismatches':0,'scope':'complete model numerical equivalence; timings are live-host measurements, not application throughput acceptance','timings':summary}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path);a=p.parse_args();result=verify(a.root)
    (a.root/'verification.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print('PASS complete alpha8/serial/parallel fields and receiver histories;',[(t['cells'],t['parallelToAlpha8Wall']) for t in result['timings']])
