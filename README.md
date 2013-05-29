MediaCloud Python API Client
============================

This module is an simple *under construction* demonstration MediaCloud api client written 
in Python.  It demonstrates pulling stories via the MediaCloud API, processing them via an 
event subscription to add metadata, and storing all the metadata to a CouchDB or MongoDB 
document database.

Installation
------------

Make sure you have Python > 2.6 (and setuptools) and then install the python dependencies:
    
    pip install pypubsub
    pip install nltk
    pip install couchdb
    pip install pymongo
    pip install tldextract
    pip install pyyaml
    
Install and run [CouchDB](http://couchdb.apache.org) or [MongoDb](http://mongodb.org) to store 
article info.

Copy the `mc-client.config.template` to `mc-client.config` and edit it, putting in the 
API username and password.  Then if you are using CouchDB run the `example_create_views.py` 
script to create the views that the various scripts and webpages use.

### Ubuntu

On Ubuntu, you may need to do this first to get nltk and pymongo to install:

    sudo apt-get install build-essential python-dev

### Setup NLTK

To run some of the examples, you need the `stopwords` corpora for NLTK. To get this, first
enter the python console.  Then do `import nltk`.  Then `nltk.download()`.  Then follow the
instructions and download the `stopwords` library.  To the same thing for the `punkt` library.

Testing
-------

To verify it all works, run the `test.py` script:

    python test.py 

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

### Example Scripts

Run the `example_word_counts.py` script to populate your database with recent stories, 
including a column that is the total number of words in the extracted text received via
the API.

Run the `example_realtime.py` script from a cron job to continuously fetch the latest
stories from MediaCloud and save them to your database (with an extracted text word count).
Make sure the user it runs under has the nltk libraries installed, otherwise you'll be stuck
for a while!

The website in `example-web-server` gives you a view of the word count data saved 
by the `example_realtime.py` script. Check out the readme in that directory for more info.

