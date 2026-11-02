import unittest
import numpy as np
from audit import boundary,quiet_runs
class Boundaries(unittest.TestCase):
 def test_quiet_boundary_stays(self):
  x=np.zeros(400);x[230:]=.1
  r=boundary(x,1.0,0,1.9);self.assertEqual(r['candidate_seconds'],1.0)
 def test_late_cut_moves_before_onset(self):
  x=np.zeros(400);x[200:]=.1
  r=boundary(x,1.05,0,1.9);self.assertLess(r['candidate_seconds'],1.0);self.assertIn('cut_near_active_audio',r['flags'])
 def test_no_gap_does_not_guess(self):
  r=boundary(np.ones(400)*.1,1.0,0,1.9);self.assertEqual(r['candidate_seconds'],1.0);self.assertIn('no_suitable_nearby_quiet_gap',r['flags'])
 def test_competing_gaps_are_flagged(self):
  x=np.ones(400)*.1;x[180:192]=0;x[208:222]=0
  r=boundary(x,1.0,0,1.9);self.assertEqual(r['candidate_seconds'],1.0);self.assertIn('ambiguous_quiet_gaps',r['flags'])
 def test_later_word_gap_not_used(self):
  x=np.ones(400)*.1;x[212:]=0
  r=boundary(x,1.0,0,1.9);self.assertEqual(r['candidate_seconds'],1.0);self.assertIn('only_later_gap_needs_word_review',r['flags'])
 def test_brief_dip_is_not_a_gap(self):
  self.assertEqual(quiet_runs(np.array([False]+[True]*7+[False])),[])
if __name__=='__main__':unittest.main()
