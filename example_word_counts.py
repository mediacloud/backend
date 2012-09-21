#! /usr/bin/env python

import ConfigParser
import json

from mediacloud.api import MediaCloud
from mediacloud.storage import StoryDB

config = ConfigParser.ConfigParser()
config.read('mc-client.config')

# set up a connection to a local DB
db = StoryDB('mediacloud')

# connect to MC and fetch some articles
mc = MediaCloud( config.get('api','user'), config.get('api','pass') )
results = mc.storiesSince(88848861)

# save them in the db
for story in results:
    db.addStory(story)
