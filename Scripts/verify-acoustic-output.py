#!/usr/bin/env python3
"""Reject incomplete acoustic reports or CSV/JSON field/clock inconsistencies."""
import argparse
import csv
import json
import math
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('--reference', action='store_true')
args = parser.parse_args()
root = args.output
cases = json.loads((root/'cases.json').read_text())
results = json.loads((root/'results.json').read_text())
conformance = json.loads((root/'conformance.json').read_text())
status = 'reference' if args.reference else 'supported'
assert len(cases) > 0 and len(results) == 6*len(cases) and len(conformance) == 2*len(cases)
for case_index, case in enumerate(cases):
    assert case['version'] == 1
    series = results[case_index*6:(case_index+1)*6]
    fine_steps = math.ceil(case['soundSpeedMps']*case['durationS']*384/(0.3*case['lengthM']))
    resolutions = [('space', n, fine_steps) for n in (96,192,384)] + [
        ('time',192,math.ceil(case['soundSpeedMps']*case['durationS']*192/(cfl*case['lengthM'])))
        for cfl in (0.6,0.3,0.15)]
    for run_index, (result, expected) in enumerate(zip(series,resolutions)):
        assert result['schemaVersion'] == 1 and result['status'] == status and result['caseSpecification'] == case
        r,h = result['resolution'],result['history']
        assert (r['axis'],r['cells'],r['steps']) == expected
        captures = {math.floor(n*r['steps']/24+0.5) for n in range(25)}
        if case['kind'] == 'rigidWall':
            captures.add(math.floor((case['lengthM']-case['centreM'])/case['soundSpeedMps']/case['durationS']*r['steps']+0.5))
        assert [f['step'] for f in h['frames']] == sorted(captures)
        with (root/f'case-{case_index}-run-{run_index}.csv').open() as f:
            rows = list(csv.DictReader(f))
        assert len(rows) == len(captures)*(2*r['cells']+1)
        row_index = 0
        for frame in h['frames']:
            assert len(frame['pressurePa']) == r['cells'] and len(frame['normalVelocityMps']) == r['cells']+1
            time = frame['step']*h['timeStepS']
            for kind,values,offset,unit in [('pressure',frame['pressurePa'],0.5,'Pa'),('normal_velocity',frame['normalVelocityMps'],0,'m/s')]:
                for index,value in enumerate(values):
                    row=rows[row_index]; row_index+=1
                    assert int(row['step']) == frame['step'] and row['grid_kind'] == kind and int(row['index']) == index
                    assert row['unit'] == unit and math.isfinite(value)
                    assert float(row['value']) == value and float(row['x_m']) == (index+offset)*h['spacingM']
                    assert float(row['pressure_time_s']) == time and float(row['velocity_time_s']) == time-h['timeStepS']/2
    for axis in ('space','time'):
        selected = [c for c in conformance if c['caseID'] == case['id'] and c['axis'] == axis]
        assert len(selected) == 1 and selected[0]['status'] == ('reference' if args.reference else 'passed')
        orders=selected[0]['observedOrders']
        assert orders == [] if args.reference else len(orders)==2 and all(1.7<=p<=2.3 for p in orders)
print(f'PASS complete acoustic reports: {len(cases)} cases, {len(results)} runs, matching staggered JSON/CSV fields')
