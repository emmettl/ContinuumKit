#!/usr/bin/env python3
import copy,math,unittest
import extruded_layout as m
class Planes(unittest.TestCase):
    def setUp(self):
        self.c=dict(id='unit',corners=[[0,0],[1,0],[1,1],[0,1]],lengths=[1,1,1],dimensions=[2,2,2],impedances=[None,3,None,None,None,None],speed=320)
    def test_hand_count_and_material(self):
        h=m.reference(self.c,1/768000)
        self.assertEqual(sum(h['inside']),8)
        self.assertEqual(sum(x>=0 for x in h['faces']),24)
        self.assertEqual(sum(x>0 for x in h['faces']),4)
        self.assertEqual(h['faces'][8+1],m.f32(320/768000/3))
        self.assertEqual(m.evaluate(self.c,h)['status'],'passed')
    def test_tilted_exit(self):
        c=copy.deepcopy(self.c);c['corners']=[[0,0],[.9,0],[.4,1],[0,1]]
        h=m.reference(c,1e-6)
        self.assertEqual(h['inside'],[1,1,1,0,1,1,1,0])
        self.assertEqual(h['selectedFaces'][9],1)
        self.assertEqual(h['selectedFaces'][10],1)
    def test_anisotropy(self):
        c=copy.deepcopy(self.c);c['lengths'][2]=.002
        h=m.reference(c,1e-6)
        self.assertEqual(h['faces'][9],m.reference(self.c,1e-6)['faces'][9])
        self.assertEqual(h['selectedFaces'][9],1)
    def test_rigid_cap_substitution_is_gap(self):
        h=m.reference(self.c,1e-6);h['faces'][9]=0;h['selectedFaces'][9]=4
        result=m.evaluate(self.c,h)
        self.assertEqual(result['status'],'conformance-gap');self.assertEqual(result['capSubstitutionCoefficientCount'],1)
    def test_bad_topology_rejected(self):
        h=m.reference(self.c,1e-6);h['faces'][0]=-1
        with self.assertRaises(ValueError):m.evaluate(self.c,h)
    def test_nonfinite_rejected(self):
        h=m.reference(self.c,1e-6);h['faces'][0]=math.nan
        with self.assertRaises(ValueError):m.evaluate(self.c,h)
    def test_identity_matters_for_rigid_faces(self):
        h=m.reference(self.c,1e-6);h['selectedFaces'][0]=4
        self.assertEqual(m.evaluate(self.c,h)['selectedFaceMismatchCount'],1)
    def test_standard_matrix_and_uniform_clock_scaling(self):
        self.assertEqual(len(m.standard_cases()),18)
        for c in m.standard_cases():
            a=m.reference(c,1e-6);b=m.reference(c,2e-6)
            self.assertTrue(all(x==-1 or abs(y-2*x)<1e-10 for x,y in zip(a['faces'],b['faces'])))
            self.assertEqual(m.evaluate(c,a)['status'],'passed')
unittest.main()
