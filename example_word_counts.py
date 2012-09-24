#! /usr/bin/env python

import ConfigParser
import json
from pubsub import pub
import nltk

from mediacloud.api import MediaCloud
from mediacloud.storage import StoryDatabase

config = ConfigParser.ConfigParser()
config.read('mc-client.config')

# set up a connection to a local DB
db = StoryDatabase('mediacloud', 
  config.get('db','host'),
  config.get('db','port'),
  )

# connect to MC and fetch some articles
mc = MediaCloud( config.get('api','user'), config.get('api','pass') )
#results = mc.storiesSince( db.getMaxStoryId() )
results = mc.recentStories()
print "Fetched "+str(len(results))+" stories"

# This is the callback to run on every story
def addWordCountToStory(db_story, raw_story):
    text = nltk.Text(raw_story['story_text'].encode('utf-8'))
    word_count = len(text)
    db_story['word_count'] = word_count

# set up my callback function that adds word count to the story
pub.subscribe(addWordCountToStory, StoryDatabase.EVENT_PRE_STORY_SAVE)

# save all the stories in the db (this will fire the callback above)
saved = 0
for story in results:
    worked = db.addStory(story)
    if worked:
      saved = saved + 1

print "Saved "+str(saved)+" stories"