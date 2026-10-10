#!/usr/bin/env python3
"""Compile only the exact original affine loops; exclude acoustic window/noise policy."""
import argparse,hashlib,json
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
r=Path(__file__).resolve().parent.parent/'Fixtures/AffineFitAudit';m=json.loads((r/'source.json').read_text());texts={}
expected={'Sources/AcousticCore/RoomParameters.swift':('3b5c0e8761ee54b63e0a19b51596673bd702a780','ad897708b1e654796786cc7745a68ed88817343df3589f66ff011bc57c6996da'),'Sources/AcousticCore/DecayAnalysis.swift':('63fc6c90bb524f50b1b18adddcdd55496d6581c0','931363a156f4b52d6c390385ba5cce3f733f9a9742281ffc2063e50f575922b1')}
assert m['revision']=='37d7f8a0491dc4bc1908e71a8e8f63c0f4fd055b' and set(m['sources'])==set(expected)
for path,s in m['sources'].items():
 raw=(r/s['snapshot']).read_bytes();blob=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest();sha=hashlib.sha256(raw).hexdigest();assert (blob,sha)==expected[path] and s['gitBlob']==blob and s['sha256']==sha,path;texts[path]=raw.decode()
room=texts['Sources/AcousticCore/RoomParameters.swift'];start=room.index('    private static func line(');end=room.index('\n    private static func slopePerSecond',start)
line=room[start:end].replace('    private static func line(','    static func line(',1)
decay=texts['Sources/AcousticCore/DecayAnalysis.swift'];start=decay.index('        let n = Double(last - first + 1)');end=decay.index('\n        return slope < 0',start);loop=decay[start:end]
# These are structural visibility/binding adaptations only. Numerical loop text
# is inserted verbatim and checked; no coordinate, summation or arithmetic edits.
source='import Foundation\nenum OriginalIndexFit {\n'+line+'\n}\nenum OriginalTimeFit {\n    static func slope(_ curve: [Double], first: Int, last: Int, sampleRate: Int) -> Double {\n'+loop+'\n        return slope\n    }\n}\n'
a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(source)
print('PASS protected RoomCAD fitting sources and verbatim numerical-loop bindings')
