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
db = StoryDatabase('mediacloud')

# connect to MC and fetch some articles
mc = MediaCloud( config.get('api','user'), config.get('api','pass') )
results = mc.recentStories()

# This is the callback to run on every story
def addWordCountToStory(db_story, raw_story):
    text = nltk.Text(raw_story['story_text'])
    word_count = len(text)
    db_story['word_count'] = word_count

# set up my callback function that adds word count to the story
pub.subscribe(addWordCountToStory, StoryDatabase.EVENT_PRE_STORY_SAVE)

# save all the stories in the db (this will fire the callback above)
for story in results:
    db.addStory(story)
