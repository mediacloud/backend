import copy

class StoryDatabase(object):

    # callbacks you can register listeners against
    EVENT_PRE_STORY_SAVE = "preStorySave"
    EVENT_POST_STORY_SAVE = "postStorySave"

    def __init__(self):
        None

    def connect(self, db_name, host, port, username, password):
        raise NotImplementedError("Subclasses should implement this!")

    def storyExists(self, story_id):
        raise NotImplementedError("Subclasses should implement this!")

    def addStoryFromSentences(self, story_sentences, extra_attributes={}):
        '''
        Save a story based on it's sentences to the database.  Return success or failure boolean.
        This is pairs well with mediacloud.sentencesMatchingByStory(...).  This saves or updates.
        '''
        from pubsub import pub
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
                '_id': str(stories_id),
                'media_id': story_sentences[0]['media_id'],
                'publish_date': story_sentences[0]['publish_date'],
                'language': story_sentences[0]['language'],
                'sentences': sentences_by_number,
                'story_sentences_count': len(sentences_by_number)
            }
            self._saveStory( dict(story_attributes.items() + extra_attributes.items()) )
        else:
            # if the story exists already, add any new sentences
            story = self.getStory(stories_id)
            all_sentences = dict(story['sentences'].items() + sentences_by_number.items())
            story_attributes = {
                '_id': str(stories_id),
                'sentences': all_sentences,
                'story_sentences_count': len(all_sentences)
            }
            self._updateStory( dict(story_attributes.items() + extra_attributes.items()) )
        return True

    def addStory(self, story, save_extracted_text=False, save_raw_download=False, save_story_sentences=False):
        ''' 
        DEPRECATED!!!
        Save a story (python object) to the database.  Return success or failure boolean.
        '''
        from pubsub import pub
        if self.storyExists(str(story['stories_id'])):
            return False
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
        }
        if( (save_extracted_text==True) and ('story_text' in story) ):
            story_attributes['story_text'] = story['story_text']
        if( (save_raw_download==True) and ('first_raw_download_file' in story) ):
            story_attributes['first_raw_download_file'] = story['first_raw_download_file']
        if('story_sentences' in story):
            story_attributes['story_sentences_count'] = len(story['story_sentences'])
            if( save_story_sentences==True ):
                story_attributes['story_sentences'] = story['story_sentences']
        pub.sendMessage(self.EVENT_PRE_STORY_SAVE, db_story=story_attributes, raw_story=story)
        self._saveStory(story_attributes)
        saved_story = self.getStory( str(story['stories_id']) )
        pub.sendMessage(self.EVENT_POST_STORY_SAVE, db_story=story_attributes, raw_story=story)
        return True

    def _updateStory(self, story_attributes):
        raise NotImplementedError("Subclasses should implement this!")

    def _saveStory(self, story_attributes):
        raise NotImplementedError("Subclasses should implement this!")

    def getStory(self, story_id):
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

    def storyExists(self, story_id):
        story = self._db.stories.find_one( { "_id": int(story_id) } )
        return story != None

    def _updateStory(self, story_attributes):
        story_attributes['_id'] = int(story_attributes['_id'])
        stories = self._db.stories
        story_id = stories.save(story_attributes)
        story = stories.find_one( { "_id": int(story_id) } )
        return story

    def _saveStory(self, story_attributes):
        story_attributes['_id'] = int(story_attributes['_id'])
        stories = self._db.stories
        story_id = stories.insert(story_attributes)
        story = stories.find_one( { "_id": int(story_id) } )
        return story

    def getStory(self, story_id):
        stories = self._db.stories
        story = stories.find_one( { "_id": int(story_id) } )
        return story

    def getMaxStoryId(self):
        max_story_id = 0
        if self._db.stories.count() > 0 :
            max_story_id = self._db.stories.find().sort("_id",-1)[0]['_id']
        return int(max_story_id)

    def initialize(self):
        # nothing to init for mongo
        return

    def storyCount(self):
        return self._db['stories'].count()

class CouchStoryDatabase(StoryDatabase):

    def __init__(self, db_name=None, host='127.0.0.1', port=5984, username=None, password=None):
        super(CouchStoryDatabase, self).__init__()
        import couchdb
        if (username is not None) and (password is not None):
            url = "http://"+username+":"+password+"@"
        else:
            url = "http://"
        url = url + host+":"+str(port)
        self._server = couchdb.Server(url)
        if db_name is not None:
          self.selectDatabase(db_name)        

    def initialize(self):
        views = {
          "_id": "_design/examples",
          "language": "javascript",
          "views": {
                "max_story_id": {
                    "map": "function(doc) { emit(doc._id,doc._id);}",
                    "reduce": "function(keys, values) { var ids = [];  values.forEach(function(id) {if (!isNaN(id)) ids.push(id); }); return Math.max.apply(Math, ids); }"
                },
                "total_stories": {
                    "map": "function(doc) { emit(null,1); }",
                    "reduce": "function(keys, values) { return sum(values); }"
                }
          }
        }
        self._db.save(views)

    def storyExists(self, story_id):
        '''
        Is this story id in the database already?
        '''
        try:
            import couchdb
            self._db[story_id]
        except couchdb.ResourceNotFound:
            return False
        return True

    def _saveStory(self, story_attributes):
        self._db.save( story_attributes )
        
    def getStory(self, story_id):
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
        results = self._db.view('examples/max_story_id')
        max_story_id = 0
        if( len(results.rows)==1 ):
            max_story_id = results.rows[0].value
        return max_story_id
