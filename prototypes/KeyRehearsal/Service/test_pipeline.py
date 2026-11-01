import unittest
from pipeline import make_guide

class GuideTests(unittest.TestCase):
    def test_clips_filters_and_retains_offset(self):
        p = make_guide([(-.1,.8,60,.8), (.9,.95,62,.9), (1,1.5,64,.05), (2,4,67,.9)], 3, 60)
        self.assertEqual(len(p['notes']), 2)
        self.assertEqual(p['notes'][0]['start'], 0)
        self.assertEqual(p['notes'][-1]['end'], 3)
        self.assertEqual(p['sourceOffset'], 60)
        self.assertEqual(p['segments'][0]['start'], 0)
        self.assertEqual(p['segments'][-1]['end'], 3)
    def test_no_split_inside_held_polyphonic_note(self):
        p = make_guide([(0,10,60,.8), (2,3,64,.9), (4,5,67,.9)], 12, 0)
        self.assertEqual(len(p['segments']), 1)
    def test_silence_fails(self):
        with self.assertRaises(ValueError): make_guide([], 5, 0)
    def test_phrases_contiguous(self):
        p = make_guide([(0,1,60,.8), (2,3,62,.8), (4,5,64,.8)], 6, 0)
        for a,b in zip(p['segments'],p['segments'][1:]): self.assertEqual(a['end'],b['start'])

if __name__ == '__main__': unittest.main()
