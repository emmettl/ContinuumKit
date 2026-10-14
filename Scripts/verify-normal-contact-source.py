from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]
m=json.loads((root/'docs/extraction/normal-contact-source.json').read_text())
source=(root/'Fixtures/NormalContactConsumer/Sources/FrozenContact/TargetNormalContactSolver.swift').read_bytes()
assert hashlib.sha256(source).hexdigest()==m['sourceSHA256']
assert (root/'Sources/SolidMechanics/NormalContactFlow.swift').read_text()==source.decode().replace('TargetNormalContactSolver','NormalContactFlow')
harness=(root/'Tests/SolidMechanicsTests/NormalContactVerification.swift').read_text().removeprefix('import SolidMechanics\n').replace('enum NormalContactVerification','@main enum TargetNormalContactStudy').replace('static func run() throws {','static func main() throws {').replace('NormalContactFlow','TargetNormalContactSolver')
assert hashlib.sha256(harness.encode()).hexdigest()==m['studySHA256']
print('PASS immutable normal-contact source and independent study; rename-only extraction')
