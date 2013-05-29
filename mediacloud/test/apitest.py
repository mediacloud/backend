
import unittest
import codecs
import ConfigParser
from mediacloud.api import MediaCloud

class ApiTest(unittest.TestCase):

    TEST_STORY_ID = 88848860

    def setUp(self):
        self._config = ConfigParser.ConfigParser()
        self._config.read('mc-client.config')

    def testParseYaml(self):
        f = codecs.open('mediacloud/test/fixtures/all_processed.yaml', encoding='utf-8')
        mc = MediaCloud()
        stories = mc._parseYamlResults(f.read())
        self.assertEquals(len(stories),20)

    def testParseJsonResults(self):
        # stories since
        story_id = self.TEST_STORY_ID
        mc = MediaCloud()
        f = open('mediacloud/test/fixtures/stories_15_since_'+str(story_id)+'.json','r');
        content = f.read()
        stories = mc._parseJsonResults(content)
        self.assertEquals(len(stories), mc.DEFAULT_STORY_COUNT)
        for story in stories:
          self.assertTrue( int(story['stories_id']) > story_id)
        # recent stories
        f = open('mediacloud/test/fixtures/stories_30_within_last_day.json','r');
        content = f.read()
        stories = mc._parseJsonResults(content)
        self.assertEquals(len(stories), 30)
        # story detail
        story_id = self.TEST_STORY_ID
        f = open('mediacloud/test/fixtures/story_'+str(story_id)+'.json','r');
        content = f.read()
        story = mc._parseJsonResults(content)[0]
        self.assertEquals(story['stories_id'], story_id)

    def testRecentStories(self):
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
        mc = MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        story_id = self.TEST_STORY_ID
        stories = mc.storiesSince(story_id)
        self.assertEquals(len(stories), mc.DEFAULT_STORY_COUNT)
        for story in stories:
            self.assertTrue(int(story['stories_id'])>story_id)

    def testStoryDetail(self):
        mc = MediaCloud( self._config.get('api','user'), self._config.get('api','pass') )
        story_id = self.TEST_STORY_ID
        story = mc.storyDetail(story_id)
        self.assertEquals(story['stories_id'], story_id)
  
    def suite():
        return unittest.makeSuite(ApiTest, 'test')
