
import unittest
from mediacloud.api import MediaCloud

class ApiTest(unittest.TestCase):

    def testRecentStories(self):
        mc = MediaCloud(None,None,True)
        stories = mc.recentStories()
        self.assertEquals(len(stories), 30)

    def testStoriesSince(self):
        story_id = 88848861
        mc = MediaCloud(None,None,True)
        stories = mc.storiesSince(story_id)
        self.assertEquals(len(stories), 15)
        for story in stories:
          self.assertTrue( int(story['stories_id']) > story_id)

    def testStoryDetail(self):
        story_id = 88848861
        mc = MediaCloud(None,None,True)
        story = mc.storyDetail(story_id)
        self.assertEquals(story['stories_id'], story_id)
  
    def suite():
        return unittest.makeSuite(ApiTest, 'test')
