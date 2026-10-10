#!/usr/bin/env python3
"""Reject incomplete or corrupted execution evidence without changing baseline files."""
import argparse, importlib.util, json, os, shutil, struct, tempfile
from pathlib import Path
spec=importlib.util.spec_from_file_location('verifier',Path(__file__).with_name('verify-cpu-wave-throughput.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def edit(root,name,callback):
    path=root/name;data=json.loads(path.read_text());callback(data)
    path.unlink();path.write_text(json.dumps(data))
def corrupt(data):
    value=struct.unpack('>f',struct.pack('>f',data['values'][0][0]+0.001))[0]
    data['values'][0][0]=value;data['bits'][0][0]=int.from_bytes(struct.pack('>f',value),'big')
def main(root):
    module.verify(root)
    with tempfile.TemporaryDirectory(prefix='cpu-throughput-controls-') as temp:
        for index in range(7):
            copy=Path(temp)/str(index);shutil.copytree(root,copy,copy_function=os.link)
            if index==0:edit(copy,'timings.json',lambda d:d[0]['timings'].pop())
            elif index==1:(copy/'24x18x9/serial-0.json').unlink()
            elif index==2:edit(copy,'24x18x9/serial-0.json',lambda d:d.update(pressureTime=d['pressureTime']+1))
            elif index==3:edit(copy,'24x18x9/serial-0.json',corrupt)
            elif index==4:edit(copy,'24x18x9/serial-0.json',lambda d:d['velocity'].pop())
            elif index==5:edit(copy,'consumer-Package.resolved',lambda d:d['pins'][0]['state'].update(revision='0'*40))
            else:
                path=copy/'Alpha8CPUWaveStepper.swift';body=path.read_text();path.unlink();path.write_text(body+'\n// changed baseline body\n')
            try:module.verify(copy)
            except (ValueError,KeyError,FileNotFoundError):pass
            else:raise AssertionError('Incomplete/corrupt execution evidence accepted: '+str(index))
    print('PASS eight execution report controls, including seven negative cases')
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('root',type=Path);main(p.parse_args().root)
