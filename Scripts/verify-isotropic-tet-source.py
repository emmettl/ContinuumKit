from pathlib import Path
import hashlib,json,subprocess,sys,tempfile
r=Path(__file__).resolve().parents[1]
m=json.loads((r/'docs/extraction/isotropic-tet-source.json').read_text())
source=(r/'Fixtures/IsotropicTetConsumer/Sources/FrozenTet/TargetIsotropicTet.swift').read_text()
assert hashlib.sha256(source.encode()).hexdigest()==m['sourceSHA256']
expected=source
for old,new in m['transformations']:expected=expected.replace(old,new)
assert (r/'Sources/SolidMechanics/IsotropicTetrahedron.swift').read_text()==expected
helper=(r/'Sources/SolidMechanics/TetWorkCorrection.swift').read_text().removeprefix('import simd\n\nenum TetWorkCorrection {\n').removesuffix('\n}\n')
assert hashlib.sha256(helper.encode()).hexdigest()==m['helperBlockSHA256']
assert (r/'Fixtures/IsotropicTetConsumer/Sources/FrozenTet/TetDependencies.swift').read_text()=='import simd\npublic enum TargetGeometryError: Error { case invalidDefinition }\nenum TargetImplicitFaceContact {\n'+helper+'\n}\n'
print('PASS immutable isotropic tetrahedron and corrected-gradient arithmetic; declared names/visibility only')

for path,sha in m['independentReferenceFiles'].items():
    assert hashlib.sha256((r/path).read_bytes()).hexdigest()==sha
with tempfile.TemporaryDirectory(prefix='continuum-tet-reference-') as directory:
    generated=Path(directory)/'reference.csv'
    fixtures=r/'Tests/SolidMechanicsTests/Fixtures/IsotropicTet'
    subprocess.run([sys.executable,str(fixtures/'reference.py'),str(generated)],check=True)
    assert generated.read_bytes()==(fixtures/'reference.csv').read_bytes()
print('PASS independent 45-digit Decimal three-law references')
