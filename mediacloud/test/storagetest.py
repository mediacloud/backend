
import unittest, os, json
from mediacloud.storage import *

class StorageTest(unittest.TestCase):

    TEST_DB_NAME = 'mediacloud-test'

    def _createThenDeleteDb(self,db):
        db.createDatabase(self.TEST_DB_NAME)
        db.deleteDatabase(self.TEST_DB_NAME)

    def _addStoryFromSentencesToDb(self, db):
        story_sentences = self._getFakeStorySentences(1)['207593389']
        db.createDatabase(self.TEST_DB_NAME)
        worked = db.addStoryFromSentences(story_sentences)
        self.assertTrue(worked)
        saved_story = db.getStory(story_sentences[0]['stories_id'])
        self.assertNotEqual(saved_story,None)
        self.assertEquals(saved_story['stories_id'], story_sentences[0]['stories_id'])
        self.assertEquals(saved_story['story_sentences_count'], 20)
        db.deleteDatabase(self.TEST_DB_NAME)

    def _addStoryFromSentencesToDbWithAttributes(self, db):
        story_sentences = self._getFakeStorySentences(1)['207593389']
        db.createDatabase(self.TEST_DB_NAME)
        worked = db.addStoryFromSentences(story_sentences, {'group':'test'})
        self.assertTrue(worked)
        saved_story = db.getStory(story_sentences[0]['stories_id'])
        self.assertNotEqual(saved_story,None)
        self.assertEquals(saved_story['stories_id'], story_sentences[0]['stories_id'])
        self.assertEquals(saved_story['story_sentences_count'], 20)
        self.assertEquals(saved_story['group'], 'test')
        db.deleteDatabase(self.TEST_DB_NAME)

    def _updateStoryFromSentencesToDb(self, db):
        # load up first page of sentences in story
        story_sentences = self._getFakeStorySentences(1)['207593389']
        db.createDatabase(self.TEST_DB_NAME)
        self.assertEquals(len(story_sentences),20)
        worked = db.addStoryFromSentences(story_sentences)
        self.assertTrue(worked)
        # make sure it saved right
        saved_story = db.getStory(story_sentences[0]['stories_id'])
        self.assertNotEqual(saved_story,None)
        self.assertEquals(saved_story['stories_id'], story_sentences[0]['stories_id'])
        self.assertEquals(saved_story['story_sentences_count'], 20)
        self.assertEquals(len(saved_story['story_sentences']), 20)
        # load up second page of sentences in story
        story_sentences = self._getFakeStorySentences(2)['207593389']
        self.assertEquals(len(story_sentences),6)
        worked = db.addStoryFromSentences(story_sentences)
        # make sure update merged the sentences right
        saved_story = db.getStory(story_sentences[0]['stories_id'])
        self.assertEquals(len(saved_story['story_sentences']), 26)
        self.assertEquals(saved_story['story_sentences_count'], 26)
        # now add some extra attributes
        story_sentences = self._getFakeStorySentences(2)['207593389']
        self.assertEquals(len(story_sentences),6)
        worked = db.addStoryFromSentences(story_sentences, {'group':'test2'})
        saved_story = db.getStory(story_sentences[0]['stories_id'])
        self.assertEquals(len(saved_story['story_sentences']), 26)
        self.assertEquals(saved_story['story_sentences_count'], 26)
        self.assertEquals(saved_story['group'], 'test2')

    def _updateStoryInDb(self, db):
        story = self._getFakeStory()
        db.createDatabase(self.TEST_DB_NAME)
        # first save it normally
        worked = db.updateStory(story)
        self.assertTrue(worked)
        saved_story = db.getStory(story['stories_id'])
        self.assertNotEqual(saved_story,None)
        self.assertEquals(saved_story['stories_id'], story['stories_id'])
        self.assertEquals(saved_story['story_sentences_count'], 4)
        self.assertFalse('category' in saved_story)
        # now update it with new info and make sure it is still there
        worked = db.updateStory(story,{'category':'editorial'})
        saved_story = db.getStory(story['stories_id'])
        self.assertNotEqual(saved_story,None)
        self.assertEquals(saved_story['stories_id'], story['stories_id'])
        self.assertEquals(saved_story['story_sentences_count'], 4)
        self.assertTrue('category' in saved_story)
        db.deleteDatabase(self.TEST_DB_NAME)

    def _countStoriesInDb(self,db):
        story1 = self._getFakeStory()
        story1['stories_id'] = "10000000000"
        story2 = self._getFakeStory()
        story1['stories_id'] = "20000000000"
        db.createDatabase(self.TEST_DB_NAME)
        db.initialize()
        db.addStory(story1)
        db.addStory(story2)
        self.assertEquals(db.storyCount(),2)
        db.deleteDatabase(self.TEST_DB_NAME)       

    def _addStoryToDb(self, db):
        story = self._getFakeStory()
        db.createDatabase(self.TEST_DB_NAME)
        worked = db.addStory(story)
        self.assertTrue(worked)
        worked = db.addStory(story)
        self.assertFalse(worked)
        saved_story = db.getStory(story['stories_id'])
        self.assertNotEqual(saved_story,None)
        self.assertEquals(saved_story['stories_id'], story['stories_id'])
        self.assertEquals(saved_story['story_sentences_count'], 4)
        db.deleteDatabase(self.TEST_DB_NAME)

    def _checkStoryExistsInDb(self, db):
        story = self._getFakeStory()
        db.createDatabase(self.TEST_DB_NAME)
        db.addStory(story)
        saved_story = db.getStory(story['stories_id'])
        self.assertTrue(db.storyExists(story['stories_id']))
        self.assertFalse(db.storyExists('43223535'))
        db.deleteDatabase(self.TEST_DB_NAME)

    def _testMaxStoryIdInDb(self, db):
        story1 = self._getFakeStory()
        story1['stories_id'] = "10000000000"
        story2 = self._getFakeStory()
        story1['stories_id'] = "20000000000"
        db.createDatabase(self.TEST_DB_NAME)
        db.initialize()
        db.addStory(story1)
        db.addStory(story2)
        self.assertEquals(db.getMaxStoryId(),20000000000)
        db.deleteDatabase(self.TEST_DB_NAME)           

    def _getFakeStory(self):
        my_file = open(os.path.dirname(os.path.realpath(__file__))+'/fixtures/story_27456565.json', 'r')
        return json.loads( my_file.read() )

    def _getFakeStorySentences(self,page=1):
        my_file = open(os.path.dirname(os.path.realpath(__file__))+'/fixtures/sentences_by_story_'+str(page)+'.json', 'r')
        return json.loads( my_file.read() )

class MongoStorageTest(StorageTest):

    def testManageDatabsae(self):
        db = MongoStoryDatabase()
        self._createThenDeleteDb(db)

    def testGetMaxStoryId(self):
        db = MongoStoryDatabase()
        self._testMaxStoryIdInDb(db)

    def testStoryExists(self):
        db = MongoStoryDatabase()
        self._checkStoryExistsInDb(db)

    def testAddStory(self):
        db = MongoStoryDatabase()
        self._addStoryToDb(db)

    def testUpdateStory(self):
        db = MongoStoryDatabase()
        self._updateStoryInDb(db)

    def testStoryCount(self):
        db = MongoStoryDatabase()
        self._countStoriesInDb(db)

    def testAddStoryFromSentencesWithAttributes(self):
        db = MongoStoryDatabase()
        self._addStoryFromSentencesToDbWithAttributes(db)

    def testAddStoryFromSentences(self):
        db = MongoStoryDatabase()
        self._addStoryFromSentencesToDb(db)

    def testUpdateStoryFromSentences(self):
        db = MongoStoryDatabase()
        self._updateStoryFromSentencesToDb(db)

