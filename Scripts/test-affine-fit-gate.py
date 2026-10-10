#!/usr/bin/env python3
import copy,importlib.util,json,struct,sys
from pathlib import Path
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('gate',Path(__file__).with_name('verify-affine-fit-output.py'));gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
r=Path(sys.argv[1]);cases=json.loads((r/'shared.json').read_text());old=json.loads((r/'original-audit.json').read_text())
def coefficient(id,key,value):
 rows=copy.deepcopy(cases);c=next(c for c in rows if c['id']==id);c[key]={'value':str(value),'bits':format(int.from_bytes(struct.pack('>d',value),'big'),'x')};return rows
controls={'missing case':cases[:-1],'duplicate case':cases+[cases[0]],'slope with coherent bits':coefficient('audit/index/8/1000000000/line','slope',1),'anchor with coherent bits':coefficient('audit/index/8/1000000000/line','valueAtOrigin',2),'large-offset intercept':coefficient('audit/index/8/1000000000/line','intercept',3),'wrong error':copy.deepcopy(cases),'native bits':copy.deepcopy(cases),'query omission':copy.deepcopy(cases),'crossing omission':copy.deepcopy(cases),'input identity':copy.deepcopy(cases),'scale parameters':copy.deepcopy(cases),'prediction value':copy.deepcopy(cases),'crossing value':copy.deepcopy(cases)}
next(c for c in controls['wrong error'] if c['id']=='failure/rank')['error']='invalidDimensions'
controls['native bits'][0]['slope']['bits']='0'
controls['query omission'][0]['predictions'].pop()
controls['crossing omission'][0]['crossings'].pop()
controls['input identity'][0]['x']['values'][0]='4.0';controls['input identity'][0]['x']['bits'][0]='4010000000000000'
next(c for c in controls['scale parameters'] if c['id'].startswith('scale/'))['parameters']['ex']=7
controls['prediction value'][0]['predictions'][0]['value']={'value':'1.0','bits':'3ff0000000000000'}
controls['crossing value'][0]['crossings'][0]['coordinate']={'value':'9.0','bits':'4022000000000000'}
for name,rows in controls.items():
 try:gate.verify_records(rows,old)
 except (ValueError,KeyError,TypeError,IndexError):pass
 else:raise SystemExit('FAIL affine gate accepted corruption '+name)
print('PASS thirteen independent affine corruption controls, including coherent coefficient/input bits and complete queries')
