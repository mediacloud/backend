MediaCloud Python API Client
============================

This module is an simple *under construction* demonstration MediaCloud api client written 
in Python.  It demonstrates pulling stories via the MediaCloud API, processing them via an 
event subscription to add metadata, and storing all the metadata to a CouchDB document 
database.

Installation
------------

Make sure you have Python > 2.6 (and setuptools) and then install the python dependencies:
    
    easy_install -Z pypubsub
    easy_install nltk
    easy_install couchdb
    
Install and run CouchDB to store article info (created a 'mediacloud' database):

    http://couchdb.apache.org

Copy the `mc-client.config.template` to `mc-client.config` and edit it, putting in the 
API username and password.

### Ubuntu

On Ubuntu, you may need to do this first to get nltk to install:

    sudo aptitude install python-dev

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
    from mediacloud.storage import StoryDatabase
    mc = MediaCloud( api_username, api_password )
    results = mc.recentStories()
    db = StoryDatabase('mediacloud')
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

The website in `example_realtime_website` gives you a view of the word count data saved 
by the `example_realtime.py` script.
