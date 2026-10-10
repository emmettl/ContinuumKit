#!/usr/bin/env python3
"""Check legacy and standalone repository selection without modifying source inputs."""
import json, subprocess, tempfile, unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name('inventory.py')

class InventorySelectionTests(unittest.TestCase):
    def test_standalone_four_repository_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); desc = root/'descriptions'; desc.mkdir()
            for name in ['continuumkit','roomcad','bombcad','edgerton']:
                repo=root/name; (repo/'Sources').mkdir(parents=True)
                (repo/'Sources/Marker.swift').write_text('import Foundation\n// '+name+'\n')
                (desc/(name+'-package.json')).write_text(json.dumps({'name':name,'targets':[],'products':[]}))
            output=root/'result.json'
            subprocess.run(['python3',str(SCRIPT),'--bombcad',str(root/'bombcad'),'--edgerton',str(root/'edgerton'),
                            '--roomcad',str(root/'roomcad'),'--core',str(root/'continuumkit'),
                            '--descriptions',str(desc),'--output',str(output)],check=True,capture_output=True)
            data=json.loads(output.read_text()); self.assertEqual([p['name'] for p in data['packages']],['continuumkit','roomcad','bombcad','edgerton'])
            for package in data['packages']:
                self.assertEqual(package['file_count'],1)
                self.assertEqual((root/package['name']/'Sources/Marker.swift').read_text(),'import Foundation\n// '+package['name']+'\n')
    def test_incomplete_standalone_arguments_reject(self):
        p=subprocess.run(['python3',str(SCRIPT),'--bombcad','b','--edgerton','e','--roomcad','r','--descriptions','d','--output','o'],capture_output=True,text=True)
        self.assertNotEqual(p.returncode,0); self.assertIn('both --roomcad and --core',p.stderr)

if __name__=='__main__': unittest.main()
