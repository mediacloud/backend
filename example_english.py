#! /usr/bin/env python

import ConfigParser
import json
from pubsub import pub
import nltk

from mediacloud.api import MediaCloud
from mediacloud.storage import *
import mediacloud.examples

'''
This example file fetches the latest 25 stories from MediaCloud and saves their metadata 
to a 'mediacloud' database.  It adds in the extracted word count via a pre-save 
event subscription.
'''

config = ConfigParser.ConfigParser()
config.read('mc-client.config')

# set up a connection to a local DB
#db = CouchStoryDatabase('mediacloud', config.get('db','host'), config.get('db','port') )
db = MongoStoryDatabase('mediacloud')

# connect to MC and fetch some articles
mc = MediaCloud( config.get('api','user'), config.get('api','pass') )
results = mc.recentStories(1)
print "Fetched "+str(len(results))+" stories"

# set up my callback function that adds word count to the story
pub.subscribe(mediacloud.examples.addIsEnglishToStory, CouchStoryDatabase.EVENT_PRE_STORY_SAVE)

# save all the stories in the db (this will fire the callback above)
saved = 0
for story in results:
    worked = db.addStory(story)
    if worked:
      saved = saved + 1

print "Saved "+str(saved)+" stories"