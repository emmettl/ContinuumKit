#!/usr/bin/env python3
"""Capture original Edgerton projection arithmetic and exact-native rational diagnostics."""
import argparse
import builtins
import copy
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import platform
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / 'Fixtures/ThroughOriginAudit'


def require(ok, label):
    if not ok:
        raise ValueError(label)


def encoded(value):
    if isinstance(value, float):
        return {'binary64': value.hex()}
    if isinstance(value, dict):
        return {k: encoded(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [encoded(v) for v in value]
    return value


def ratio(value):
    return {'numerator': str(value.numerator), 'denominator': str(value.denominator)}


def cases():
    result = []
    def add(name, xs, ys):
        require(len(xs) == len(ys) and all(math.isfinite(v) for v in xs + ys), 'finite native case')
        for kind in ['shear', 'bulk']:
            result.append({'id': kind + '/' + name, 'kind': kind,
                           'x': [v.hex() for v in xs], 'y': [v.hex() for v in ys]})
    add('ordinary-modulus', [.001, .002, .003], [1000., 2000., 3000.])
    add('ordinary-noisy', [.001, .002, .003, .004], [1020., 1990., 3010., 3980.])
    add('signed-strain', [-.001, 0., .003], [-1000., 0., 3000.])
    add('zero-strain', [0., 0., 0.], [1., 2., 3.])
    add('zero-response', [1., 2., 3.], [0., 0., 0.])
    add('negative-modulus', [1., 2., 3.], [-2., -4., -6.])
    add('too-few', [1., 2.], [2., 4.])
    add('cancellation-positive', [1., 1., 1.], [2.**53, 1., -(2.**53)])
    add('cancellation-reordered', [1., 1., 1.], [2.**53, -(2.**53), 1.])
    add('raw-sums-overflow', [1e200]*3, [3e200]*3)
    add('raw-sums-underflow', [1e-200]*3, [3e-200]*3)
    add('dot-overflow-only', [1e100]*3, [1e250]*3)
    add('unrepresentable-modulus', [1e-300]*3, [1e300]*3)
    add('unrepresentable-rmse', [1.]*3, [1e200, 2e200, 3e200])
    add('tiny-modulus', [1e200]*3, [1e-200]*3)
    for exponent in [-1000, -800, -600, -540, -538, -537, -536, -535, -500, -400, -200, 0, 200, 400, 500, 509, 510, 511, 512, 513, 600, 800, 1000]:
        x = math.ldexp(1., exponent)
        add('scale-' + str(exponent), [x, 2*x, 3*x], [2*x, 4*x, 6*x])
    for exponent in [-600, -400, -200, 0, 200, 400, 600]:
        x = math.ldexp(1., exponent)
        add('strain-scale-' + str(exponent), [x, 2*x, 3*x], [2., 4., 6.])
    return result


def source():
    metadata = json.loads((FIXTURE/'source.json').read_text())
    raw = (FIXTURE/metadata['snapshot']).read_bytes()
    require(hashlib.sha256(raw).hexdigest() == metadata['sha256'], 'original source SHA-256')
    require(hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest() == metadata['gitBlob'], 'original source Git blob')
    require(metadata['gitBlob'] == '9d963dc0b30bb6672da1055d375a887da0d2e8a0', 'protected original calibration blob')
    return metadata, raw


def native(raw, case, observe=True):
    observations = []
    def observed_sum(values):
        # Freeze every term in its original order and delegate to the same builtin.
        terms = list(values)
        value = builtins.sum(terms)
        observations.append({'terms': encoded(terms), 'result': encoded(value)})
        return value
    namespace = {'__name__': 'protected_original_calibration'}
    if observe:
        namespace['sum'] = observed_sum
    exec(compile(raw, 'OriginalCalibration.py.txt', 'exec'), namespace)
    rows = [{'test': case['kind'], 'strain': float.fromhex(x), 'stress_pa': float.fromhex(y)}
            for x, y in zip(case['x'], case['y'])]
    try:
        output = namespace['fit'](rows)
        outcome = {'status': 'returned', 'output': encoded(output)}
    except (ValueError, OverflowError, ZeroDivisionError) as error:
        outcome = {'status': 'rejected', 'type': type(error).__name__, 'message': str(error)}
    return {'outcome': outcome, 'sums': observations}


def reference(case, actual):
    xs = [Fraction(float.fromhex(v)) for v in case['x']]
    ys = [Fraction(float.fromhex(v)) for v in case['y']]
    den = sum(x*x for x in xs)
    dot = sum(x*y for x, y in zip(xs, ys))
    result = {'denominator': ratio(den), 'dot': ratio(dot)}
    if len(xs) < 3 or not den:
        result.update(status='policy-rejected', finding='expected-source-rejection')
        require(actual['outcome']['status'] == 'rejected', 'source count/zero-strain rejection')
        return result
    modulus = dot / den
    result['modulus'] = ratio(modulus)
    if modulus <= 0:
        result.update(status='policy-rejected', finding='expected-source-rejection')
        require(actual['outcome']['status'] == 'rejected', 'source positive-modulus rejection')
        return result
    residuals = [y - modulus*x for x, y in zip(xs, ys)]
    result['residuals'] = [ratio(v) for v in residuals]
    result['meanSquaredResidual'] = ratio(sum(v*v for v in residuals)/len(xs))
    require(sum(x*r for x, r in zip(xs, residuals)) == 0, 'exact projection orthogonality')
    try:
        expected = float(modulus)
    except OverflowError:
        result.update(status='unrepresentable-coefficient', finding='unsupported-binary64-coefficient')
        return result
    if not expected or not math.isfinite(expected):
        result.update(status='unrepresentable-coefficient', finding='unsupported-binary64-coefficient')
        return result
    result.update(status='representable-positive-projection', roundedModulus=encoded(expected))
    if actual['outcome']['status'] == 'rejected':
        result['finding'] = 'rejected-representable-positive-projection'
        return result
    fit = actual['outcome']['output']['fits'][case['kind']]
    value = float.fromhex(fit['modulus_pa']['binary64'])
    rmse = float.fromhex(fit['rmse_pa']['binary64'])
    if not math.isfinite(value):
        result['finding'] = 'returned-nonfinite-coefficient'
    elif value == expected:
        result['finding'] = 'correctly-rounded-coefficient'
    else:
        result['finding'] = 'finite-coefficient-difference'
        result['exactCoefficientError'] = ratio(Fraction(value) - modulus)
    result['nativeRMSEFinite'] = math.isfinite(rmse)
    # RMSE representation is a separate observable; this audit makes no error-bound claim.
    return result


def capture():
    metadata, raw = source()
    records = []
    for case in cases():
        actual = native(raw, case)
        require(actual['outcome'] == native(raw, case, observe=False)['outcome'], 'observation binding preserves actual source result')
        records.append({'case': case, 'native': actual, 'reference': reference(case, actual)})
    counts = {}
    for record in records:
        finding = record['reference']['finding']
        counts[finding] = counts.get(finding, 0) + 1
    return {'schemaVersion': 1, 'source': metadata, 'cases': records, 'findings': counts,
            'scope': 'protected original source arithmetic audit; no shared primitive or material accuracy claim'}


def validate(report):
    expected = capture()
    require(report == expected, 'complete native/reference/source/case identity')


def controls(report):
    labels = []
    for label in ['source', 'native', 'input', 'exact-reference', 'missing-case']:
        bad = copy.deepcopy(report)
        if label == 'source': bad['source']['gitBlob'] = '0'*40
        elif label == 'native': bad['cases'][0]['native']['outcome']['output']['fits']['shear']['modulus_pa']['binary64'] = '0x1.0p+0'
        elif label == 'input':
            case = bad['cases'][0]['case']
            case['y'][0] = '0x1.0p+0'
            _, raw = source()
            actual = native(raw, case)
            bad['cases'][0]['native'] = actual
            bad['cases'][0]['reference'] = reference(case, actual)
        elif label == 'exact-reference': bad['cases'][0]['reference']['modulus']['numerator'] = '1'
        else: bad['cases'].pop()
        try:
            validate(bad)
        except ValueError:
            labels.append(label)
        else:
            raise ValueError('corruption escaped: ' + label)
    return labels


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    path = args.output / 'original.json'
    if args.verify:
        report = json.loads(path.read_text())
    else:
        report = capture()
        path.write_text(json.dumps(report, indent=2, sort_keys=True, allow_nan=False)+'\n')
        (args.output/'environment.json').write_text(json.dumps({'python': sys.version, 'platform': platform.platform(), 'machine': platform.machine(), 'sumImplementation': 'actual runtime builtins.sum; generator terms frozen in original order'}, indent=2)+'\n')
    validate(report)
    rejected = controls(report)
    (args.output/'controls.json').write_text(json.dumps({'rejectedControls': rejected}, indent=2)+'\n')
    print(json.dumps({'cases': len(report['cases']), 'findings': report['findings'], 'rejectedControls': rejected}, sort_keys=True))

if __name__ == '__main__':
    main()
