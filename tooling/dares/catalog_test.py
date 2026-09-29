import copy,json,unittest
from catalog import validate,SOURCE
class CatalogTests(unittest.TestCase):
    def setUp(self):self.data=json.loads(SOURCE.read_text())
    def test_reviewed_catalog(self):self.assertEqual(validate(self.data),[])
    def test_short_empty_and_duplicate_lists_fail(self):
        for value in [[],['A photo.']*12,['']*12]:
            d=copy.deepcopy(self.data);d['moods']['Happy']['dares']=value;self.assertTrue(validate(d))
    def test_regressions_fail(self):
        for prompt in ['Record a three-minute video.','Film a 60-second video.','Take a photo while driving.','Hold your breath for a video.','Take a photo to cure anxiety.','Show a fucking photo.','Do something.','Show '+('word '*60)]:
            d=copy.deepcopy(self.data);d['moods']['Happy']['dares'][0]=prompt
            with self.subTest(prompt=prompt):self.assertTrue(validate(d))
    def test_30_seconds_and_normal_off_camera_activity_are_valid(self):
        for text in ['Record a 30-second video of a safe object.','Read a few lines off-camera. Then photograph your closed book.']:
            d=copy.deepcopy(self.data);d['moods']['Happy']['dares'][0]=text;self.assertEqual(validate(d),[])
if __name__=='__main__':unittest.main()
