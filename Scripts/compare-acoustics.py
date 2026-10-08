#!/usr/bin/env python3
"""Compare independently scored, complete acoustic backend reports with identical cases."""
import argparse,csv,json,subprocess
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',required=True,type=Path)
parser.add_argument('reports',nargs='+',type=Path)
a=parser.parse_args(); rows=[]; cases=None; models=set()
for report in a.reports:
 subprocess.run(['python3',str(Path(__file__).with_name('verify-acoustic-output.py')),str(report)],check=True)
 current=json.loads((report/'cases.json').read_text())
 if cases is None: cases=current
 assert cases==current,'Different physical cases cannot be compared'
 results=json.loads((report/'results.json').read_text())
 model=results[0]['model'];assert model not in models,'Duplicate backend';models.add(model)
 for r in results:
  assert r['model']==model and r['status']=='supported'
  row={'model':model,'case':r['caseSpecification']['id'],'axis':r['resolution']['axis'],
       'cells':r['resolution']['cells'],'steps':r['resolution']['steps'],
       'spacing_m':r['history']['spacingM'],'time_step_s':r['history']['timeStepS'],
       'reference':r['reference'],'precision':r['environment']['precision'],'revision':r['environment']['revision'],
       'runtime_s':r['runtimeS'],**r['errors']}
  rows.append(row)
a.output.mkdir(parents=True,exist_ok=True)
(a.output/'comparison.json').write_text(json.dumps({'schemaVersion':1,'cases':cases,'results':rows},indent=2)+'\n')
with (a.output/'comparison.csv').open('w',newline='') as f:
 w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
print(f'PASS matched acoustic comparison: {len(models)} real backends, {len(rows)} independently scored runs')
