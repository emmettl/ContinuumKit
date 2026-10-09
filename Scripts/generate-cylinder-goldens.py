#!/usr/bin/env python3
"""Offline independent 60-digit cylinder checks; requires mpmath==1.3.0, never used by Swift CI."""
import json
import mpmath as m
m.mp.dps=60
root=m.besseljzero(1,1);radius=m.mpf(3)/32;kr=root/radius;kz=8*m.pi;norm=m.sqrt(kr*kr+kz*kz)
x=y=radius/4;z=m.mpf(1)/32;r=m.sqrt(x*x+y*y)
p=m.besselj(0,kr*r)*m.cos(kz*z)
u=kr*m.besselj(1,kr*r)*x/r*m.cos(kz*z)/(400*norm)
w=kz*m.besselj(0,kr*r)*m.sin(kz*z)/(400*norm)
energy=m.pi*radius*radius/8*m.besselj(0,root)**2/(4*m.mpf('1.25')*320**2)
print(json.dumps({'tool':'mpmath','version':m.__version__,'decimalPrecision':60,'root':m.nstr(root,60),'pressureAtZero':m.nstr(p,60),'quarterCycleU':m.nstr(u,60),'quarterCycleV':m.nstr(u,60),'quarterCycleW':m.nstr(w,60),'energy':m.nstr(energy,60),'position':[.125+float(x),.125+float(y),float(z)]},indent=2,sort_keys=True))
