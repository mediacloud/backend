#! /usr/bin/env python

import ConfigParser
import json
from pubsub import pub
import nltk
import logging

from mediacloud.api import MediaCloud
from mediacloud.storage import *
import mediacloud.examples

'''
This example is meant to be run from a cron job on a server.  It fetches all stories 
created after the latest one it has in it's db.  It saves the metadata for all those to 
a 'mediacloud' database.
'''

STORIES_TO_FETCH = 100

config = ConfigParser.ConfigParser()
config.read('mc-client.config')

# setup logging
logging.basicConfig(filename='mc-realtime.log',level=logging.DEBUG)
log = logging.getLogger('mc-realtime')
log.info("---------------------------------------------------------------------------")

# setup a connection to a local DB
#db = CouchStoryDatabase('mediacloud', config.get('db','host'), config.get('db','port') )
db = MongoStoryDatabase('mediacloud')

# setup the mediacloud connection
mc = MediaCloud( config.get('api','user'), config.get('api','pass') )

max_story_id = db.getMaxStoryId()
results = mc.storiesSince( max_story_id, STORIES_TO_FETCH )
log.info("Fetched "+str(len(results))+" stories (after "+str(max_story_id)+")")

# set up my callback function that adds word count to the story
pub.subscribe(mediacloud.examples.addWordCountToStory, StoryDatabase.EVENT_PRE_STORY_SAVE)

# set up my callback function that adds the language guess to the story
pub.subscribe(mediacloud.examples.addIsEnglishToStory, StoryDatabase.EVENT_PRE_STORY_SAVE)

# set up my callback function that adds the reading grade level to the story
pub.subscribe(mediacloud.examples.addFleshKincaidGradeLevelToStory, StoryDatabase.EVENT_PRE_STORY_SAVE)

# save all the stories in the db
saved = 0
for story in results:
    worked = db.addStory(story)
    if worked:
      saved = saved + 1
    else:
      log.warning("  unable to save story "+str(story['stories_id']))

max_story_id = db.getMaxStoryId()
log.info("Saved "+str(saved)+" stories - new max id "+str(max_story_id))
