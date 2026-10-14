from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]
m=json.loads((r/'docs/extraction/gmres-source.json').read_text())
engine=(r/'Sources/Numerics/GMRESImplementation.swift').read_text().removeprefix('#if canImport(simd)\n').removesuffix('#endif\n').replace('GMRESImplementation','TargetKrylov')
assert hashlib.sha256(engine.encode()).hexdigest()==m['sourceSHA256']
frozen=(r/'Fixtures/GMRESConsumer/Sources/FrozenGMRES/TargetKrylov.swift').read_text().replace('public enum TargetKrylov','enum TargetKrylov').replace('    public typealias Vector','    typealias Vector').replace('    public static func solve','    static func solve')
assert frozen==engine
print('PASS immutable GMRES engine and verification-only visibility changes')
