#!/usr/bin/env python3
"""Prepare a temporary exact-block RoomCAD CPU comparison consumer from pinned Git source.

Generated app-derived source/results belong outside the public repository. This tool
never reads working app files or modifies its checkout. Build using the same flags
as the candidate. Run the generated consumer with one private output JSON path.
"""
import argparse
import hashlib
import importlib.util
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--roomcad', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root/'docs/extraction/linear-wave-source.json').read_text())
spec = importlib.util.spec_from_file_location('wave_source_map', root/'Scripts/verify-wave-extraction-source.py')
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)
revision = manifest['repositories']['roomcad']['revision']
entry = next(f for f in manifest['files'] if f['path']=='Sources/AcousticCore/WaveSolver.swift')
raw = subprocess.check_output(['git','show',revision+':'+entry['path']],cwd=args.roomcad)
verifier.require(hashlib.sha256(raw).hexdigest()==entry['sha256'] and len(raw)==entry['bytes'], 'pinned RoomCAD source mismatch')
source = raw.decode()
blocks = {}
for block in manifest['blocks']:
    if not block['id'].startswith('cpu-masked-'):
        continue
    start,end = verifier.selected_block(source,block['selector'])
    data = source[start:end].encode()
    verifier.require(hashlib.sha256(data).hexdigest()==block['sha256'] and len(data)==block['bytes'],block['id'])
    blocks[block['id']]=data.decode()
args.output.mkdir(parents=True,exist_ok=False)
target = args.output/'Sources/WaveSourceParity'
target.mkdir(parents=True)
(target/'SourceCPU.swift').write_text('''// Generated from immutable RoomCAD MIT source; Copyright (c) 2026 Louis Emmett.
import LinearAcoustics
final class SourceCPU {
 let grid:PreparedWaveGrid
 let p,ux,uy,uz:UnsafeMutablePointer<Float>
 var pressureStepIndex=0
 init(_ grid:PreparedWaveGrid,_ f:WaveInitialFields) {
  self.grid=grid
  func copy(_ values:[Float])->UnsafeMutablePointer<Float> {
   let b=UnsafeMutablePointer<Float>.allocate(capacity:values.count)
   values.withUnsafeBufferPointer{b.initialize(from:$0.baseAddress!,count:values.count)}
   return b
  }
  p=copy(f.pressureOverDensity);ux=copy(f.velocityX);uy=copy(f.velocityY);uz=copy(f.velocityZ)
 }
 deinit {for f in [p,ux,uy,uz]{f.deinitialize(count:grid.cellCount);f.deallocate()}}
 func fields()->[[Float]]{[p,ux,uy,uz].map{Array(UnsafeBufferPointer(start:$0,count:grid.cellCount))}}
 func advance(_ steps:Int) {
  let nx=grid.dimensions.x,ny=grid.dimensions.y,nz=grid.dimensions.z,plane=nx*ny,slabs=1
  let c=grid.soundSpeed,dt=grid.timeStep,spacing=grid.spacing,count=grid.cellCount
  let inside=grid.activeCells.map{$0==1}
  let faces=(0..<6).map{Array(grid.boundaryTerms[($0*count)..<(($0+1)*count)])}
  func forEachSlab(_ body:(Int)->Void){body(0)}
'''+blocks['cpu-masked-coefficients']+'''for _ in 0..<steps {
'''+blocks['cpu-masked-velocity']+blocks['cpu-masked-pressure']+'''
 pressureStepIndex+=1
 }
 }
}
''')
(target/'main.swift').write_text((root/'Fixtures/WaveSourceParity.swift').read_text())
(args.output/'Package.swift').write_text('''// swift-tools-version: 6.4
import Foundation
import PackageDescription
let env=ProcessInfo.processInfo.environment
let package=Package(name:"WaveSourceParity",platforms:[.macOS(.v15)],
 dependencies:[.package(url:URL(fileURLWithPath:env["CONTINUUMKIT_CONSUMER_SOURCE"]!).absoluteString,revision:env["CONTINUUMKIT_CONSUMER_REVISION"]!)],
 targets:[.executableTarget(name:"WaveSourceParity",dependencies:[.product(name:"LinearAcoustics",package:"continuumkit")])],swiftLanguageModes:[.v6])
''')
print('Prepared three exact pinned blocks at',args.output,'from',revision)
