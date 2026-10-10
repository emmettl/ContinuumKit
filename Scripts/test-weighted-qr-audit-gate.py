#!/usr/bin/env python3
"""Prove incomplete/corrupt evidence rejects and coherent numerical errors are findings."""
import contextlib, copy, importlib.util, io, json, shutil, struct, sys, tempfile
from pathlib import Path
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('audit', Path(__file__).with_name('verify-weighted-qr-audit.py'))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)
root = Path(sys.argv[1])
data = json.loads((root / 'original.json').read_text())
def scalar(v):
    return {'value': str(v), 'bits': struct.pack('>d', v).hex()}
def reject(name, check):
    try:
        with contextlib.redirect_stdout(io.StringIO()):
            check()
    except (ValueError, KeyError, IndexError, TypeError):
        return
    raise AssertionError('audit accepted corruption: ' + name)
controls = []
def control(name, mutate):
    changed = copy.deepcopy(data)
    mutate(changed)
    reject(name, lambda: audit.verify_data(changed))
    controls.append(name)
control('missing direct case', lambda d: d['direct'].pop())
control('duplicate direct case', lambda d: d['direct'].__setitem__(-1, d['direct'][0]))
control('missing stencil', lambda d: d['geometry'].pop())
control('duplicate stencil', lambda d: d['geometry'].__setitem__(-1, d['geometry'][0]))
control('native bits', lambda d: d['direct'][0]['rows'][0][0].__setitem__('bits', '0'))
control('coherent changed matrix input', lambda d: d['direct'][0]['rows'][0].__setitem__(0, scalar(2.0)))
control('coherent changed rhs input', lambda d: d['direct'][0]['rhs'].__setitem__(0, scalar(2.0)))
control('parameter identity', lambda d: d['geometry'][0]['parameters'].__setitem__('origin', 99))
control('sample identity', lambda d: d['geometry'][0]['cell']['centre'].__setitem__(0, scalar(2.0)))
control('weighted basis', lambda d: d['geometry'][0]['rows'][0].__setitem__(0, scalar(2.0)))
control('distance weight', lambda d: d['geometry'][0]['weights'].__setitem__(0, scalar(2.0)))
control('complete factor vectors', lambda d: next(r for r in d['direct'] if r['factorAccepted'])['vectors'].pop())
control('query coverage', lambda d: d['geometry'][0]['queries'].pop())
control('query identity', lambda d: d['geometry'][0]['queries'][0]['point'].__setitem__(0, scalar(2.0)))
control('degree fallback', lambda d: d['geometry'][0].__setitem__('degree', 0))
# Updating coefficients and every derived prediction coherently must still expose
# the disagreement with the independent exact-native least-squares solution.
changed = copy.deepcopy(data)
row = next(r for r in changed['direct'] if r['id'] == 'direct/3/common/0/false/false')
coeff = audit.vector(row['coefficients']); coeff[0] += 1
row['coefficients'] = [scalar(v) for v in coeff]
row['predictions'] = [scalar(sum(v*w for v,w in zip(values, coeff))) for values in audit.matrix(row['rows'])]
finding = next(r for r in audit.verify_data(changed)['findings'] if r['id'] == row['id'])
assert finding['classification'] == 'finite_coefficient_inaccuracy'
with tempfile.TemporaryDirectory(prefix='weighted-qr-controls-') as scratch:
    path = Path(scratch)
    for name, file, mutate in [
        ('source snapshot', 'source/FiniteVolumePressureFit.swift.txt', lambda t: t + '\n'),
        ('compiled arithmetic', 'compiled-original.swift', lambda t: t.replace('1e-10', '1e-8')),
        ('producer source hash', 'environment.json', lambda t: t.replace('"workingTreeDirty": false', '"workingTreeDirty": true')),
        ('source revision', 'source/source.json', lambda t: t.replace('5f2e50dcef5a5adcde3d3c4cb811426e6de2fe6c', '0'*40)),
        ('reversible bindings', 'bindings.json', lambda t: t.replace('    struct QR {', '    struct WrongQR {')),
    ]:
        target = path / name.replace(' ', '-')
        target.mkdir()
        for relative in ['source', 'scripts']:
            shutil.copytree(root / relative, target / relative)
        for relative in ['compiled-original.swift', 'environment.json', 'bindings.json']:
            shutil.copyfile(root / relative, target / relative)
        f = target / file; before = f.read_text(); after = mutate(before)
        assert before != after, name
        f.write_text(after)
        reject(name, lambda: audit.verify_provenance(target))
        controls.append(name)
receipt = {'schemaVersion': 1, 'rejectingControls': controls, 'coherentCoefficientChange': finding['classification']}
(root / 'controls.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
print(f'PASS {len(controls)} rejecting corruption controls and one coherent coefficient-change finding')
