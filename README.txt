MediaCloud Python API Client
============================

This module is an simple *under construction* demonstration MediaCloud api client written 
in Python.  It demonstrates pulling stories via the MediaCloud API, processing them via an 
event subscription to add metadata, and storing all the metadata to a CouchDB or MongoDB 
document database.

Installation
------------

Download the distribution zip, then run

    python setup.py install

Install and run [CouchDB](http://couchdb.apache.org) or [MongoDb](http://mongodb.org) to store 
article info.

Examples
--------

### Getting Stories from Media Cloud

You can fetch the latest stories from MediaCloud like this:

    from mediacloud.api import MediaCloud
    mc = MediaCloud( api_username, api_password )
    results = mc.recentStories()

You can fetch information about a specific story like this:

    from mediacloud.api import MediaCloud
    mc = MediaCloud( api_username, api_password )
    results = mc.storyDetail(story_id)

You can fetch the stories created after a specific story like this:

    from mediacloud.api import MediaCloud
    mc = MediaCloud( api_username, api_password )
    results = mc.storiesSince(story_id)

### Saving Stories to CouchDB

You can save those stories to a local 'mediacloud' CouchDB database like this:

    from mediacloud.api import MediaCloud
    from mediacloud.storage import CouchStoryDatabase
    mc = MediaCloud( api_username, api_password )
    results = mc.recentStories()
    db = CouchStoryDatabase('mediacloud')
    for story in results:
      worked = db.addStory(story)

### Saving Stories to MongoDB

You can save those stories to a local 'mediacloud' MongoDB database like this 
(in a `stories` collection):

    from mediacloud.api import MediaCloud
    from mediacloud.storage import MongoStoryDatabase
    mc = MediaCloud( api_username, api_password )
    results = mc.recentStories()
    db = MongoStoryDatabase('mediacloud')
    for story in results:
      worked = db.addStory(story)

### Adding Metadata via Callbacks

We have a simple callback mechanism for subscribing to database save events.  This 
example adds a piece of metadata ("coolness") to the story that gets saved with it 
when the story is inserted into the database:

    from mediacloud.api import MediaCloud
    from mediacloud.storage import StoryDatabase
    from pubsub import pub
    
    def myCallback(db_story, raw_story):
        db_story['coolness'] = 10
    pub.subscribe(myCallback, StoryDatabase.EVENT_PRE_STORY_SAVE)
    
    mc = MediaCloud( api_username, api_password )
    results = mc.recentStories()
    
    db = StoryDatabase('mediacloud')
    for story in results:
      worked = db.addStory(story)   # this will fire the myCallback for each story

### Downloading a Subset of Articles

