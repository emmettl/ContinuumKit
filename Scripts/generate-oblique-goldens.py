#!/usr/bin/env python3
"""Independent 60-decimal boundary-determinant roots; requires mpmath==1.3.0 (not a Swift/CI dependency)."""
import argparse,json
import mpmath as mp
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
mp.mp.dps=60;rows=[]
for xi in [3,.5]:
 b=2*mp.pi;guess=2*mp.pi-.5j if xi==3 else 2.5*mp.pi-.4j
 z=mp.findroot(lambda z:z*mp.tan(z)+1j*mp.sqrt(z*z+b*b)/xi,guess)
 k=z/mp.mpf('.25');q=mp.sqrt(k*k+(mp.pi/mp.mpf('.125'))**2);rate=-1j*320*q
 reflection=(xi*k/q-1)/(xi*k/q+1)
 rows.append({'impedance':xi,'dimensionlessRoot':[str(mp.re(z)),str(mp.im(z))],
  'rate':[str(mp.re(rate)),str(mp.im(rate))],'reflection':[str(mp.re(reflection)),str(mp.im(reflection))]})
a.output.write_text(json.dumps({'method':'mpmath 1.3.0 findroot, 60 decimal digits, independently solved boundary determinant','cases':rows},indent=2)+'\n')
