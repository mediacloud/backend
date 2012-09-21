
import couchdb
from pubsub import pub

class StoryDB(object):
    '''
    For now this is CouchDB implementation, but this API should support later extraction
    to allow for multiple backing database technologies
    '''

    # callbacks you can register listeners against
    EVENT_PRE_STORY_SAVE = "preStorySave"
    EVENT_POST_STORY_SAVE = "postStorySave"

    def __init__(self,db_name):
        '''
        Open a single connection to the database to use for all subsequent calls
        '''
        self._server = couchdb.Server()
        self._db = self._server[db_name]

    def addStory(self,story):
        ''' 
        Save a story (python object) to the database
        '''
        story_attributes = {
          '_id': str(story['stories_id']),
          'title': story['title'],
          'url': story['url'],
          'media_id': story['media_id'],
          'collect_date': story['collect_date'],
          'publish_date': story['publish_date'],
          'description': story['description'],
          'guid': story['guid'],
          'fully_extracted': story['fully_extracted'],
          'stories_id': story['stories_id'],
          'story_sentences_count': len(story['story_sentences']),
        }
        pub.sendMessage(self.EVENT_PRE_STORY_SAVE, db_story=story_attributes, raw_story=story)
        self._db.save( story_attributes )
        saved_story = self.getStory( str(story['stories_id']) )
        pub.sendMessage(self.EVENT_POST_STORY_SAVE, db_story=story_attributes, raw_story=story)
        
    def getStory(self,story_id):
        '''
        Return a story (python object)
        '''
        return self._db[story_id]
