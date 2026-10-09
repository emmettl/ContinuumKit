#!/usr/bin/env python3
"""Prepare a private, temporary exact-kernel RoomCAD/Metal consumer from pinned Git source."""
import argparse,hashlib,importlib.util,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--roomcad',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'docs/extraction/linear-wave-source.json').read_text())
spec=importlib.util.spec_from_file_location('source_map',root/'Scripts/verify-wave-extraction-source.py');verifier=importlib.util.module_from_spec(spec);spec.loader.exec_module(verifier)
entry=next(f for f in manifest['files'] if f['path']=='Sources/AcousticCore/MetalWaveSolver.swift')
revision=manifest['repositories']['roomcad']['revision']
raw=subprocess.check_output(['git','show',revision+':'+entry['path']],cwd=a.roomcad)
verifier.require(len(raw)==entry['bytes'] and hashlib.sha256(raw).hexdigest()==entry['sha256'],'pinned RoomCAD Metal source')
blocks={}
for block in manifest['blocks']:
 if block['id'] not in ['metal-swift-grid-abi','metal-grid-abi','metal-velocity','metal-pressure']:continue
 start,end=verifier.selected_block(raw.decode(),block['selector']);text=raw.decode()[start:end]
 verifier.require(len(text.encode())==block['bytes'] and hashlib.sha256(text.encode()).hexdigest()==block['sha256'],block['id'])
 blocks[block['id']]=text
msl='#include <metal_stdlib>\nusing namespace metal;\n'+blocks['metal-grid-abi']+blocks['metal-velocity']+blocks['metal-pressure']
a.output.mkdir(parents=True,exist_ok=False);target=a.output/'Sources/MetalSourceParity';target.mkdir(parents=True)
wrapper='''// Generated from immutable RoomCAD MIT source. Copyright (c) 2026 Louis Emmett.
import Foundation
import LinearAcoustics
import Metal
final class SourceGPU {
 let p,ux,uy,uz,inside,faces:any MTLBuffer
 let queue:any MTLCommandQueue
 let velocity,pressure:any MTLComputePipelineState
 let grid:PreparedWaveGrid
 var pressureStepIndex=0
'''+blocks['metal-swift-grid-abi']+''' static let source='''+json.dumps(msl)+'''
 init(_ device:any MTLDevice,_ g:PreparedWaveGrid,_ f:WaveInitialFields) throws {
  grid=g
  guard let q=device.makeCommandQueue() else {throw ComparisonFailure.device};queue=q
  let library=try device.makeLibrary(source:Self.source,options:nil)
  guard let v=library.makeFunction(name:"waveVelocity"),let p=library.makeFunction(name:"wavePressure") else {throw ComparisonFailure.device}
  velocity=try device.makeComputePipelineState(function:v);pressure=try device.makeComputePipelineState(function:p)
  func buffer<T>(_ values:[T]) throws -> any MTLBuffer {
   try values.withUnsafeBytes { raw in
    guard let b=device.makeBuffer(bytes:raw.baseAddress!,length:raw.count,options:.storageModeShared) else {throw ComparisonFailure.device};return b
   }
  }
  self.p=try buffer(f.pressureOverDensity);ux=try buffer(f.velocityX);uy=try buffer(f.velocityY);uz=try buffer(f.velocityZ)
  inside=try buffer(g.activeCells);faces=try buffer(g.boundaryTerms)
 }
 func fields()->[[Float]] {[p,ux,uy,uz].map {Array(UnsafeBufferPointer(start:$0.contents().assumingMemoryBound(to:Float.self),count:grid.cellCount))}}
 func advance(_ steps:Int) throws {
  let g=grid,c=g.soundSpeed,dt=g.timeStep,d=g.spacing
  var abi=Grid(nx:UInt32(g.dimensions.x),ny:UInt32(g.dimensions.y),nz:UInt32(g.dimensions.z),
   kx:Float(dt/d.x),ky:Float(dt/d.y),kz:Float(dt/d.z),bx:Float(c*c*dt/d.x),by:Float(c*c*dt/d.y),bz:Float(c*c*dt/d.z))
  guard let commands=queue.makeCommandBuffer(),let encoder=commands.makeComputeCommandEncoder() else {throw ComparisonFailure.device}
  let threads=MTLSize(width:g.dimensions.x,height:g.dimensions.y,depth:g.dimensions.z),group=MTLSize(width:32,height:4,depth:2)
  for _ in 0..<steps {
   encoder.setComputePipelineState(velocity)
   encoder.setBuffer(p,offset:0,index:0);encoder.setBuffer(ux,offset:0,index:1);encoder.setBuffer(uy,offset:0,index:2);encoder.setBuffer(uz,offset:0,index:3)
   encoder.setBuffer(inside,offset:0,index:4);encoder.setBytes(&abi,length:MemoryLayout<Grid>.stride,index:5)
   encoder.dispatchThreads(threads,threadsPerThreadgroup:group)
   encoder.setComputePipelineState(pressure)
   encoder.setBuffer(faces,offset:0,index:5);encoder.setBytes(&abi,length:MemoryLayout<Grid>.stride,index:6)
   encoder.dispatchThreads(threads,threadsPerThreadgroup:group)
  }
  encoder.endEncoding();commands.commit();commands.waitUntilCompleted()
  guard commands.status == .completed else {throw ComparisonFailure.device}
  pressureStepIndex+=steps
 }
}
'''
(target/'SourceGPU.swift').write_text(wrapper)
(target/'main.swift').write_text((root/'Fixtures/MetalWaveSourceParity.swift').read_text())
(a.output/'Package.swift').write_text('''// swift-tools-version: 6.4
import Foundation
import PackageDescription
let env=ProcessInfo.processInfo.environment
let package=Package(name:"MetalSourceParity",platforms:[.macOS(.v15)],
 dependencies:[.package(url:URL(fileURLWithPath:env["CONTINUUMKIT_CONSUMER_SOURCE"]!).absoluteString,revision:env["CONTINUUMKIT_CONSUMER_REVISION"]!)],
 targets:[.executableTarget(name:"MetalSourceParity",dependencies:[.product(name:"LinearAcoustics",package:"continuumkit"),.product(name:"LinearAcousticsMetal",package:"continuumkit")])],swiftLanguageModes:[.v6])
''')
print('Prepared exact Swift/Metal ABI and two pinned kernels:',revision,a.output)
