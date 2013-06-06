
import unittest
from mediacloud.storage import *

class StorageTest(unittest.TestCase):

    TEST_DB_NAME = 'mediacloud-test'

    def _createThenDeleteDb(self,db):
        db.createDatabase(self.TEST_DB_NAME)
        db.deleteDatabase(self.TEST_DB_NAME)

    def _addStoryToDb(self, db):
        story = self._getFakeStory()
        db.createDatabase(self.TEST_DB_NAME)
        worked = db.addStory(story)
        self.assertTrue(worked)
        worked = db.addStory(story)
        self.assertFalse(worked)
        saved_story = db.getStory(str(story['stories_id']))
        self.assertNotEqual(saved_story,None)
        self.assertEquals(int(saved_story['_id']), story['stories_id'])
        self.assertEquals(saved_story['story_sentences_count'], 2)
        db.deleteDatabase(self.TEST_DB_NAME)

    def _checkStoryExistsInDb(self, db):
        story = self._getFakeStory()
        db.createDatabase(self.TEST_DB_NAME)
        db.addStory(story)
        saved_story = db.getStory(str(story['stories_id']))
        self.assertTrue(db.storyExists(str(story['stories_id'])))
        self.assertFalse(db.storyExists('43223535'))
        db.deleteDatabase(self.TEST_DB_NAME)

    def _testMaxStoryIdInDb(self, db):
        story1 = self._getFakeStory()
        story1['stories_id'] = "1000"
        story2 = self._getFakeStory()
        story1['stories_id'] = "2000"
        db.createDatabase(self.TEST_DB_NAME)
        db.initialize()
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
            'sentence1',
            'sentence2',
           ],
        }
        return story_attributes

class CouchStorageTest(StorageTest):

    def testManageDatabase(self):
        db = CouchStoryDatabase()
        self._createThenDeleteDb(db)

    def testAddStory(self):
        db = CouchStoryDatabase()
        self._addStoryToDb(db)

    def testStoryExists(self):
        db = CouchStoryDatabase()
        self._checkStoryExistsInDb(db)

    def testGetMaxStoryId(self):
        db = CouchStoryDatabase()
        self._testMaxStoryIdInDb(db)

    def testCreateMaxIdView(self):
        db = CouchStoryDatabase()
        db.createDatabase(self.TEST_DB_NAME)
        db.initialize()
        self.assertEquals(db.getMaxStoryId(),0)
        db.deleteDatabase(self.TEST_DB_NAME)        

class MongoStorageTest(StorageTest):

    def testManageDatabsae(self):
        db = MongoStoryDatabase()
        self._createThenDeleteDb(db)

    def testAddStory(self):
        db = MongoStoryDatabase()
        self._addStoryToDb(db)

    def testStoryExists(self):
        db = MongoStoryDatabase()
        self._checkStoryExistsInDb(db)

    def testGetMaxStoryId(self):
        db = MongoStoryDatabase()
        self._testMaxStoryIdInDb(db)
