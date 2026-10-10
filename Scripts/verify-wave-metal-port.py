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

forcing=json.loads((root/'docs/extraction/linear-wave-forcing-source.json').read_text())['metalBlock']
start=shader.index(forcing['selector']['startMarker'].encode());raw=shader[start:start+forcing['bytes']]
if hashlib.sha256(raw).hexdigest()!=forcing['sha256']:raise ValueError('ported shader block differs: metal-injection')
print('PASS exact pinned shader block: metal-injection',forcing['bytes'],'bytes')

observation=json.loads((root/'docs/extraction/linear-wave-observation-source.json').read_text())
block=next(b for b in observation['blocks'] if b['id']=='metal-observation')
start=shader.index(block['selector']['startMarker'].encode());raw=shader[start:start+block['bytes']]
if hashlib.sha256(raw).hexdigest()!=block['sha256']:raise ValueError('ported shader block differs: metal-observation')
adapt=observation['pressureOnlyAdaptation'];start=shader.index(b'            float value = 0;',shader.index(b'kernel void waveSamplePressure'))
raw=shader[start:start+adapt['retainedPressureStatementsBytes']]
if hashlib.sha256(raw).hexdigest()!=adapt['retainedPressureStatementsSHA256']:raise ValueError('pressure-only sampling statements differ')
print('PASS exact pinned observation kernel and pressure-only arithmetic')

# Mixed receivers retain the exact pinned arithmetic on both sides of the absent-probe guard.
full=shader[shader.index(b'kernel void waveSample('):shader.index(b'// Pressure-only port')]
mixed=shader[shader.index(b'kernel void waveSampleMixed('):]
pressure_start=b'            float value = 0;'
velocity_start=b'            uint plane = g.nx * g.ny;'
pressure_end=b'            uint at = velocityCells[r];'
if full[full.index(pressure_start):full.index(pressure_end)] != mixed[mixed.index(pressure_start):mixed.index(pressure_end)]:
 raise ValueError('mixed pressure statements differ from pinned kernel')
if full[full.index(velocity_start):full.index(b'        }')] != mixed[mixed.index(velocity_start):mixed.index(b'        }',mixed.index(velocity_start))]:
 raise ValueError('mixed velocity statements differ from pinned kernel')
guard=b'if (at == 0xffffffffu) {\n                velocityOutput[r * (steps + 1) + step + 1] = 0;\n                return;\n            }'
if guard not in mixed or mixed.index(guard)>mixed.index(velocity_start):raise ValueError('missing early absent-probe guard')
print('PASS mixed observation exact pinned pressure/velocity arithmetic and early absent-probe guard')
