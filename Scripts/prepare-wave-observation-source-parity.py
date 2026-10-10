#!/usr/bin/env python3
"""Bind original masked CPU observation and microphone timing beside Core receiver APIs; evidence is private."""
import argparse,hashlib,importlib.util,json,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--roomcad',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];m=json.loads((root/'docs/extraction/linear-wave-observation-source.json').read_text())
spec=importlib.util.spec_from_file_location('source_map',root/'Scripts/verify-wave-extraction-source.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
source=subprocess.check_output(['git','show',m['repository']['revision']+':'+m['blocks'][0]['path']],cwd=a.roomcad).decode();blocks={}
for block in m['blocks']:
 start,end=v.selected_block(source,block['selector']);raw=source[start:end]
 v.require(len(raw.encode())==block['bytes'] and hashlib.sha256(raw.encode()).hexdigest()==block['sha256'],block['id']);blocks[block['id']]=raw
subprocess.run([sys.executable,str(root/'Scripts/prepare-forced-wave-source-parity.py'),'--roomcad',str(a.roomcad),'--output',str(a.output)],check=True)
target=a.output/'Sources/WaveSourceParity';path=target/'SourceCPU.swift';text=path.read_text().replace('import LinearAcoustics','import LinearAcoustics\nimport simd')
# Matching scaffolding only; all original observation/mixing statements are pasted unchanged.
methods='''
 struct Pattern { let omniShare:Double }
 struct Microphone { let isOmni:Bool;let axis:SIMD3<Double>;let pattern:Pattern }
 struct Receiver { let microphone:Microphone }
 func receivers(_ plan:PreparedWaveObservation)->[Receiver] {
  plan.receivers.enumerated().map { i,s in Receiver(microphone:Microphone(isOmni:s.velocityCell==nil,axis:s.velocityAxis ?? .zero,pattern:Pattern(omniShare:i==0 ? 1 : (i==1 ? 0 : 0.3)))) }
 }
 func observe(_ plan:PreparedWaveObservation)->(pressure:[Double],velocity:[Double?]) {
  let receivers=receivers(plan),nx=grid.dimensions.x,plane=grid.dimensions.x*grid.dimensions.y,n=0
  let receiverWeights=plan.receivers.map {Array(zip($0.pressureCells,$0.pressureWeights))}
  let receiverCells=plan.receivers.map { s->SIMD3<Int> in
   let at=s.velocityCell ?? 0;return [at%nx,at/nx%grid.dimensions.y,at/plane]
  }
  func index(_ x:Int,_ y:Int,_ z:Int)->Int {x+nx*y+plane*z}
  var pressure=Array(repeating:[Double](repeating:0,count:1),count:receivers.count)
  var velocity=Array(repeating:[Double](repeating:0,count:2),count:receivers.count)
'''+blocks['cpu-masked-observation']+'''
  return (pressure.map{$0[0]},velocity.enumerated().map {i,v in plan.receivers[i].velocityCell==nil ? nil : v[1]})
 }
 func mix(_ plan:PreparedWaveObservation,_ pressure:[[Double]],_ projected:[[Double?]])->[[Double]] {
  let receivers=receivers(plan),steps=pressure[0].count,c=grid.soundSpeed
  let velocity=projected.map { [0]+$0.map{$0 ?? 0} }
'''+blocks['cpu-masked-microphone-timing']+'''
 }
'''
v.require(text.endswith('}\n'),'wrapper terminator');text=text[:-2]+methods+'}\n';path.write_text(text)
(target/'main.swift').write_text((root/'Fixtures/WaveObservationSourceParity.swift').read_text())
(a.output/'observation-source-provenance.json').write_text(json.dumps(m,indent=2,sort_keys=True)+'\n')
print('Prepared exact original CPU observation and microphone timing',m['repository']['revision'],a.output)
