
import unittest
from mediacloud.api import MediaCloud
import mediacloud.examples

class ExamplesTest(unittest.TestCase):

    def testFleshKincaidGradeLevel(self):
        story_id = 88848861
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(story_id)
        fkLevel = mediacloud.examples._getFleshKincaidGradeLevel(story['story_text'])
        self.assertEquals(round(fkLevel), 8)
        fkLevel = mediacloud.examples._getFleshKincaidGradeLevel("")
        self.assertTrue( fkLevel==None )
        fkLevel = mediacloud.examples._getFleshKincaidGradeLevel(None)
        self.assertTrue( fkLevel==None )

    def testWordCount(self):
        story_id = 88848861
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(story_id)
        word_count = mediacloud.examples._getWordCount(story['description'])
        self.assertEquals(word_count, 10436)
