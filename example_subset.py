#! /usr/bin/env python
import sys
import logging
import datetime
import ConfigParser
from mediacloud.api import MediaCloud
from mediacloud.storage import *

'''
Shows how to query mediacloud for a subset of articles.
'''

# setup logging
logfile_name = datetime.datetime.now().strftime('log/%Y%m%d%H%M%S_mc-subset.log')
logging.basicConfig(filename=logfile_name,level=logging.DEBUG)
log = logging.getLogger('mc-subset')
log.info("---------------------------------------------------------------------------")

# setup the mediacloud connection
config = ConfigParser.ConfigParser()
config.read('mc-client.config')
mc = MediaCloud( config.get('api','user'), config.get('api','pass') )

# Step 1: Create the subset
#subset_id = mc.createStorySubset('2012-01-01','2012-01-02',1)
#log.info("Created subset with id of "+str(subset_id))

# Step 2: Check if the subset is ready
#subset_id = 264
#if( mc.isStorySubsetReady(subset_id)):
#  log.info("Subset id "+str(subset_id)+" is ready!")
#else:
#  log.info("Subset id "+str(subset_id)+" is not ready yet")

# Step 3: Insert all the stories into a db
subset_id = 264
db = MongoStoryDatabase('mediacloud')
more_stories = True
saved_story_count = 0
while more_stories:
  stories = mc.allProcessedInSubset(subset_id,1)
  if len(stories)==0:
    more_stories = False
  for story in stories:
    worked = db.addStory(story)
    if worked:
      saved_story_count = saved_story_count + 1
    else:
      log.warning("  unable to save story "+str(story['stories_id']))
log.info("Saved "+str(saved_story_count)+" stories")

sys.exit();
