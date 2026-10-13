#!/usr/bin/env python3
"""Require frozen P1 oracle identity and the explicitly renamed kernel."""
import hashlib
import json
from pathlib import Path
r = Path(__file__).resolve().parents[1]
s = json.loads((r/'docs/extraction/orthotropic-plane-stress-source.json').read_text())
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
assert sha(r/'Sources/SolidMechanics/OrthotropicPlaneStress.swift') == s['extractedKernelSHA256'], 'kernel change requires reviewed evidence version'
for name in ['input.json', 'reference.py', 'constitutive-reference.csv', 'bending-reference.csv', 'rotated-reference.csv']:
    expected = [v for k,v in s['sourceHashes'].items() if k.endswith('/'+name)]
    assert len(expected) == 1
    assert sha(r/'Tests/SolidMechanicsTests/Fixtures'/name) == expected[0], name
    consumer = r/'Fixtures/OrthotropicConsumer/Sources/OrthotropicConsumer/Fixtures'/name
    if consumer.exists():
        assert sha(consumer) == expected[0], 'consumer '+name
print('PASS immutable P1 independent fixture and extracted kernel identities')
