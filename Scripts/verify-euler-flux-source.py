#!/usr/bin/env python3
"""Protect original source and restrict extraction to access/type-name/documentation changes."""
import hashlib,json,re
from pathlib import Path
r=Path(__file__).resolve().parent.parent
m=json.loads((r/'docs/extraction/euler-flux-source.json').read_text())
original=(r/m['immutableOriginal']).read_bytes()
assert hashlib.sha256(original).hexdigest()==m['sha256']=='d80e566a9938f665d71ee00bb813e934bb5febff1a112920200fd47560c818c5'
assert hashlib.sha1(b'blob '+str(len(original)).encode()+b'\0'+original).hexdigest()==m['blob']=='4736724d8bf71dd84ebb8bde48c0b10b7953a474'
assert m['revision']=='063d6fe818fd78ccbfe46c1c79e035f04de03800'
def normalized(s):
 s=re.sub(r'//[^\n]*','',s)
 s=re.sub(r'\bpublic\s+','',s)
 s=s.replace(': Equatable, Sendable','').replace('Error, Equatable','Error')
 s=s.replace('FractionalGasTransport','PrescribedGasTransport')
 return re.sub(r'\s+','',s)
assert normalized(original.decode())==normalized((r/'Sources/CompressibleFlow/FractionalEulerFlux.swift').read_text()),'numerical source changed'
print('PASS immutable Euler source SHA/blob and unchanged normalized numerical implementation')
