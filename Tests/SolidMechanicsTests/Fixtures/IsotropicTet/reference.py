"""Independent Decimal diagonal-deformation energy and Cauchy stress references."""
from decimal import Decimal as D,getcontext
from pathlib import Path
import csv,sys
getcontext().prec=45
G,K,A=D(5000),D(20000),D(1000)
rows=[]
for law in ['isochoricNeoHookeanLogBulk','saintVenantKirchhoff','saintVenantKirchhoffLogBarrier']:
    for values in [('1','1','1'),('1.05','.97','1.01'),('.8','.9','1.1'),('1.2','1.2','1.2')]:
        s=list(map(D,values));j=s[0]*s[1]*s[2]
        if law=='isochoricNeoHookeanLogBulk':
            tr=sum(x*x for x in s);iso=j**(-D(2)/3)
            energy=G/2*(iso*tr-3)+K/2*j.ln()**2
            stress=[(G*iso*(x*x-tr/3)+K*j.ln())/j for x in s]
        else:
            barrier=A if law.endswith('LogBarrier') else D(0)
            c=[x*x-1 for x in s];tr=sum(c);lam=K-2*G/3-barrier
            energy=G/4*sum(x*x for x in c)+lam/8*tr*tr+barrier*(j-1-j.ln())
            stress=[(x*x*(G*ci+lam*tr/2)+barrier*(j-1))/j for x,ci in zip(s,c)]
        rows.append([law,*map(float,s),float(j),float(energy),*map(float,stress)])
with Path(sys.argv[1]).open('w',newline='') as f:
    w=csv.writer(f,lineterminator='\n');w.writerow(['law','x','y','z','J','energy_density','stress_x','stress_y','stress_z']);w.writerows(rows)
