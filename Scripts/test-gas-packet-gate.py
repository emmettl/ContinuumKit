#!/usr/bin/env python3
"""Require rejection of corrupted complete packet reports, beyond paired equality."""
import argparse,importlib.util,json,shutil,struct,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('packet_gate',Path(__file__).with_name('verify-gas-packet-output.py'));gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
def mutate_amount(c,slot,lane,value):
    for variant in ['original','shared']:
        state=c[variant][slot];state['amount'][lane]=value;state['bits'][lane+1]=gate.bits(value)
def controls(source):
    gate.verify(source)
    cases={
      'missing case':lambda d:d.pop(),
      'duplicate matrix identity':lambda d:d.__setitem__(1,d[0]),
      'missing native result':lambda d:[d[0][v].pop() for v in ['original','shared']],
      'unaccounted mass':lambda d:mutate_amount(d[0],0,0,d[0]['shared'][0]['amount'][0]*1.1),
      'unaccounted energy':lambda d:mutate_amount(d[0],0,4,d[0]['shared'][0]['amount'][4]*1.1),
      'reserved result lane':lambda d:mutate_amount(d[0],0,7,1),
      'changed prescribed transfer':lambda d:d[1]['transfers'][0].__setitem__('volume',1),
      'missing supplied volume bit':lambda d:d[0]['newVolumeBits'].pop(),
      'missing external exchange':lambda d:next(c for c in d if c.get('matrix',[0])[-1]==4)['walls'].pop(),
      'wrong failure category':lambda d:[next(c for c in d if c['id']=='rejection/self').__setitem__(v,'invalidState') for v in ['originalFailure','sharedFailure']],
      'excessive dry cleanup':lambda d:next(c for c in d if c['id']=='cleanup/at')['walls'][0].__setitem__('gasWork',gate.unbits(gate.bits(2**-40)+1)),
    }
    rejected=[]
    for label,mutation in [*cases.items(),('wrong fetched pin',None),('dirty producer',None)]:
      with tempfile.TemporaryDirectory(prefix='continuumkit-packet-control-') as tmp:
        r=Path(tmp);shutil.copytree(source,r,dirs_exist_ok=True)
        if mutation:
          d=json.loads((r/'cases.json').read_text());mutation(d);(r/'cases.json').write_text(json.dumps(d))
        elif label=='wrong fetched pin':
          p=r/'consumer-Package.resolved';d=json.loads(p.read_text());d['pins'][0]['state']['revision']='0'*40;p.write_text(json.dumps(d))
        else:
          p=r/'environment.json';d=json.loads(p.read_text());d['workingTreeDirty']=True;p.write_text(json.dumps(d))
        try:gate.verify(r)
        except (ValueError,KeyError,IndexError):rejected.append(label)
        else:raise AssertionError('gate accepted '+label)
    return rejected
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path);a=p.parse_args();d={'schemaVersion':1,'status':'passed','rejectedControls':controls(a.root)}
    (a.root/'negative-controls.json').write_text(json.dumps(d,indent=2,sort_keys=True)+'\n');print('PASS rejected',len(d['rejectedControls']),'packet completeness/ledger/pin controls')
