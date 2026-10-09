#!/usr/bin/env python3
"""Check the proposed source map from pinned Git objects without editing apps."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path


def require(condition, label):
    if not condition:
        raise ValueError(label)


def selected_block(source, selector):
    start = source.index(selector['anchor'])
    start_occurrence = selector.get('startOccurrence', 0)
    for occurrence in range(start_occurrence + 1):
        start = source.index(selector['startMarker'], start)
        if occurrence < start_occurrence:
            start += len(selector['startMarker'])
    end = start + len(selector['startMarker'])
    end_occurrence = selector.get('endOccurrence', 0)
    for occurrence in range(end_occurrence + 1):
        end = source.index(selector['endMarker'], end)
        if occurrence < end_occurrence:
            end += len(selector['endMarker'])
    return start, end


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--roomcad', type=Path, required=True)
    parser.add_argument('--edgerton', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=(
        Path(__file__).resolve().parents[1]
        / 'docs/extraction/linear-wave-source.json'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    manifest_bytes = args.manifest.read_bytes()
    manifest = json.loads(manifest_bytes)
    require(manifest['schemaVersion'] == 1, 'unsupported source-map schema')
    require(manifest['status'] == 'proposed-contract-not-an-extraction',
            'source map is not a proposed contract')
    roots = {'roomcad': args.roomcad, 'edgerton': args.edgerton}
    sources = {}
    for entry in manifest['files']:
        revision = manifest['repositories'][entry['repository']]['revision']
        raw = subprocess.check_output(
            ['git', 'show', revision + ':' + entry['path']],
            cwd=roots[entry['repository']])
        require(len(raw) == entry['bytes'], entry['path'] + ': byte count')
        require(hashlib.sha256(raw).hexdigest() == entry['sha256'],
                entry['path'] + ': source hash')
        sources[(entry['repository'], entry['path'])] = raw.decode('utf-8')
    for block in manifest['blocks']:
        source = sources[(block['repository'], block['path'])]
        start, end = selected_block(source, block['selector'])
        raw = source[start:end].encode('utf-8')
        require(len(raw) == block['bytes'], block['id'] + ': byte count')
        require(hashlib.sha256(raw).hexdigest() == block['sha256'],
                block['id'] + ': block hash')
        require(source[:start].count('\n') + 1 == block['startLine'],
                block['id'] + ': start line')
        require(source[:end].count('\n') == block['endLine'],
                block['id'] + ': end line')
    result = {
        'schemaVersion': 1,
        'status': 'passed',
        'scope': 'read-only source-map verification; no implementation or numerical rerun',
        'manifestSHA256': hashlib.sha256(manifest_bytes).hexdigest(),
        'files': len(manifest['files']),
        'blocks': len(manifest['blocks']),
        'repositories': manifest['repositories'],
    }
    if args.output:
        args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
    print('PASS', result['files'], 'pinned files and', result['blocks'],
          'bounded source blocks; app checkouts untouched')


if __name__ == '__main__':
    main()
