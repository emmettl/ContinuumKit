#!/usr/bin/env python3
"""Create a fetched CPU comparison with the exact alpha.8 stepper body as baseline."""
import argparse, hashlib, json, shutil, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--core',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
baseline='2aecacbc3da082382cb11639d67af0ea37583272'
source='Sources/LinearAcoustics/CPUWaveStepper.swift'
raw=subprocess.check_output(['git','show',baseline+':'+source],cwd=a.core)
text=raw.decode();body=text[text.index('public final class CPUWaveStepper {'):]
assert body.count('CPUWaveStepper')==1
adapted=body.replace('public final class CPUWaveStepper {','final class Alpha8CPUWaveStepper {',1)
shutil.copytree(a.core/'Fixtures/CPUWaveThroughput',a.output)
(a.output/'Sources/CPUWaveThroughput/Alpha8CPUWaveStepper.swift').write_text('// Copyright (c) 2026 Louis Emmett. MIT licence; see LICENSE.\n// Exact alpha.8 class body, with only its class name changed.\nimport LinearAcoustics\n'+adapted)
provenance={'schemaVersion':1,'baseline':baseline,'source':source,'sourceSHA256':hashlib.sha256(raw).hexdigest(),'classSHA256':hashlib.sha256(body.encode()).hexdigest(),'adaptedClassSHA256':hashlib.sha256(adapted.encode()).hexdigest(),'adaptation':'only class name changed; public grid/source/frame value types supplied by fetched candidate'}
(a.output/'baseline-source-provenance.json').write_text(json.dumps(provenance,indent=2,sort_keys=True)+'\n')
