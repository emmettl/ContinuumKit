"""Independent high-precision displacement envelope and compliance solution."""
import csv,json,sys
from decimal import Decimal as D,getcontext
from pathlib import Path
getcontext().prec=45
FIELDS=['mode','orientation','cells','increments','sign','step','band_strain','stress','damage','history','displacement_m','reaction_N','stored_J','loss_J','work_J']
def generate(data,out):
    L=D(str(data['length_m'])); A=D(str(data['width_m']))*D(str(data['thickness_m']))
    rows=[]
    for mode in ['tension','shear']:
        for angle in data['grain_orientations_deg']:
            p=next(m for m in data['tension'] if m['grain_deg']==angle) if mode=='tension' else data['shear']
            K,S,G=map(lambda k:D(str(p[k])),['K_Pa','strength_Pa','Gf_J_m2'])
            for cells in data['mesh_cells']:
                h=L/D(cells); w0=h*S/K; wf=2*G/S
                def traction(w):
                    if w<=w0:return K*w/h
                    if w>=wf:return D(0)
                    return S*(wf-w)/(wf-w0)
                def envelope_area(w):
                    x=min(w,wf)
                    return S*w0/2+(S+traction(x))*(x-w0)/2 if x>w0 else K*x*x/(2*h)
                for n in data['increments_per_leg']:
                    for sign in ([1] if mode=='tension' else [1,-1]):
                        a=w0+(wf-w0)*D('.2'); b=w0+(wf-w0)*D('.65')
                        path=[D(0),w0/2,w0,a,D(0),(-a/2 if mode=='shear' else a/2),b,D(0),(-b if mode=='shear' else b),wf,wf*D('1.1'),D(0)]
                        points=[D(0)]+[D(sign)*(u+(v-u)*D(j)/D(n)) for u,v in zip(path,path[1:]) for j in range(1,n+1)]
                        maximum=D(0)
                        for step,w in enumerate(points):
                            maximum=max(maximum,abs(w))
                            stiffness=K/h if maximum<=w0 else traction(maximum)/maximum
                            stress=stiffness*w
                            damage=1-stiffness*h/K
                            bandStored=stiffness*w*w/2
                            loss=envelope_area(maximum)-traction(maximum)*maximum/2
                            bulkStored=(L-h)*stress*stress/(2*K)
                            displacement=w+(L-h)*stress/K
                            stored=A*(bandStored+bulkStored)
                            rows.append([mode,angle,cells,n,sign,step,*map(float,[w/h,stress,damage,maximum/h,displacement,A*stress,stored,A*loss,stored+A*loss])])
    with Path(out).open('w',newline='') as f:
        writer=csv.writer(f,lineterminator='\n');writer.writerow(FIELDS);writer.writerows(rows)
    print(len(rows))
if __name__=='__main__':generate(json.loads(Path(sys.argv[1]).read_text()),sys.argv[2])
