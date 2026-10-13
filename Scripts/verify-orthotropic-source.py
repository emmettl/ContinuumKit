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
original = (r/'Sources/SolidMechanics/OrthotropicPlaneStress.swift').read_bytes().replace(b'OrthotropicPlaneStress', b'TargetOrthotropicPlaneStress')
assert hashlib.sha256(original).hexdigest() == s['sourceHashes']['Sources/EdgertonCore/TargetOrthotropicPlaneStress.swift'], 'extraction exceeded public type rename'
assert sha(r/'Fixtures/OrthotropicConsumer/Sources/FrozenP1/TargetOrthotropicPlaneStress.swift') == s['sourceHashes']['Sources/EdgertonCore/TargetOrthotropicPlaneStress.swift'], 'frozen original changed'
for name in ['input.json', 'reference.py', 'constitutive-reference.csv', 'bending-reference.csv', 'rotated-reference.csv']:
    expected = [v for k,v in s['sourceHashes'].items() if k.endswith('/'+name)]
    assert len(expected) == 1
    assert sha(r/'Tests/SolidMechanicsTests/Fixtures'/name) == expected[0], name
    consumer = r/'Fixtures/OrthotropicConsumer/Sources/OrthotropicConsumer/Fixtures'/name
    if consumer.exists():
        assert sha(consumer) == expected[0], 'consumer '+name
print('PASS immutable P1 independent fixture and extracted kernel identities')
