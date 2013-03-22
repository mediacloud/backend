
import unittest
from mediacloud.api import MediaCloud
import mediacloud.examples
import tldextract

class ExamplesTest(unittest.TestCase):

    TEST_STORY_ID = 88848860

    def testFleshKincaidGradeLevel(self):
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(self.TEST_STORY_ID)
        fkLevel = mediacloud.examples.getFleshKincaidGradeLevel(story['story_text'])
        self.assertEquals(round(fkLevel), 7)
        fkLevel = mediacloud.examples.getFleshKincaidGradeLevel("")
        self.assertTrue( fkLevel==None )
        fkLevel = mediacloud.examples.getFleshKincaidGradeLevel(None)
        self.assertTrue( fkLevel==None )

    def testWordCount(self):
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(self.TEST_STORY_ID)
        word_count = mediacloud.examples.getWordCount(story['description'])
        self.assertEquals(word_count, 1270)
  
    def testIsEnglish(self):
        mc = MediaCloud(None,None,True)
        english_story_id = self.TEST_STORY_ID
        story = mc.storyDetail(english_story_id)
        is_english = mediacloud.examples.isEnglish(story['story_text'])
        self.assertTrue(is_english)
        # TODO: find a real example in the MC curpus
        story['story_text'] = "Esto es un otro cuenta en espanol" 
        is_english = mediacloud.examples.isEnglish(story['story_text'])
        self.assertFalse(is_english)

    def testDomainExtraction(self):
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(self.TEST_STORY_ID)
        domain_parts = mediacloud.examples.getDomainInfo(story)
        self.assertEquals(domain_parts.subdomain,'feedproxy')
        self.assertEquals(domain_parts.domain,'google')
        self.assertEquals(domain_parts.tld,'com')

