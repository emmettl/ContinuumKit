#!/usr/bin/env python3
"""Independent convex-plane occupancy and directed boundary-crossing contract, in SI units.

No app geometry queries or wave updates are used. None means rigid (infinite xi).
Six sides are -x,+x,-y,+y,-z,+z, each a native cell-count array; -1 is interior/inactive.
"""
import argparse, json, math, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def standard_cases():
    return json.loads((ROOT/'Fixtures/ExtrudedLayout/cases.json').read_text())['cases']

def dot(a,b):
    return sum(x*y for x,y in zip(a,b))

def planes(c):
    points=c['corners']; result=[]
    for a,b in zip(points,points[1:]+points[:1]):
        # Counterclockwise polygon: right-hand edge normal points outwards.
        n=[b[1]-a[1],a[0]-b[0],0.0]
        length=math.sqrt(dot(n,n)); n=[x/length for x in n]
        result.append((n,dot(n,a+[0])))
    return result+[([0,0,-1],0),([0,0,1],c['lengths'][2])]

def f32(x):
    return struct.unpack('f',struct.pack('f',x))[0]

def reference(c,dt):
    assert math.isfinite(dt) and dt>0
    dims=c['dimensions']; nx,ny,nz=dims; size=c['lengths']
    spacing=[a/b for a,b in zip(size,dims)]
    bounds=planes(c); count=nx*ny*nz
    centres=[[((i%nx)+.5)*spacing[0],((i//nx)%ny+.5)*spacing[1],(i//(nx*ny)+.5)*spacing[2]] for i in range(count)]
    inside=[int(all(dot(n,p)<b for n,b in bounds)) for p in centres]
    ids=[-1]*(6*count); faces=[-1.]*(6*count)
    for cell,p in enumerate(centres):
        if not inside[cell]: continue
        ijk=[cell%nx,(cell//nx)%ny,cell//(nx*ny)]
        for side in range(6):
            axis=side//2; direction=-1 if side%2==0 else 1
            neighbour=list(ijk);neighbour[axis]+=direction
            valid=all(0<=i<n for i,n in zip(neighbour,dims))
            if valid and inside[neighbour[0]+nx*(neighbour[1]+ny*neighbour[2])]:continue
            delta=[0.,0.,0.];delta[axis]=direction*spacing[axis]
            exits=[]
            for face,(n,b) in enumerate(bounds):
                denom=dot(n,delta)
                if denom>0:
                    t=(b-dot(n,p))/denom
                    if 0<t<=1+1e-12:exits.append((t,face))
            if not exits:raise ValueError('Closed boundary has no segment exit')
            t,face=min(exits)
            index=side*count+cell;ids[index]=face
            xi=c['impedances'][face]
            if xi is None:faces[index]=0.
            else:
                weight=1/sum(abs(x) for x in bounds[face][0])
                # Match only the documented Float32 storage/operation order, not face selection.
                faces[index]=f32(f32(c['speed']*dt/(2*xi*spacing[axis]))*f32(weight))
    return dict(inside=inside,faces=faces,selectedFaces=ids,spacing=spacing,dt=dt)

def evaluate(c,h):
    dims=c['dimensions'];count=math.prod(dims)
    if (len(h.get('inside',[]))!=count or len(h.get('faces',[]))!=6*count
        or len(h.get('selectedFaces',[]))!=6*count
        or not all(isinstance(x,(int,float)) and math.isfinite(x) for x in h['faces'])
        or not all(type(x)==int and -1<=x<6 for x in h['selectedFaces'])
        or not isinstance(h.get('dt'),(int,float)) or not math.isfinite(h['dt']) or h['dt']<=0):
        raise ValueError('Incomplete or nonfinite layout')
    expected=reference(c,h['dt'])
    if h['inside']!=expected['inside'] or h['spacing']!=expected['spacing']:
        raise ValueError('Occupancy or spacing disagrees with independent planes')
    for value,want,face,identity in zip(h['faces'],expected['faces'],h['selectedFaces'],expected['selectedFaces']):
        if (value<0)!=(want<0) or (face<0)!=(identity<0) or (value<0 and value!=-1):
            raise ValueError('Interior/inactive face topology disagrees with occupancy')
    coefficients=[];identities=[];missing=[];caps=[];patch=[]
    count=math.prod(dims)
    for index,(value,want,face,identity) in enumerate(zip(h['faces'],expected['faces'],h['selectedFaces'],expected['selectedFaces'])):
        if want<0:continue
        if face!=identity:identities.append(index)
        scale=max(abs(want),c['speed']*h['dt']/(6*expected['spacing'][index//count//2]))
        if abs(value-want)>2e-6*scale:
            coefficients.append(index)
            if want>0 and value==0:missing.append(index)
            if identity<4 and face>=4:caps.append(index)
            y=((index%count//dims[0])%dims[1]+.5)*expected['spacing'][1]
            if identity==1 and .10<y<.27:patch.append(index)
    wanted=sum(max(0,x) for x in expected['faces']);got=sum(max(0,x) for x in h['faces'])
    return dict(status='passed' if not coefficients and not identities else 'conformance-gap',
        topologyStatus='passed',coefficientMismatchCount=len(coefficients),selectedFaceMismatchCount=len(identities),
        missingAdmittanceFaceCount=len(missing),capSubstitutionCoefficientCount=len(caps),
        centralEastWallMismatchCount=len(patch),closedFaceCount=sum(x>=0 for x in expected['faces']),
        admittanceSumRatio=got/wanted if wanted else 1,
        coefficientMismatchIndices=coefficients,selectedFaceMismatchIndices=identities)

def verify(root):
    cases=standard_cases();records=list(root.glob('*.layout.json'));by={c['id']:c for c in cases}
    seen=set();summary=[]
    for path in sorted(records):
        record=json.loads(path.read_text());c=record['specification'];rep=record['representation'];key=(c['id'],rep)
        if c!=by.get(c['id']) or rep not in ['reference','plan','mesh'] or key in seen:
            raise ValueError('Unexpected or duplicate case')
        seen.add(key);metrics=evaluate(c,record['layout'])
        if record.get('metrics')!=metrics:raise ValueError('Recorded metrics disagree with independent recomputation')
        summary.append(dict(case=c['id'],representation=rep,**{k:v for k,v in metrics.items() if not k.endswith('Indices')}))
    reps={r for _,r in seen}
    if reps not in [{'reference'},{'plan','mesh'}] or seen!={(c['id'],r) for c in cases for r in reps}:
        raise ValueError('Incomplete case/representation matrix')
    # Equivalent inputs must retain identical occupancy and clock; coefficients are the audited gap.
    if reps=={'plan','mesh'}:
        for c in cases:
            a=json.loads((root/(c['id']+'-plan.layout.json')).read_text())['layout']
            b=json.loads((root/(c['id']+'-mesh.layout.json')).read_text())['layout']
            if any(a[k]!=b[k] for k in ['inside','dt','spacing']):raise ValueError('Plan/mesh geometry or clock mismatch')
    (root/'comparison.json').write_text(json.dumps(dict(schemaVersion=1,scope='geometry-layout-only',results=summary),indent=2)+'\n')
    print('PASS complete independent topology audit:',len(summary),'layouts;',sum(x['status']=='conformance-gap' for x in summary),'explicit assignment gaps')
    return summary

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['reference','verify']);p.add_argument('output',type=Path);a=p.parse_args()
    if a.mode=='reference':
        a.output.mkdir(parents=True,exist_ok=True)
        for c in standard_cases():
            h=reference(c,1/768000)
            record=dict(schemaVersion=1,specification=c,representation='reference',layout=h,metrics=evaluate(c,h))
            (a.output/(c['id']+'-reference.layout.json')).write_text(json.dumps(record,separators=(',',':'))+'\n')
    verify(a.output)
