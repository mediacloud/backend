
import unittest
from mediacloud.storage import StoryDatabase

class StorageTest(unittest.TestCase):

    TEST_DB_NAME = 'mediacloud-test'

    def testManageDatabase(self):
        db = StoryDatabase()
        db.createDatabase(self.TEST_DB_NAME)
        db.selectDatabase(self.TEST_DB_NAME)
        db.deleteDatabase(self.TEST_DB_NAME)

    def testSaveStory(self):
        story = self._getFakeStory()
        db = StoryDatabase()
        db.createDatabase(self.TEST_DB_NAME)
        db.addStory(story)
        saved_story = db.getStory(str(story['stories_id']))
        self.assertEquals(saved_story['_id'], str(story['stories_id']))
        self.assertEquals(saved_story['story_sentences_count'], 2)
        db.deleteDatabase(self.TEST_DB_NAME)

    def testStoryExists(self):
        story = self._getFakeStory()
        db = StoryDatabase()
        db.createDatabase(self.TEST_DB_NAME)
        db.addStory(story)
        saved_story = db.getStory(str(story['stories_id']))
        self.assertTrue(db.storyExists(str(story['stories_id'])))
        self.assertFalse(db.storyExists('43223535'))
        db.deleteDatabase(self.TEST_DB_NAME)

    def testGetMaxStoryId(self):
        story1 = self._getFakeStory()
        story1['stories_id'] = "1000"
        story2 = self._getFakeStory()
        story1['stories_id'] = "2000"
        db = StoryDatabase()
        db.createDatabase(self.TEST_DB_NAME)
        self.assertEquals(db.getMaxStoryId(),0)
        db.addStory(story1)
        db.addStory(story2)
        self.assertEquals(db.getMaxStoryId(),2000)
        db.deleteDatabase(self.TEST_DB_NAME)        

    def _getFakeStory(self):
        story_attributes = {
          'stories_id': 1234,
          'title': 'my test story',
          'url': 'www.myserver.com',
          'media_id': 4321,
          'collect_date': '9/2/12',
          'publish_date': '9/2/12',
          'description': 'This is my awesome test story for testing everything.',
          'guid': '23445654634615',
          'fully_extracted': 1,
          'story_sentences': [
            'sentence',
            'sentence',
           ],
        }
        return story_attributes
