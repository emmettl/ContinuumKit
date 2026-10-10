#!/usr/bin/env python3
import copy, importlib.util, json, sys
from pathlib import Path
spec=importlib.util.spec_from_file_location('gate',Path(__file__).with_name('verify-real-fft-output.py'));gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
cases=json.loads((Path(sys.argv[1])/'shared.json').read_text())
def mutate(id,field,index,value):
    r=copy.deepcopy(cases);c=next(c for c in r if c['id']==id);c[field]['values'][index]=value
    import struct
    c[field]['bits'][index]=format(int.from_bytes(struct.pack('>d' if c['kind'] not in ['convolution','filter'] else '>f',value),'big'),'x')
    return r
controls={
 'missing case':cases[:-1],
 'duplicate case':cases+[cases[0]],
 'DC packing':mutate('forward/8/dc','real',0,0),
 'Nyquist packing':mutate('forward/8/nyquist','imag',0,0),
 'sine sign':mutate('forward/8/sin-1','imag',1,8),
 'inverse normalization':mutate('inverse/8/0','output',0,2),
 'frequency units':mutate('accumulate/8/48000/identity','frequencies',2,1),
 'sum weighting':mutate('accumulate/8/48000/tilt','real',1,9),
 'circular filter prefix':mutate('filter/3/5/center3tap','output',0,4),
 'convolution endpoint':mutate('convolution/3/7/impulse','output',2,0),
 'native bit identity':copy.deepcopy(cases),
 'padding identity':copy.deepcopy(cases),
}
controls['native bit identity'][0]['output']['bits'][0]='0'
next(c for c in controls['padding identity'] if c['kind']=='filter')['padding']=999
for name,r in controls.items():
    try:gate.verify_records(r)
    except (ValueError,KeyError,IndexError,TypeError):pass
    else:raise SystemExit(f'FAIL accepted corruption: {name}')
f=json.loads((Path(sys.argv[1])/'failures.json').read_text())
try:gate.verify_failures(f[:-1])
except ValueError:pass
else:raise SystemExit('FAIL missing checked failure')
print(f'PASS {len(controls)+1} independent corruption controls, applied even when both native variants would be changed')
