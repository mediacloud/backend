import copy, logging

class StoryDatabase(object):

    # callbacks you can register listeners against
    EVENT_PRE_STORY_SAVE = "preStorySave"
    EVENT_POST_STORY_SAVE = "postStorySave"

    def __init__(self):
        self._logger = logging.getLogger(__name__)

    def connect(self, db_name, host, port, username, password):
        raise NotImplementedError("Subclasses should implement this!")

    def storyExists(self, story_id):
        raise NotImplementedError("Subclasses should implement this!")

    def addStoryFromSentences(self, story_sentences, extra_attributes={}):
        '''
        Save a story based on it's sentences to the database.  Return success or failure boolean.
        This is pairs well with mediacloud.sentencesMatchingByStory(...).  This saves or updates.
        '''
        # if nothing to save, bail
        if len(story_sentences)==0:
            return False
        # verify all the sentences are part of the same story
        stories_id_list = set( [ s['stories_id'] for s in story_sentences ] )
        if len(stories_id_list)>1:
            raise Exception('Expecting all the sentences to be part of the same story (ie. one entry from mediacloud.sentencesMatchingByStory)')
        stories_id = list(stories_id_list)[0]
        # save or update the story
        sentences_by_number = {str(s['sentence_number']):s['sentence'] for s in sorted(story_sentences, key=lambda x: x['sentence_number'], reverse=True)}
        if not self.storyExists(stories_id):
            # if the story is new, save it all
            story_attributes = {
                'stories_id': stories_id,
                'media_id': story_sentences[0]['media_id'],
                'publish_date': story_sentences[0]['publish_date'],
                'language': story_sentences[0]['language'],
                'story_sentences': sentences_by_number,
                'story_sentences_count': len(sentences_by_number)
            }
            self._saveStory( dict(story_attributes.items() + extra_attributes.items()) )
        else:
            # if the story exists already, add any new sentences
            story = self.getStory(stories_id)
            all_sentences = dict(story['story_sentences'].items() + sentences_by_number.items())
            story_attributes = {
                'stories_id': stories_id,
                'story_sentences': all_sentences,
                'story_sentences_count': len(all_sentences)
            }
            self._updateStory( dict(story_attributes.items() + extra_attributes.items()) )
        return True

    def updateStory(self, story, extra_attributes={}):
        # if it is a new story, just add it normally
        if not self.storyExists(story['stories_id']):
            return self.addStory(story,extra_attributes)
        else:
            story_to_save = copy.deepcopy( story )
            story_to_save = dict(story_to_save.items() + extra_attributes.items())
            story_to_save['stories_id'] = story['stories_id']
            if 'story_sentences' in story:
                story_to_save['story_sentences_count'] = len(story['story_sentences'])
            self._updateStory(story_to_save)
            saved_story = self.getStory( story['stories_id'] )
            self._logger.debug('Updated '+str(story['stories_id']))

    def addStory(self, story, extra_attributes={}):
        ''' 
        Save a story (python object) to the database. This does NOT update stories.
        Return success or failure boolean.
        '''
        if self.storyExists(story['stories_id']):
            self._logger.warn('Not saving '+str(story['stories_id'])+' - already exists')
            return False
        story_to_save = copy.deepcopy( story )
        story_to_save = dict(story_to_save.items() + extra_attributes.items())
        story_to_save['_stories_id'] = story['stories_id']
        if 'story_sentences' in story:
            story_to_save['story_sentences_count'] = len(story['story_sentences'])
        self._saveStory( story_to_save )
        saved_story = self.getStory( story['stories_id'] )
        self._logger.debug('Saved '+str(story['stories_id']))
        return True

    def _updateStory(self, story_attributes):
        raise NotImplementedError("Subclasses should implement this!")

    def _saveStory(self, story_attributes):
        raise NotImplementedError("Subclasses should implement this!")

    def getStory(self, story_id):
        raise NotImplementedError("Subclasses should implement this!")

    def storyCount(self):
        raise NotImplementedError("Subclasses should implement this!")        

    def createDatabase(self, db_name):
        raise NotImplementedError("Subclasses should implement this!")
        
    def deleteDatabase(self, db_name):
        raise NotImplementedError("Subclasses should implement this!")
        
    def getMaxStoryId(self):
        raise NotImplementedError("Subclasses should implement this!")

    def initialize(self):
        raise NotImplementedError("Subclasses should implement this!")

class MongoStoryDatabase(StoryDatabase):

    def __init__(self, db_name=None, host='127.0.0.1', port=27017, username=None, password=None):
        super(MongoStoryDatabase, self).__init__()
        import pymongo
        self._server = pymongo.MongoClient(host, port)
        if db_name is not None:
            self.selectDatabase(db_name)

    def createDatabase(self, db_name):
        self.selectDatabase(db_name)

    def selectDatabase(self, db_name):
        self._db = self._server[db_name]

    def deleteDatabase(self, ignored):
        self._db.drop_collection('stories')

    def storyCount(self):
        self._db.stories.count();

    def storyExists(self, story_id):
        story = self.getStory(story_id)
        return story != None

    def _updateStory(self, story_attributes):
        story = self.getStory(story_attributes['stories_id'])
        story_attributes['_id'] = story['_id']
        story_id = self._db.stories.save(story_attributes)
        story = self.getStory(story_attributes['stories_id'])
        return story

    def _saveStory(self, story_attributes):
        story_db_id = self._db.stories.insert(story_attributes)
        story = self.getStory(story_attributes['stories_id'])
        return story

    def getStory(self, story_id):
        stories = self._db.stories.find( { "stories_id": story_id } ).limit(1)
        if stories.count()==0:
            return None
        return stories.next()

    def getMaxStoryId(self):
        max_story_id = 0
        if self._db.stories.count() > 0 :
            max_story_id = self._db.stories.find().sort("stories_id",-1)[0]['stories_id']
        return int(max_story_id)

    def initialize(self):
        # nothing to init for mongo
        return

    def storyCount(self):
        return self._db['stories'].count()
