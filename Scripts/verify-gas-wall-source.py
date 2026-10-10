#!/usr/bin/env python3
"""Protect the immutable original used by the public wall-reference consumer."""
import hashlib, json
from pathlib import Path
root=Path(__file__).resolve().parent.parent
manifest=json.loads((root/'docs/extraction/ideal-gas-wall-source.json').read_text())
source=(root/'Fixtures/GasWallConsumer/Sources/GasWallConsumer/OriginalWall.swift').read_bytes()
blob=hashlib.sha1(b'blob '+str(len(source)).encode()+b'\0'+source).hexdigest()
assert hashlib.sha256(source).hexdigest()==manifest['sourceSHA256']
assert blob==manifest['sourceGitBlob']
assert manifest['revision']=='0b4943def5ec50064d1e44b9ab0ab249c2689b15'
print('PASS immutable original ideal-gas wall source hash and Git blob identity')
