#!/usr/bin/env python3
"""Bind immutable original masked CPU injection beside shared forcing; output is private evidence."""
import argparse,hashlib,importlib.util,json,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--roomcad',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'docs/extraction/linear-wave-forcing-source.json').read_text())
spec=importlib.util.spec_from_file_location('wave_source_map',root/'Scripts/verify-wave-extraction-source.py')
v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
block=manifest['block'];revision=manifest['repository']['revision']
source=subprocess.check_output(['git','show',revision+':'+block['path']],cwd=a.roomcad).decode()
start,end=v.selected_block(source,block['selector']);injection=source[start:end]
v.require(len(injection.encode())==block['bytes'] and hashlib.sha256(injection.encode()).hexdigest()==block['sha256'],'pinned injection block mismatch')
# The base preparer independently verifies the full source file and all three update blocks.
subprocess.run([sys.executable,str(root/'Scripts/prepare-wave-source-parity.py'),'--roomcad',str(a.roomcad),'--output',str(a.output)],check=True)
target=a.output/'Sources/WaveSourceParity';path=target/'SourceCPU.swift';text=path.read_text()
text=text.replace('func advance(_ steps:Int) {','func advance(_ amplitudes:[Double], sourceWeights:[(Int,Float)]) {\n  let steps=amplitudes.count')
text=text.replace('for _ in 0..<steps {','for step in 0..<steps {')
text=text.replace(' pressureStepIndex+=1',' let q=amplitudes[step]\n'+injection+' pressureStepIndex+=1')
path.write_text(text)
(target/'main.swift').write_text((root/'Fixtures/WaveForcedSourceParity.swift').read_text())
(a.output/'forcing-source-provenance.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
print('Prepared exact original masked injection and updates at',a.output,'from',revision)
