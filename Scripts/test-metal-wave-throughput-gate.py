#!/usr/bin/env python3
import argparse,importlib.util,json,shutil,tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('v',Path(__file__).with_name('verify-metal-wave-throughput.py'));v=importlib.util.module_from_spec(spec);spec.loader.exec_module(v)
def main(root):
 v.verify(root)
 edits=[('missing grid',lambda d:d['cases'].pop()),('missing repetition',lambda d:d['cases'][0]['runs'].pop()),('false completion clock',lambda d:d['cases'][0]['runs'][0].update(clock=1023)),('missing receiver frame',lambda d:d['cases'][0]['runs'][0]['frames'].pop()),('missing command',lambda d:d['cases'][0]['runs'][1]['commands'].pop()),('zero GPU timestamp',lambda d:d['cases'][0]['runs'][1]['commands'][0].update(gpuEndSeconds=0)),('changed mixed sample',lambda d:d['cases'][0]['runs'][1]['mixed'][0].__setitem__(0,1))]
 with tempfile.TemporaryDirectory(prefix='metal-profile-controls-') as t:
  for i,(label,edit) in enumerate(edits):
   p=Path(t)/str(i);shutil.copytree(root,p);r=p/'metal-throughput.json';d=json.loads(r.read_text());edit(d);r.write_text(json.dumps(d))
   try:v.verify(p)
   except (ValueError,KeyError,FileNotFoundError):pass
   else:raise AssertionError('accepted altered profile: '+label)
  for label,change in [('changed complete field',lambda p:(p/'fields-100-profile32-0.bin').write_bytes(b'bad')),('changed baseline shader',lambda p:(p/'baseline-source/WaveUpdate.metal').write_text('bad'))]:
   p=Path(t)/label;shutil.copytree(root,p);change(p)
   try:v.verify(p)
   except (ValueError,KeyError,FileNotFoundError):pass
   else:raise AssertionError('accepted altered profile: '+label)
 print('PASS ten profile controls, including nine negative cases')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('root',type=Path);main(p.parse_args().root)
