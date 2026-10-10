#!/usr/bin/env python3
"""Bind exact original GPU sampling and microphone mixing beside resident observations; retain outputs privately."""
import argparse,hashlib,importlib.util,json,re,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--roomcad',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];manifest=json.loads((root/'docs/extraction/linear-wave-observation-source.json').read_text())
spec=importlib.util.spec_from_file_location('source_map',root/'Scripts/verify-wave-extraction-source.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
blocks={}
for block in manifest['blocks']:
 if not block['id'].startswith('metal-'):continue
 source=subprocess.check_output(['git','show',manifest['repository']['revision']+':'+block['path']],cwd=a.roomcad).decode()
 start,end=v.selected_block(source,block['selector']);raw=source[start:end]
 v.require(len(raw.encode())==block['bytes'] and hashlib.sha256(raw.encode()).hexdigest()==block['sha256'],block['id']);blocks[block['id']]=raw
subprocess.run([sys.executable,str(root/'Scripts/prepare-forced-metal-wave-source-parity.py'),'--roomcad',str(a.roomcad),'--output',str(a.output)],check=True)
target=a.output/'Sources/MetalSourceParity';path=target/'SourceGPU.swift';text=path.read_text()
m=re.search(r' static let source=(.*)\n init',text);v.require(m is not None,'source declaration')
msl=json.loads(m.group(1))+blocks['metal-observation'];text=text[:m.start(1)]+json.dumps(msl)+text[m.end(1):]
text=text.replace('let velocity,pressure,injection:any MTLComputePipelineState','let velocity,pressure,injection,sampling:any MTLComputePipelineState')
text=text.replace('  func buffer<T>', '  sampling=try device.makeComputePipelineState(function:library.makeFunction(name:"waveSample")!)\n  func buffer<T>',1)
methods='''
 func observe(_ plan:PreparedWaveObservation) throws -> (pressure:[Double],velocity:[Double?]) {
  let count=plan.receivers.count
  func buffer<T>(_ values:[T]) throws -> any MTLBuffer {try values.withUnsafeBytes{raw in
   guard let b=queue.device.makeBuffer(bytes:raw.baseAddress!,length:raw.count,options:.storageModeShared) else {throw ComparisonFailure.device};return b}}
  let cells=try buffer(plan.receivers.flatMap{$0.pressureCells.map(UInt32.init)}),weights=try buffer(plan.receivers.flatMap{$0.pressureWeights})
  let dummy=1+grid.dimensions.x+grid.dimensions.x*grid.dimensions.y
  let velocityCells=try buffer(plan.receivers.map{UInt32($0.velocityCell ?? dummy)})
  let axes=try buffer(plan.receivers.flatMap{s->[Float] in let a=s.velocityAxis ?? .zero;return [Float(a.x),Float(a.y),Float(a.z)]})
  let output=try buffer([Float](repeating:0,count:count)),velocityOutput=try buffer([Float](repeating:0,count:2*count))
  var abi=Grid(nx:UInt32(grid.dimensions.x),ny:UInt32(grid.dimensions.y),nz:UInt32(grid.dimensions.z),kx:grid.velocityCoefficients.x,ky:grid.velocityCoefficients.y,kz:grid.velocityCoefficients.z,bx:grid.pressureCoefficients.x,by:grid.pressureCoefficients.y,bz:grid.pressureCoefficients.z)
  var step:UInt32=0,steps:UInt32=1,receivers=UInt32(count)
  guard let commands=queue.makeCommandBuffer(),let encoder=commands.makeComputeCommandEncoder() else {throw ComparisonFailure.device}
  encoder.setComputePipelineState(sampling)
  encoder.setBuffer(p,offset:0,index:0);encoder.setBuffer(ux,offset:0,index:1);encoder.setBuffer(uy,offset:0,index:2);encoder.setBuffer(uz,offset:0,index:3)
  encoder.setBuffer(cells,offset:0,index:4);encoder.setBuffer(weights,offset:0,index:5);encoder.setBuffer(velocityCells,offset:0,index:6);encoder.setBuffer(axes,offset:0,index:7)
  encoder.setBuffer(output,offset:0,index:8);encoder.setBuffer(velocityOutput,offset:0,index:9);encoder.setBytes(&abi,length:MemoryLayout<Grid>.stride,index:10)
  encoder.setBytes(&step,length:4,index:11);encoder.setBytes(&steps,length:4,index:12);encoder.setBytes(&receivers,length:4,index:13)
  encoder.dispatchThreads(MTLSize(width:count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:1,height:1,depth:1))
  encoder.endEncoding();commands.commit();commands.waitUntilCompleted();guard commands.status == .completed else {throw ComparisonFailure.device}
  let pp=output.contents().assumingMemoryBound(to:Float.self),vv=velocityOutput.contents().assumingMemoryBound(to:Float.self)
  return ((0..<count).map{Double(pp[$0])},(0..<count).map{plan.receivers[$0].velocityCell==nil ? nil : Double(vv[2*$0+1])})
 }
 struct Pattern {let omniShare:Double}
 struct Microphone {let isOmni:Bool;let pattern:Pattern}
 struct Receiver {let microphone:Microphone}
 func mix(_ plan:PreparedWaveObservation,_ values:[[Double]],_ projected:[[Double?]])->[[Double]] {
  let steps=values[0].count,c=grid.soundSpeed
  let receivers=plan.receivers.enumerated().map{i,s in Receiver(microphone:Microphone(isOmni:s.velocityCell==nil,pattern:Pattern(omniShare:i==0 ? 1 : (i==1 ? 0 : 0.3))))}
  let pressures=values.flatMap{$0.map(Float.init)},velocities=projected.flatMap{[Float(0)]+$0.map{Float($0 ?? 0)}}
'''+blocks['metal-microphone-timing']+'''
 }
'''
v.require(text.endswith('}\n'),'wrapper terminator');path.write_text(text[:-2]+methods+'}\n')
(target/'main.swift').write_text((root/'Fixtures/MetalWaveObservationSourceParity.swift').read_text())
(a.output/'observation-source-provenance.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print('Prepared exact original GPU sampling and microphone timing',manifest['repository']['revision'],a.output)
