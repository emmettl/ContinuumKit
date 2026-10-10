#!/usr/bin/env python3
"""Corrupt both native reports together to test independent acceptance beyond parity."""
import argparse,copy,importlib.util,json,struct
from pathlib import Path
spec=importlib.util.spec_from_file_location('euler_gate',Path(__file__).with_name('verify-euler-flux-output.py'))
gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
def set_value(s,k,v):s['values'][k]=v;s['bits'][k]=format(int.from_bytes(struct.pack('>d',v),'big'),'x')
def controls(root):
 gate.verify(root)
 source=json.loads((root/'shared.json').read_text())
 by_id={c['id']:i for i,c in enumerate(source)}
 rejected=[]
 trials=['missing case','duplicate identity','missing native result','unaccounted mass','unaccounted energy','reserved lane','wrong CFL clock','wrong wall work','missing wall impulse','wrong failure category','incomplete wave interval','missing temporal level','wrong fetched pin','dirty producer']
 for label in trials:
  tree=list(source);metadata={}
  index=by_id['wall/0/0/0/0/1'] if 'wall' in label else (by_id['failure/index'] if 'failure' in label else (by_id['acoustic/128'] if 'wave' in label else 0))
  tree[index]=copy.deepcopy(tree[index]);c=tree[index];i=c['intervals'][0]
  if label=='missing temporal level':tree.pop(by_id['acousticTime/1'])
  elif label=='missing case':tree.pop()
  elif label=='duplicate identity':tree[1]=tree[0]
  elif label=='missing native result':i['result'].pop()
  elif label=='unaccounted mass':set_value(i['result'][0],1,i['result'][0]['values'][1]*1.1)
  elif label=='unaccounted energy':set_value(i['result'][0],5,i['result'][0]['values'][5]*1.1)
  elif label=='reserved lane':set_value(i['result'][0],8,1.0)
  elif label=='wrong CFL clock':
   i['limit']*=1.1;i['limitBits']=format(int.from_bytes(struct.pack('>d',i['limit']),'big'),'x')
  elif label=='wrong wall work':i['work'][0]=1.0
  elif label=='missing wall impulse':i['impulses'].pop()
  elif label=='wrong failure category':i['failure']='packet.invalidState'
  elif label=='incomplete wave interval':c['intervals'].pop(1)
  elif label=='wrong fetched pin':
   pins=json.loads((root/'consumer-Package.resolved').read_text())['pins'];pins[0]['state']['revision']='0'*40;metadata['pins']=pins
  elif label=='dirty producer':
   env=json.loads((root/'environment.json').read_text());env['workingTreeDirty']=True;metadata['environment']=env
  try:gate.verify(root,(tree,tree),metadata)
  except (ValueError,KeyError,IndexError,ZeroDivisionError):rejected.append(label)
  else:raise AssertionError('gate accepted '+label)
 return rejected
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path);a=p.parse_args()
 result={'schemaVersion':1,'status':'passed','rejectedControls':controls(a.root)}
 (a.root/'negative-controls.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 print('PASS rejected',len(result['rejectedControls']),'Euler completeness/physics/clock/pin controls')
