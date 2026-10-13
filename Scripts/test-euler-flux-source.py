#!/usr/bin/env python3
"""Check the exact portability whitelist without modifying source or frozen fixtures."""
import runpy
from pathlib import Path

root = Path(__file__).resolve().parent.parent
gate = runpy.run_path(str(root / 'Scripts/verify-euler-flux-source.py'))
normalize = gate['normalized']
source = (root / 'Sources/CompressibleFlow/FractionalEulerFlux.swift').read_text()
expected = normalize(gate['original'].decode())
preamble = 'import Foundation\n\n#if canImport(simd)\n  import simd\n#endif\n'
assert source.startswith(preamble)
assert normalize(source) == expected
assert normalize('import simd\n' + source[len(preamble):]) == expected

trials = {
    'numeric expression': ('cell.amount / cell.volume', 'cell.amount * cell.volume'),
    'constant': ('private static let gamma = 1.4', 'private static let gamma = 1.5'),
    'body conditional': ('if wall.area == 0', 'if wall.area != 0'),
    'return body': ('}.max()!', '}.min()!'),
    'import condition': ('#if canImport(simd)', '#if !canImport(simd)'),
    'extra import': ('import Foundation', 'import Foundation\nimport Dispatch'),
    'code inside import guard': ('  import simd\n#endif', '  import simd\nlet injected = 1\n#endif'),
    'additional body preprocessor': ('    let state = cell.amount / cell.volume', '    #if canImport(simd)\n    let state = cell.amount / cell.volume\n    #endif'),
}
for label, (before, after) in trials.items():
    assert source.count(before) == 1, label
    assert normalize(source.replace(before, after)) != expected, label
# The exact block is accepted only at the start, never stripped from a body.
assert normalize(source + '\n' + preamble) != expected
assert normalize('// moved preamble\n' + source) != expected
print(f'PASS original/portable preambles; {len(trials) + 2} source corruption controls rejected')
