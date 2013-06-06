MediaCloud Python API Client
============================

This is the source code of the python MediaCloud API module.  It is a siple *under construction* 
demonstration MediaCloud api client written in Python.  It lets you pull subsets of stories via 
the MediaCloud API, process them via an event subscription to add metadata, and store them in a 
CouchDB or MongoDB document database.

Installation
------------

Download the distribution zip, then run

    python setup.py install

Install and run [CouchDB](http://couchdb.apache.org) or [MongoDb](http://mongodb.org) to store 
article info.

Distribution
------------

To build the distributon, run `python setup.py sdist` and a compressed file will be created in 
the `dist` directory.

Examples
--------

### Getting the Latest Stories from Media Cloud

You can fetch the latest 20 processed stories from MediaCloud like this:

    from mediacloud.api import MediaCloud
    mc = MediaCloud( api_username, api_password )
    stories = mc.allProcessed()

### Saving Stories to CouchDB

You can save those stories to a local 'mediacloud' CouchDB database like this:

    from mediacloud.api import MediaCloud
    from mediacloud.storage import CouchStoryDatabase
    mc = MediaCloud( api_username, api_password )
    stories = mc.allProcessed()
    db = CouchStoryDatabase('mediacloud')
    for story in stories:
      worked = db.addStory(story)

### Saving Stories to MongoDB

You can save those stories to a local 'mediacloud' MongoDB database like this 
(in a `stories` collection):

    from mediacloud.api import MediaCloud
    from mediacloud.storage import MongoStoryDatabase
    mc = MediaCloud( api_username, api_password )
    stories = mc.recentStories()
    db = MongoStoryDatabase('mediacloud')
    for story in stories:
      worked = db.addStory(story)

### Adding Metadata via Callbacks

We have a simple callback mechanism for subscribing to database save events.  This 
example adds a piece of metadata with the source name to the story that gets saved with it 
when the story is inserted into the database:

    from mediacloud.api import MediaCloud
    from mediacloud.storage import StoryDatabase
    from pubsub import pub
    
    mc = MediaCloud( api_username, api_password )

    def addSourceNameCallback(db_story, raw_story):
        db_story['source_name'] = mc.mediaInfo(db_story['media_id'])
    pub.subscribe(addSourceNameCallback, StoryDatabase.EVENT_PRE_STORY_SAVE)
    
    stories = mc.recentStories()
    
    db = StoryDatabase('mediacloud')
    for story in stories:
      worked = db.addStory(story)   # this will automatically call addSourceNameCallback for each story

### Downloading a Subset of Articles

To Do...