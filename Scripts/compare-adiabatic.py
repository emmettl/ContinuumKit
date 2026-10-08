#!/usr/bin/env python3
"""Compare already-conformant model reports under identical case definitions; retain independent errors."""
import argparse
import csv
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('reports', nargs='+', type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
expected_cases = None
rows = []
for report in args.reports:
    cases = json.loads((report / 'cases.json').read_text())
    if expected_cases is None: expected_cases = cases
    if cases != expected_cases:
        raise SystemExit(f'Case definitions differ: {report}')
    status = json.loads((report / 'conformance.json').read_text())
    if len(status) != len(cases) or any(s['status'] != 'passed' for s in status):
        raise SystemExit(f'Missing, unsupported or failed conformance: {report}')
    results = json.loads((report / 'results.json').read_text())
    for case in cases:
        series = [r for r in results if r['caseSpecification'] == case]
        if len(series) != 4 or any(r['status'] != 'supported' for r in series):
            raise SystemExit(f'Incomplete result series: {report}/{case["id"]}')
        finest = max(series, key=lambda r: r['steps'])
        summary = next(s for s in status if s['caseID'] == case['id'])
        rows.append({'case': case['id'], 'model': finest['model'], 'steps': finest['steps'],
                     'revision': finest['environment']['revision'], 'hardware': finest['environment']['hardware'],
                     'working_tree_dirty': finest['environment']['workingTreeDirty'],
                     'runtime_s': finest['runtimeS'], 'refinement_metric': summary['refinementMetric'],
                     'observed_orders': summary['observedOrders'], **finest['errors']})
(args.output / 'comparison.json').write_text(json.dumps({'schemaVersion': 1, 'cases': expected_cases,
    'note': 'Errors use independent analytic references; cross-model agreement is not the accuracy oracle.',
    'results': rows}, indent=2) + '\n')
with (args.output / 'comparison.csv').open('w', newline='') as stream:
    writer = csv.DictWriter(stream, fieldnames=rows[0].keys())
    writer.writeheader()
    writer.writerows(rows)
for row in rows:
    print(row['case'], row['model'], 'p error', row['maximumRelativePressure'],
          'work error', row['maximumWorkNormalized'], 'orders', row['observed_orders'])
