#!/usr/bin/env python3
"""Require complete fields/observations and explicit per-command profiling scope."""
import argparse,json,math,struct,statistics,hashlib
from pathlib import Path
BASELINE='da7cb5f5ac642edc57e8433c6150dceca6b9edd9'
MODES=['candidate','profile32','profile256']
def require(v,s):
 if not v:raise ValueError(s)
def words(data):return list(struct.unpack('<'+'I'*(len(data)//4),data))
def float_bits(value):return struct.unpack('<I',struct.pack('<f',value))[0]
def verify(root):
 env=json.loads((root/'environment.json').read_text());report=json.loads((root/'metal-throughput.json').read_text());provenance=json.loads((root/'profile-source-provenance.json').read_text())
 require(not env['workingTreeDirty'] and len(env['candidate'])==40 and report['candidate']==env['candidate'],'clean producer')
 pins=json.loads((root/'consumer-Package.resolved').read_text())['pins'];require(len(pins)==1 and pins[0]['identity']=='continuumkit' and pins[0]['state']['revision']==env['candidate'],'fetched exact candidate')
 require(report['device'] and report['registryID']>0,'actual physical device')
 require(provenance['baseline']==BASELINE and len(provenance['files'])==4,'immutable profiling source envelope')
 for name,f in provenance['files'].items():
  original=(root/'baseline-source'/Path(name).name).read_bytes();profiled=(root/'profiled-source'/Path(name).name).read_bytes()
  require(hashlib.sha256(original).hexdigest()==f['originalSHA256'] and hashlib.sha256(profiled).hexdigest()==f['profiledSHA256'],'retained source bytes')
  text=original.decode()
  for patch in f['patches']:
   require(text.count(patch['old'])==1,'exact profiling selector');text=text.replace(patch['old'],patch['new'])
  require(text.encode()==profiled,'only declared profiling patches')
  if not name.endswith('MetalWaveStepper.swift'):require(not f['patches'] and original==profiled,'unchanged pipelines/plans/shader')
  else:require(len(f['patches'])==6 and original.count(b'memoryBarrier(scope: .buffers)')==profiled.count(b'memoryBarrier(scope: .buffers)'),'all barriers retained')
 expected=[[0.96923828125,0.53076171875,*([100]*6)],[0.12109375,*([0]*7)],[0]*8,[0]*8]
 require(report['handOracle']==[[float_bits(v) for v in r] for r in expected],'independent two-cell signed source oracle')
 require(len(report['cases'])==3 and {c['frequency'] for c in report['cases']}=={100,200,450},'complete grids')
 summaries=[];field_words=0;frame_count=0
 for case in report['cases']:
  d=case['dimensions'];n=math.prod(d);require(len(d)==3 and case['maximumThreads']>=256,'device/group capacity')
  speed=331.3*math.sqrt((20+273.15)/273.15);expected_d=[math.ceil(s/(speed/(case['frequency']*10))) for s in [8,6,3]]
  require(d==expected_d and case['speed']==speed and case['spacing']==[s/k for s,k in zip([8,6,3],d)],'independent physical grid input')
  require(len(case['inside'])==n and all(x==1 for x in case['inside']) and len(case['faces'])==6*n,'complete topology')
  limit=0.95/(speed*math.sqrt(sum(1/(h*h) for h in case['spacing'])));decimation=1
  while 2*decimation/48000<=limit:decimation*=2
  require(case['timeStep']==decimation/48000,'independent pressure clock')
  require(len(case['amplitudes'])==1024 and [float_bits(v) for v in case['amplitudes']]==[float_bits((i%7-3)/2048) for i in range(1024)],'complete signed source amplitudes')
  require(case['sourceCells']==[n//3,n//3+1] and case['sourceCoefficients']==[0.25,-0.125],'source identity')
  initial=(root/case['initialFieldFile']).read_bytes();require(len(initial)==4*n*4,'initial complete fields')
  require(words(initial)==[float_bits((i%17-8)/512) for i in range(n)]+[0]*(3*n),'independent initial fields')
  runs=case['runs'];require(len(runs)==9 and {(r['mode'],r['repetition']) for r in runs}=={(m,i) for m in MODES for i in range(3)},'complete balanced repetitions')
  control=(root/runs[0]['fieldFile']).read_bytes();require(len(control)==4*n*4,'complete end fields')
  require(all(math.isfinite(v[0]) for v in struct.iter_unpack('<f',control)),'finite full field snapshot')
  for run in runs:
   require((root/run['fieldFile']).read_bytes()==control,'every final field bit')
   require(run['frameIndices']==list(range(1,1025)),'every native frame clock')
   require(run['clock']==1024 and run['frames']==runs[0]['frames'] and run['mixed']==runs[0]['mixed'],'complete field/readout/clock parity')
   require(len(run['frames'])==len(run['mixed'])==1024 and all(len(f)==4 for f in run['frames']) and all(len(f)==2 for f in run['mixed']),'all native/mixed frames')
   last=run['frames'][-1];require(last[2]==2**64-1,'pressure-only channel has absent velocity')
   def double(word):return struct.unpack('<d',struct.pack('<Q',word))[0]
   final=list(struct.unpack('<'+'f'*(4*n),control))
   require(all(double(last[i])==final[case['pressureCells'][i][0]] for i in range(2)),'independent final native pressure readout')
   require(run['mixed'][-1][0]==last[0] and double(run['mixed'][-1][1])==0.5*double(last[1])-0.5*speed*double(last[3]),'independent terminal mixed output')
   require(all(math.isfinite(run[k]) and run[k]>0 for k in ['wallSeconds','setupSeconds','advanceSeconds','mixingSeconds']),'positive measured phases')
   require(run['wallSeconds']>=run['setupSeconds']+run['advanceSeconds']+run['mixingSeconds']-1e-6,'phase containment')
   if run['mode']=='candidate':require(run.get('commands') is None and run.get('decodeSeconds') is None,'unmeasured profiling fields explicitly absent')
   else:
    require(len(run['commands'])==8 and all(cmd['steps']==128 for cmd in run['commands']),'complete command chronology')
    require(run['decodeSeconds']>0 and math.isfinite(run['decodeSeconds']),'decode measurement')
    for cmd in run['commands']:
     require(all(math.isfinite(cmd[k]) and cmd[k]>0 for k in ['encodingSeconds','commitWaitSeconds','gpuStartSeconds','gpuEndSeconds']),'actual command timestamp')
     require(cmd['gpuEndSeconds']>cmd['gpuStartSeconds'],'completed GPU interval')
    measured=sum(cmd['encodingSeconds']+cmd['commitWaitSeconds'] for cmd in run['commands'])+run['decodeSeconds'];require(measured<=run['advanceSeconds']+1e-6,'advance phase containment')
   field_words+=4*n;frame_count+=1024
  summary={'dimensions':d,'cellCount':n,'frequency':case['frequency'],'modes':{}}
  for m in MODES:
   rs=[r for r in runs if r['mode']==m];v={k:statistics.median(r[k] for r in rs) for k in ['wallSeconds','setupSeconds','advanceSeconds','mixingSeconds']}
   if m!='candidate':
    v['decodeSeconds']=statistics.median(r['decodeSeconds'] for r in rs)
    v['gpuSeconds']=statistics.median(sum(c['gpuEndSeconds']-c['gpuStartSeconds'] for c in r['commands']) for r in rs)
    v['encodingSeconds']=statistics.median(sum(c['encodingSeconds'] for c in r['commands']) for r in rs)
    v['commitWaitSeconds']=statistics.median(sum(c['commitWaitSeconds'] for c in r['commands']) for r in rs)
   summary['modes'][m]=v
  control='profile32' if n<4096 else 'profile256'
  summary['sameFieldGroupSplitToCandidateWall']=summary['modes'][control]['wallSeconds']/summary['modes']['candidate']['wallSeconds']
  summary['largerGroupToCandidateWall']=summary['modes']['profile256']['wallSeconds']/summary['modes']['candidate']['wallSeconds']
  summary['largerGroupToProfile32GPU']=summary['modes']['profile256']['gpuSeconds']/summary['modes']['profile32']['gpuSeconds'];summaries.append(summary)
 require(frame_count==27648,'complete receiver frame tree')
 return {'schemaVersion':1,'status':'passed','candidate':env['candidate'],'device':report['device'],'completeRuns':27,'completeFieldWords':field_words,'nativeFrames':frame_count,'source':'private profiling copies retain exact alpha.10 except declared timing/group patches; public candidate uses fetched exact revision; field/injection/completion dependencies retained','scope':'controlled model profile on live hosts; no isolated or application throughput claim','timings':summaries}
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path);a=p.parse_args();r=verify(a.root);(a.root/'verification.json').write_text(json.dumps(r,indent=2,sort_keys=True)+'\n');print('PASS 27 complete field/receiver/clock profiles; larger-group/candidate wall ratios:',[t['largerGroupToCandidateWall'] for t in r['timings']])
