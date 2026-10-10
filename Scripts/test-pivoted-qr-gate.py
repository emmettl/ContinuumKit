#!/usr/bin/env python3
"""Coherent corruption must fail independent numerical and producer contracts."""
import contextlib, copy, importlib.util, io, json, shutil, struct, sys, tempfile
from pathlib import Path
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('qr', Path(__file__).with_name('verify-pivoted-qr-output.py'))
qr = importlib.util.module_from_spec(spec); spec.loader.exec_module(qr)
root = Path(sys.argv[1]); records = json.loads((root/'results.json').read_text())['records']
raw = json.loads((root/'original-audit/original.json').read_text())
def scalar(v): return {'value':str(v),'bits':struct.pack('>d',v).hex()}
def reject(name, check):
    try:
        with contextlib.redirect_stdout(io.StringIO()): check()
    except (ValueError, KeyError, IndexError, TypeError): return
    raise AssertionError('accepted corruption: '+name)
controls = []
def target(data): return next(r for r in data if r['id']=='scale/3/0')
def control(name, mutate):
    changed = copy.deepcopy(records); mutate(changed)
    reject(name,lambda:qr.verify_records(changed,raw)); controls.append(name)
control('missing factor case',lambda d:d.pop())
control('duplicate case',lambda d:d.__setitem__(-1,d[0]))
control('native bits',lambda d:target(d)['rows'][0][0].__setitem__('bits','0'))
control('coherent matrix input',lambda d:target(d)['rows'][0].__setitem__(0,scalar(2.)))
control('coherent primary RHS input',lambda d:target(d)['primaryRHS'].__setitem__(0,scalar(2.)))
control('rank tolerance',lambda d:target(d).__setitem__('tolerance',scalar(.5)))
control('matrix scale',lambda d:target(d).__setitem__('matrixScaleExponent',1))
control('factor row dimensions',lambda d:target(d).__setitem__('rowCount',99))
control('permutation',lambda d:target(d).__setitem__('permutation',[0,0,0]))
control('complete Q',lambda d:target(d)['orthogonalColumns'].pop())
control('coherent Q value',lambda d:target(d)['orthogonalColumns'][0].__setitem__(0,scalar(2.)))
control('coherent triangular factor',lambda d:target(d)['scaledUpperTriangular'][0].__setitem__(0,scalar(2.)))
control('condition diagnostic',lambda d:target(d).__setitem__('reciprocalConditionEstimate',scalar(1.)))
control('repeated solve',lambda d:target(d).__setitem__('repeatPrimaryIdentical',False))
control('complete RHS tree',lambda d:target(d)['solves'].pop())
control('RHS identity',lambda d:target(d)['solves'][0]['rhs'].__setitem__(0,scalar(2.)))
control('complete predictions',lambda d:target(d)['solves'][0]['predictions'].pop())
control('residual diagnostic',lambda d:target(d)['solves'][0].__setitem__('scaledResidualNorm',scalar(1.)))
control('RHS scale',lambda d:target(d)['solves'][0].__setitem__('rhsScaleExponent',99))
control('factor error',lambda d:next(r for r in d if r['id']=='failure/empty').__setitem__('factorError','rankDeficient'))
def forged(d):
    row=target(d);s=row['solves'][0];x=qr.vector(s['coefficients']);x[0]+=1
    s['coefficients']=[scalar(v) for v in x]
    s['predictions']=[scalar(sum(v*w for v,w in zip(a,x))) for a in qr.matrix(row['rows'])]
control('coherent coefficients and all predictions',forged)
with tempfile.TemporaryDirectory(prefix='qr-source-controls-') as scratch:
    path=Path(scratch)
    for name,file,mutate in [
        ('source arithmetic','reference-sources/Sources/Numerics/PivotedQR.swift',lambda t:t+'\n'),
        ('dirty producer','environment.json',lambda t:t.replace('"workingTreeDirty": false','"workingTreeDirty": true')),
        ('consumer pin','consumer-Package.resolved',lambda t:t.replace(json.loads((root/'environment.json').read_text())['candidateRevision'],'0'*40)),
    ]:
        dest=path/name.replace(' ','-');dest.mkdir()
        shutil.copytree(root/'reference-sources',dest/'reference-sources')
        (dest/'original-audit').mkdir();shutil.copyfile(root/'original-audit/environment.json',dest/'original-audit/environment.json')
        for relative in ['environment.json','consumer-Package.resolved','linkage.txt']:shutil.copyfile(root/relative,dest/relative)
        f=dest/file;before=f.read_text();after=mutate(before);assert before!=after;f.write_text(after)
        reject(name,lambda:qr.verify_source(dest));controls.append(name)
(root/'controls.json').write_text(json.dumps({'schemaVersion':1,'rejectingControls':controls},indent=2,sort_keys=True)+'\n')
print(f'PASS {len(controls)} pivoted QR independent corruption controls')
