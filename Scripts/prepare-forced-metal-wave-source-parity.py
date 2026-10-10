#!/usr/bin/env python3
"""Bind exact pinned GPU injection/update kernels beside shared resident forcing; retain outputs privately."""
import argparse,hashlib,importlib.util,json,re,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--roomcad',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];manifest=json.loads((root/'docs/extraction/linear-wave-forcing-source.json').read_text())
spec=importlib.util.spec_from_file_location('source_map',root/'Scripts/verify-wave-extraction-source.py');v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
block=manifest['metalBlock'];revision=manifest['repository']['revision']
source=subprocess.check_output(['git','show',revision+':'+block['path']],cwd=a.roomcad).decode();start,end=v.selected_block(source,block['selector']);kernel=source[start:end]
v.require(len(kernel.encode())==block['bytes'] and hashlib.sha256(kernel.encode()).hexdigest()==block['sha256'],'pinned Metal injection block')
subprocess.run([sys.executable,str(root/'Scripts/prepare-metal-wave-source-parity.py'),'--roomcad',str(a.roomcad),'--output',str(a.output)],check=True)
target=a.output/'Sources/MetalSourceParity';path=target/'SourceGPU.swift';text=path.read_text()
m=re.search(r' static let source=(.*)\n init',text);v.require(m is not None,'source declaration')
msl=json.loads(m.group(1))+kernel;text=text[:m.start(1)]+json.dumps(msl)+text[m.end(1):]
text=text.replace('let velocity,pressure:any MTLComputePipelineState','let velocity,pressure,injection:any MTLComputePipelineState')
text=text.replace('  func buffer<T>', '  injection=try device.makeComputePipelineState(function:library.makeFunction(name:"waveInject")!)\n  func buffer<T>')
text=text.replace('func advance(_ steps:Int) throws {','func advance(_ amplitudes:[Double], cells:[Int], weights:[Float]) throws {\n  let steps=amplitudes.count')
needle='  for _ in 0..<steps {'
replacement='''  func buffer<T>(_ values:[T]) throws -> any MTLBuffer {
   try values.withUnsafeBytes { raw in
    guard let b=queue.device.makeBuffer(bytes:raw.baseAddress!,length:raw.count,options:.storageModeShared) else {throw ComparisonFailure.device};return b
   }
  }
  let q=try buffer(amplitudes.map(Float.init)),sourceCells=try buffer(cells.map(UInt32.init)),sourceWeights=try buffer(weights)
  var sourceCount=UInt32(cells.count)
  for n in 0..<steps {'''
v.require(needle in text,'update loop');text=text.replace(needle,replacement)
needle='  }\n  encoder.endEncoding()'
replacement='''   var step=UInt32(n)
   encoder.setComputePipelineState(injection)
   encoder.setBuffer(p,offset:0,index:0);encoder.setBuffer(q,offset:0,index:1);encoder.setBuffer(sourceCells,offset:0,index:2);encoder.setBuffer(sourceWeights,offset:0,index:3)
   encoder.setBytes(&step,length:4,index:4);encoder.setBytes(&sourceCount,length:4,index:5)
   encoder.dispatchThreads(MTLSize(width:cells.count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:8,height:1,depth:1))
  }
  encoder.endEncoding()'''
v.require(needle in text,'command termination');text=text.replace(needle,replacement)
path.write_text(text);(target/'main.swift').write_text((root/'Fixtures/MetalWaveForcedSourceParity.swift').read_text())
(a.output/'forcing-source-provenance.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print('Prepared exact original GPU injection/update kernels',revision,a.output)
