#!/usr/bin/env python3
"""Verify the packaged Metal Grid and kernels retain their exact pinned source blocks."""
import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
manifest=json.loads((root/'docs/extraction/linear-wave-source.json').read_text())
shader=(root/'Sources/LinearAcousticsMetal/Shaders/WaveUpdate.metal').read_bytes()
for block in manifest['blocks']:
 if block['id'] not in ['metal-grid-abi','metal-velocity','metal-pressure']:continue
 start=shader.index(block['selector']['startMarker'].encode())
 raw=shader[start:start+block['bytes']]
 if hashlib.sha256(raw).hexdigest()!=block['sha256']:
  raise ValueError('ported shader block differs: '+block['id'])
 print('PASS exact pinned shader block:',block['id'],block['bytes'],'bytes')
