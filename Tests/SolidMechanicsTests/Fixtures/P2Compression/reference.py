"""Independent envelope solution: running maximum compression, not return mapping."""
import csv, json
from decimal import Decimal as D, getcontext
from pathlib import Path
getcontext().prec = 45

FIELDS = ['axis','hardening_control','increments','step','strain','stress','alpha','elastic','hardening','dissipation','work','displacement_m','reaction_N','work_J']

def generate(inputs, output):
    rows = []
    L = D(str(inputs['gauge_length_m']))
    A = D(str(inputs['width_m'])) * D(str(inputs['thickness_m']))
    for material in inputs['materials']:
        for control in ['linear', 'perfect-plastic']:
            E, Y = D(str(material['E_Pa'])), D(str(material['Y_Pa']))
            H = D(str(material['H_Pa'])) if control == 'linear' else D(0)
            peak, deep = D(str(material['peak_strain'])), D(str(material['deep_strain']))
            residual = (E * peak + Y) / (E + H)
            final = (E * deep + Y) / (E + H)
            path = [D(0), -Y/(2*E), -Y/E, peak, residual,
                    (peak+residual)/2, residual, deep, final]
            for n in inputs['increments_per_leg']:
                maximum, old, work = D(0), D(0), D(0)
                points = [D(0)] + [a+(b-a)*D(k)/D(n) for a,b in zip(path,path[1:]) for k in range(1,n+1)]
                for step, strain in enumerate(points):
                    alpha_old = max(D(0), (E*maximum-Y)/(E+H))
                    onset = -(Y+(E+H)*alpha_old)/E
                    # Analytic antiderivatives of the elastic line and plastic envelope.
                    def elastic_primitive(x): return E*x*x/2 + E*alpha_old*x
                    def envelope_primitive(x): return E*H*x*x/(2*(E+H))-E*Y*x/(E+H)
                    if strain < onset:
                        work += elastic_primitive(onset)-elastic_primitive(old)
                        work += envelope_primitive(strain)-envelope_primitive(onset)
                    else:
                        work += elastic_primitive(strain)-elastic_primitive(old)
                    maximum = max(maximum,-strain)
                    alpha = max(D(0),(E*maximum-Y)/(E+H))
                    stress = E*(strain+alpha)
                    elastic, stored, loss = stress*stress/(2*E), H*alpha*alpha/2, Y*alpha
                    assert abs(work-elastic-stored-loss) < D('1e-30')
                    rows.append([material['axis'],control,n,step,*map(float,[strain,stress,alpha,elastic,stored,loss,work,L*strain,A*stress,A*L*work])])
                    old = strain
    with Path(output).open('w',newline='') as f:
        writer=csv.writer(f,lineterminator='\n'); writer.writerow(FIELDS); writer.writerows(rows)
    return len(rows)

if __name__ == '__main__':
    import sys
    print(generate(json.loads(Path(sys.argv[1]).read_text()),sys.argv[2]))
