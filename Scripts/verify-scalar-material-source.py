"""Check immutable P2 source, independent fixtures and rename-only extraction."""
from pathlib import Path
import gzip, hashlib, json, subprocess, sys, tempfile
root = Path(__file__).resolve().parents[1]
manifest = json.loads((root/'docs/extraction/scalar-material-source.json').read_text())
for kind in ('Compression', 'Damage'):
    app_path = f'Sources/EdgertonCore/TargetVeneer{kind}.swift'
    original = (root/f'Fixtures/ScalarMaterialConsumer/Sources/FrozenP2/TargetVeneer{kind}.swift').read_bytes()
    assert hashlib.sha256(original).hexdigest() == manifest['files'][app_path]['sha256'], app_path
    expected = original.decode().replace(f'TargetVeneer{kind}', f'Veneer{kind}')
    assert (root/f'Sources/SolidMechanics/Veneer{kind}.swift').read_text() == expected, kind
    harness = (root/f'Tests/SolidMechanicsTests/P2{kind}Verification.swift').read_text()
    original_harness = harness.removeprefix('import SolidMechanics\n').replace('enum P2'+kind+'Verification', '@main enum '+kind+'Study').replace('static func run(_ args: [String]) throws {', 'static func main() throws {\n        let args = CommandLine.arguments').replace('Veneer'+kind, 'TargetVeneer'+kind).replace('OrthotropicPlaneStress', 'TargetOrthotropicPlaneStress')
    study_path = f'Studies/TargetMechanics/PlywoodP2{kind}/{kind}Study.swift'
    assert hashlib.sha256(original_harness.encode()).hexdigest() == manifest['files'][study_path]['sha256'], study_path
    fixtures = root/f'Tests/SolidMechanicsTests/Fixtures/P2{kind}'
    for name in ('input.json', 'reference.py', 'reference.csv'):
        data = gzip.decompress((fixtures/(name+'.gz')).read_bytes()) if name.endswith('.csv') else (fixtures/name).read_bytes()
        source = f'Studies/TargetMechanics/PlywoodP2{kind}/' + ('evidence/' if name.endswith('.csv') else '') + name
        assert hashlib.sha256(data).hexdigest() == manifest['files'][source]['sha256'], source
    with tempfile.TemporaryDirectory(prefix='continuum-p2-reference-') as directory:
        regenerated = Path(directory)/'reference.csv'
        subprocess.run([sys.executable, str(fixtures/'reference.py'), str(fixtures/'input.json'), str(regenerated)], check=True, stdout=subprocess.DEVNULL)
        assert regenerated.read_bytes() == gzip.decompress((fixtures/'reference.csv.gz').read_bytes()), 'independent generator changed '+kind
print('PASS immutable P2 source/input/independent-reference guards; rename-only laws')
