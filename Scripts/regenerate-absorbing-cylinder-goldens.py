#!/usr/bin/env python3
"""Offline 60-digit independent mpmath 1.3.0 reference; not a CI dependency."""
import json
from pathlib import Path
import mpmath as m
m.mp.dps=60
R=m.mpf('0.09375');H=m.mpf('0.125');rho=m.mpf('1.25');c=m.mpf(320);xi=m.mpf(3);k=m.pi/H
f=lambda z:z*m.besselj(1,z)+1j*m.sqrt(z*z+(k*R)**2)/xi*m.besselj(0,z)
z=m.findroot(f,(3.8-.3j,3.9-.5j));q=z/R;s=-1j*c*m.sqrt(q*q+k*k);T=2*m.pi/abs(s.imag)
def vector(r,theta,height,t):
 phase=m.exp(s*t);j0=m.besselj(0,q*r);j1=m.besselj(1,q*r)
 return [m.re(phase*j0)*m.cos(k*height),m.re(phase*q*j1/(rho*s))*m.cos(theta)*m.cos(k*height),m.re(phase*q*j1/(rho*s))*m.sin(theta)*m.cos(k*height),m.re(phase*k*j0/(rho*s))*m.sin(k*height)]
def energy(t):
 return m.pi*H/2*m.quad(lambda r:r*(m.re(m.exp(s*t)*m.besselj(0,q*r))**2/(rho*c*c)
  +rho*m.re(m.exp(s*t)*q*m.besselj(1,q*r)/(rho*s))**2
  +rho*m.re(m.exp(s*t)*k*m.besselj(0,q*r)/(rho*s))**2),[0,R])
# Independent temporal quadrature of physical boundary p²/(rho*c*xi).
def work(t):return m.pi*R*H/(rho*c*xi)*m.quad(lambda u:m.re(m.besselj(0,z)*m.exp(s*u))**2,[0,t])
result={'mpmathVersion':m.__version__,'decimalDigits':m.mp.dps,'root':[str(z.real),str(z.imag)],'rate':[str(s.real),str(s.imag)],'duration':str(T),'energy0':str(energy(0)),'energyHalf':str(energy(T/2)),'workHalf':str(work(T/2)),
 'statePoint':[str(m.mpf('.125')+R/4),str(m.mpf('.125')+R/4),str(H/4)],'stateTimeFraction':'0.137','state':list(map(str,vector(R*m.sqrt(2)/4,m.pi/4,H/4,T*m.mpf('.137'))))}
root=Path(__file__).resolve().parents[1]/'docs/benchmarks/reference';root.mkdir(parents=True,exist_ok=True)
(root/'absorbing-cylinder-goldens.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
