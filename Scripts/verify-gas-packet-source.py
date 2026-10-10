#!/usr/bin/env python3
"""Protect the original packet source against changes or inferred provenance."""
import hashlib,json
from pathlib import Path
r=Path(__file__).resolve().parent.parent
m=json.loads((r/'docs/extraction/gas-packet-source.json').read_text())
s=(r/m['immutableOriginal']).read_bytes()
assert hashlib.sha256(s).hexdigest()==m['sourceSHA256']=='9a3bccd54cd6448bb468ccd71e6d0f391ccd6f6f19f9661f6c250f2c9daa02a7'
assert hashlib.sha1(b'blob '+str(len(s)).encode()+b'\0'+s).hexdigest()==m['sourceGitBlob']=='af65c142dbd6dfaffe8ccbb516c0b846d62c4086'
assert m['revision']=='8ec83cb524d1e745c0793106b0d78a7269131030'
print('PASS immutable original prescribed-gas packet source SHA-256 and Git blob')
