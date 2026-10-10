#!/usr/bin/env python3
"""Expose only fixture visibility and reversible observation hooks; retain QR arithmetic."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args();r=Path(__file__).resolve().parent.parent/'Fixtures/WeightedQRAudit';m=json.loads((r/'source.json').read_text())
expected={'Sources/BlastCore/FiniteVolumePressureFit.swift':('31e58a31f681d81b8379fc7e81a000f75ba8df8d','8120e41b29cd28d68c731a96b637bd8db56f6b08c3871241a3f51e5c9c95f7f2'),'Sources/BlastCore/ConservedGasReconstruction.swift':('3e2b5dffd343f26dd0957ac76fdbe3841fcc444a','55ccef8419142735965d7b19b7f961f903546f3bc1d4a0684893b6fd6df59d72'),'Tests/BlastCoreTests/FiniteVolumePressureFitTests.swift':('12edbd8f5298a3a77d0a0a471e69d9229d2e6e52','ca1fbf9ea3afe5db2823d1e07aa90ce6bbc737b51df885daf11c50225375fddb')}
assert m['revision']=='5f2e50dcef5a5adcde3d3c4cb811426e6de2fe6c' and set(m['sources'])==set(expected)
for path,entry in m['sources'].items():
 raw=(r/entry['snapshot']).read_bytes();blob=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest();sha=hashlib.sha256(raw).hexdigest();assert (blob,sha)==expected[path] and entry['gitBlob']==blob and entry['sha256']==sha
raw=(r/m['sources']['Sources/BlastCore/FiniteVolumePressureFit.swift']['snapshot']).read_text();text=raw;patches=[]
def patch(old,new,label):
 global text
 assert text.count(old)==1,label;text=text.replace(old,new);patches.append({'label':label,'original':old,'traced':new})
patch('    private struct QR {','    struct QR {','fixture-only private QR visibility')
anchor='            let weighted = rows.enumerated().map { n, row in row.map { $0 * distanceWeights[n] } }'
patch(anchor,anchor+'\n            QRAuditHook.rows = weighted\n            QRAuditHook.weights = distanceWeights','capture actual weighted rows')
anchor='            let rhs = zip(neighbourAverages, weights).map { ($0.0 - average) * $0.1 }'
patch(anchor,anchor+'\n            QRAuditHook.rhs = rhs','capture actual weighted RHS')
restored=text
for entry in reversed(patches):assert restored.count(entry['traced'])==1;restored=restored.replace(entry['traced'],entry['original'])
assert restored==raw
source='enum QRAuditHook {\n    nonisolated(unsafe) static var rows: [[Double]] = []\n    nonisolated(unsafe) static var weights: [Double] = []\n    nonisolated(unsafe) static var rhs: [Double] = []\n}\n'+text
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(source);a.output.with_suffix('.bindings.json').write_text(json.dumps({'schemaVersion':1,'originalSHA256':hashlib.sha256(raw.encode()).hexdigest(),'compiledSHA256':hashlib.sha256(source.encode()).hexdigest(),'patches':patches,'scope':'only private visibility and observation hooks; complete original QR/Stencil arithmetic unchanged'},indent=2,sort_keys=True)+'\n')
print('PASS protected current BombCAD QR/Stencil source and reversible non-arithmetic bindings')
