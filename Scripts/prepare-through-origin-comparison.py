#!/usr/bin/env python3
"""Use the complete protected audit case tree as exact binary64 QR inputs."""
import importlib.util,json,struct,sys
from pathlib import Path
sys.dont_write_bytecode=True
r=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('audit',r/'through-origin-audit.py');audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
def bits(v):return str(struct.unpack('>Q',struct.pack('>d',float.fromhex(v)))[0])
inputs=[{'id':c['id'],'xBits':[bits(v) for v in c['x']],'yBits':[bits(v) for v in c['y']]} for c in audit.cases()]
Path(sys.argv[1]).write_text(json.dumps(inputs,indent=2)+'\n')
