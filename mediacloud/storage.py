
import couchdb
from pubsub import pub

class StoryDatabase(object):
    '''
    For now this is CouchDB implementation, but this API should support later extraction
    to allow for multiple backing database technologies
    '''

    # callbacks you can register listeners against
    EVENT_PRE_STORY_SAVE = "preStorySave"
    EVENT_POST_STORY_SAVE = "postStorySave"

    def __init__(self,db_name=None):
        self._server = couchdb.Server()
        if db_name is not None:
          self.selectDatabase(db_name)
    
    def storyExists(self,story_id):
        '''
        Is this story id in the database already?
        '''
        
        try:
          self._db[story_id]
        except couchdb.ResourceNotFound:
          return False
        return True

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

    def selectDatabase(self, db_name):
        self._db = self._server[db_name]

    def createDatabase(self, db_name):
        self._server.create(db_name)
        self.selectDatabase(db_name)
        
    def deleteDatabase(self, db_name):
        del self._server[db_name]
        
    def getMaxStoryId(self):
        map_function = "function(doc) { emit(null, doc._id); }"
        results = self._db.query(map_function)
        ids = []
        for row in results:
            ids.append(int(row.id))
        if ( len(ids) == 0 ):
          return 0
        return max(ids)
