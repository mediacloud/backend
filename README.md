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
    stories = mc.allProcessed()
    db = MongoStoryDatabase('mediacloud')
    for story in stories:
      worked = db.addStory(story)

### Adding Metadata via Callbacks

We have a simple callback mechanism for subscribing to database save events.  This 
example adds a piece of metadata with the source name to the story that gets saved with it 
when the story is inserted into the database:

    from mediacloud.api import MediaCloud
    from mediacloud.storage import StoryDatabase, MongoStoryDatabase
    from pubsub import pub
    
    mc = MediaCloud( api_username, api_password )

    def addSourceNameCallback(db_story, raw_story):
        db_story['source_name'] = mc.mediaInfo(db_story['media_id'])['name']
    pub.subscribe(addSourceNameCallback, StoryDatabase.EVENT_PRE_STORY_SAVE)
    
    stories = mc.allProcessed()
    
    db = MongoStoryDatabase('mediacloud')
    for story in stories:
      worked = db.addStory(story)   # this will automatically call addSourceNameCallback for each story

### Downloading a Subset of Articles

This is asynchronous, so it takes a bit more work.

#### Step 1: Create a subset

The first step is telling MediaCloud what set of articles you want.  This examples grabs
all the stories on two dates from the New York Times (media_id 1 as found in 
`mediacloud/data/media_ids.csv`)

    mc = MediaCloud( api_username, api_password )
    subset_id = mc.createStorySubset('2012-01-01','2012-01-02',1)

The `subset_id` you get back is important to keep track of.  Now MediaCould will go off
and gather all the articles it has for you.

#### Step 2: Check if the subset is ready

You can check every once in a while to see if MediaCloud is done gathering the articles.
This code checks to see if the with the id returned in the Step 1 is ready to be downloaded.

    ready = mc.isStorySubsetReady(subset_id):

The `ready` variable is boolean.

#### Step 3: Download all your articles

Once `ready == True`, you are free to download all your articles.  This works just like
the `allProcessed()` method, in that you page through results (basde on your `subset_id`).

    db = MongoStoryDatabase('mediacloud')
    more_stories = True
    while more_stories:
      stories = mc.allProcessedInSubset(subset_id,1)
      if len(stories)==0:
        more_stories = False
      for story in stories:
        worked = db.addStory(story)

Testing
-------

First run all the tests.  Copy `mc-client.config.template` to `mc-client.config` and edit it.
Then run `python tests.py`.

Distribution
------------

To build the distributon, run `python setup.py sdist` and a compressed file will be created in 
the `dist` directory.
