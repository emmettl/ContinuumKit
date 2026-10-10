#!/usr/bin/env python3
import copy,importlib.util,json,sys
from pathlib import Path
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('audit',Path(__file__).with_name('verify-affine-fit-audit.py'));a=importlib.util.module_from_spec(spec);spec.loader.exec_module(a)
cases=json.loads((Path(sys.argv[1])/'original.json').read_text())
controls={'missing case':cases[:-1],'duplicate case':cases+[cases[0]],'native bits':copy.deepcopy(cases),'input identity':copy.deepcopy(cases),'parameter identity':copy.deepcopy(cases)}
controls['native bits'][0]['slope']['bits']='0'
controls['input identity'][0]['y']['values'][0]='11.0';controls['input identity'][0]['y']['bits']='4026000000000000'
controls['parameter identity'][0]['offset']=19
for name,r in controls.items():
 try:a.verify(r)
 except (ValueError,KeyError,IndexError,TypeError):pass
 else:raise SystemExit('FAIL audit accepted corruption: '+name)
# Coherent coefficient changes are findings, not automatically passing/rejected
# producer claims. Demonstrate that a forged coefficient cannot look accurate.
r=copy.deepcopy(cases);r[0]['slope']={'value':'1.0','bits':'3ff0000000000000'}
out=a.verify(r);assert out[0]['classification']=='raw_moment_inaccurate'
print('PASS five provenance/completeness/native corruption rejections and one coefficient-change finding')
