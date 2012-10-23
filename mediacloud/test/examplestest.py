
import unittest
from mediacloud.api import MediaCloud
import mediacloud.examples

class ExamplesTest(unittest.TestCase):

    def testFleshKincaidGradeLevel(self):
        story_id = 88848861
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(story_id)
        fkLevel = mediacloud.examples.getFleshKincaidGradeLevel(story['story_text'])
        self.assertEquals(round(fkLevel), 8)
        fkLevel = mediacloud.examples.getFleshKincaidGradeLevel("")
        self.assertTrue( fkLevel==None )
        fkLevel = mediacloud.examples.getFleshKincaidGradeLevel(None)
        self.assertTrue( fkLevel==None )

    def testWordCount(self):
        story_id = 88848861
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(story_id)
        word_count = mediacloud.examples.getWordCount(story['description'])
        self.assertEquals(word_count, 10436)
  
    def testIsEnglish(self):
        mc = MediaCloud(None,None,True)
        english_story_id = 88848861
        story = mc.storyDetail(english_story_id)
        is_english = mediacloud.examples.isEnglish(story['story_text'])
        self.assertTrue(is_english)
        # TODO: find a real example in the MC curpus
        story['story_text'] = "Esto es un otro cuenta en espanol" 
        is_english = mediacloud.examples.isEnglish(story['story_text'])
        self.assertFalse(is_english)