
import unittest
import ConfigParser
from mediacloud.api import MediaCloud

class ApiTest(unittest.TestCase):

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')

    def testRecentStories(self):
        mc = MediaCloud(None,None,True)
        stories = mc.recentStories()
        self.assertEquals(len(stories), 30)

    def testRecentStoriesForReal(self):
        mc = MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        # test basic fetch
        stories = mc.recentStories()
        self.assertEquals(len(stories), mc.DEFAULT_STORY_COUNT)
        # test story limit
        stories = mc.recentStories(10)
        self.assertEquals(len(stories), 10)
        for story in stories:
          self.assertFalse(story.has_key('first_raw_download_file'))
        # test raw download option
        stories = mc.recentStories(10,True)
        for story in stories:
          self.assertTrue(story.has_key('first_raw_download_file'))

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
